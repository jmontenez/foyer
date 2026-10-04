using Foyer;
using Google.Apis.Auth;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.RateLimiting;
using Npgsql;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Processing;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading.RateLimiting;

if (args.Contains("--healthcheck"))
{
    try { using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(3) }; var response = await client.GetAsync("http://127.0.0.1:8080/health"); Environment.Exit(response.IsSuccessStatusCode ? 0 : 1); }
    catch { Environment.Exit(1); }
    return;
}
var builder = WebApplication.CreateBuilder(args);
// Mounted secret files are resolved by the runtime, never copied into source or client bundles.
foreach (var key in new[] { "ConnectionStrings__Database", "GoogleClientSecret" })
{
    var file = Environment.GetEnvironmentVariable(key + "_FILE");
    if (!string.IsNullOrEmpty(file)) builder.Configuration[key.Replace("__", ":")] = File.ReadAllText(file).Trim();
}
var settings = new Settings(builder.Configuration, builder.Environment);
if (string.IsNullOrWhiteSpace(settings.ConnectionString)) throw new InvalidOperationException("ConnectionStrings__Database is required.");
if (!builder.Environment.IsDevelopment() && (!settings.Origin.StartsWith("https://") || settings.AllowedEmails.Length != 2))
    throw new InvalidOperationException("Production requires HTTPS PublicOrigin and exactly two AllowedEmails.");
if (!builder.Environment.IsDevelopment() && builder.Configuration.GetValue("DemoMode", false)) throw new InvalidOperationException("DemoMode is forbidden in production.");
if (settings.PublicDemo && Demo.Refusal(settings, builder.Configuration) is { } refusal) throw new InvalidOperationException(refusal);
Directory.CreateDirectory(settings.Images);
builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton(settings);
builder.Services.AddSingleton(NpgsqlDataSource.Create(settings.ConnectionString));
builder.Services.AddSingleton<Store>();
builder.Services.AddHostedService<PushWorker>();
builder.Services.AddHostedService<DemoReset>();
builder.Services.AddOpenApi();
builder.Services.Configure<FormOptions>(o => o.MultipartBodyLengthLimit = 10 * 1024 * 1024);
builder.WebHost.ConfigureKestrel(o => o.Limits.MaxRequestBodySize = 11 * 1024 * 1024);
// Derrière Cloudflare Tunnel, le pair réseau est toujours le connecteur : les partitions
// utilisent l’adresse visiteur résolue par Security.ClientIp, et les routes d’authentification
// (coûteuses et sensibles à la force brute) ont leur propre budget, plus strict.
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = 429;
    o.GlobalLimiter = PartitionedRateLimiter.CreateChained(
        PartitionedRateLimiter.Create<HttpContext, string>(ctx => RateLimitPartition.GetFixedWindowLimiter("global:" + Security.ClientIp(ctx, settings), _ => new() { PermitLimit = settings.RequestsPerMinute, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 })),
        PartitionedRateLimiter.Create<HttpContext, string>(ctx => Security.AuthPath(ctx.Request.Path)
            ? RateLimitPartition.GetFixedWindowLimiter("auth:" + Security.ClientIp(ctx, settings), _ => new() { PermitLimit = 30, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 })
            : RateLimitPartition.GetNoLimiter("auth:none")));
});
var googleConfigured = !string.IsNullOrEmpty(settings.GoogleClientId) && !string.IsNullOrEmpty(builder.Configuration["GoogleClientSecret"]);
var auth = builder.Services.AddAuthentication("google-temp").AddCookie("google-temp", o => { o.Cookie.Name = "foyer_google"; o.ExpireTimeSpan = TimeSpan.FromMinutes(5); });
// Le handler .NET interroge userinfo v3 (`email_verified`) ; `verified_email` est le nom v2.
if (googleConfigured)
    auth.AddGoogle(o => { o.ClientId = settings.GoogleClientId!; o.ClientSecret = builder.Configuration["GoogleClientSecret"]!; o.SignInScheme = "google-temp"; o.CallbackPath = "/signin-google"; o.SaveTokens = false; o.Events.OnCreatingTicket = ctx => { if (!(ctx.User.TryGetProperty("email_verified", out var verified) || ctx.User.TryGetProperty("verified_email", out verified)) || verified.ValueKind != JsonValueKind.True) throw new RuleException("Adresse Google non vérifiée.", 403); return Task.CompletedTask; }; o.Events.OnRemoteFailure = ctx => { ctx.Response.Redirect("/?login=failed"); ctx.HandleResponse(); return Task.CompletedTask; }; });
var app = builder.Build();
await app.Services.GetRequiredService<Store>().Initialize();
{
    var store = app.Services.GetRequiredService<Store>();
    if (!await store.Read(h => h.ShortcutsSeeded && h.RepeatsSuggested && h.IngredientsSeeded)) await store.Update(h => { Shortcuts.SeedOnce(h); Recurrence.SuggestOnce(h); Shopping.SeedOnce(h); return true; });
}
app.Use(async (ctx, next) =>
{
    // Canonical configured origin, never trust caller-controlled forwarded headers.
    // Production listener is bound to host loopback behind the local cloudflared connector.
    if (settings.Secure)
    {
        var origin = new Uri(settings.Origin); ctx.Request.Scheme = origin.Scheme; ctx.Request.Host = new(origin.Authority);
    }
    ctx.Response.Headers["X-Content-Type-Options"] = "nosniff";
    ctx.Response.Headers["Referrer-Policy"] = "same-origin";
    ctx.Response.Headers["X-Frame-Options"] = "DENY";
    ctx.Response.Headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()";
    if (settings.Secure) ctx.Response.Headers["Strict-Transport-Security"] = "max-age=31536000";
    if (settings.PublicDemo) ctx.Response.Headers["X-Robots-Tag"] = "noindex, nofollow";
    if (ctx.Request.Path.StartsWithSegments("/api") || Security.AuthPath(ctx.Request.Path)) ctx.Response.Headers.CacheControl = "no-store";
    try { await next(); }
    catch (RuleException ex) { ctx.Response.StatusCode = ex.Status; await ctx.Response.WriteAsJsonAsync(new { error = ex.Message }); }
    catch (BadHttpRequestException) { ctx.Response.StatusCode = 400; await ctx.Response.WriteAsJsonAsync(new { error = "Requête invalide." }); }
    catch (Exception ex) { app.Logger.LogError("Erreur API : {Type}", ex.GetType().Name); ctx.Response.StatusCode = 500; await ctx.Response.WriteAsJsonAsync(new { error = "Le serveur n’a pas pu traiter cette demande." }); }
});
app.UseRateLimiter();
app.UseAuthentication();
app.MapGet("/health", async (Store store) => Results.Ok(new { status = await store.Read(h => h.Maintenance ? "maintenance" : "ok"), version = "0.1.0" }));
var demoLogin = (app.Environment.IsDevelopment() && app.Configuration.GetValue("DemoMode", false)) || settings.PublicDemo;
app.MapGet("/auth/config", () => new { googleClientId = settings.GoogleClientId, demo = demoLogin, publicDemo = settings.PublicDemo });
app.MapGet("/auth/google/start", () => !googleConfigured ? Results.Problem("Connexion Google non configurée.", statusCode: 503) : Results.Challenge(new AuthenticationProperties { RedirectUri = "/auth/google/finish" }, ["Google"]));
app.MapGet("/auth/google/finish", async (HttpContext ctx, Store store) =>
{
    var ticket = await ctx.AuthenticateAsync("google-temp");
    if (!ticket.Succeeded) return Results.Unauthorized();
    var p = ticket.Principal!;
    var login = await store.Update(h => Security.Login(h, settings, p.FindFirstValue(ClaimTypes.NameIdentifier)!, p.FindFirstValue(ClaimTypes.Email)!, p.FindFirstValue(ClaimTypes.Name) ?? "Membre", "Navigateur"));
    await ctx.SignOutAsync("google-temp");
    ctx.Response.Cookies.Append(Security.Cookie, login.token, new CookieOptions { HttpOnly = true, Secure = settings.Secure, SameSite = SameSiteMode.Lax, Path = "/", MaxAge = TimeSpan.FromDays(30) });
    return Results.Redirect("/");
});
app.MapPost("/auth/google/mobile", async (GoogleLogin input, HttpContext ctx, Store store) =>
{
    if (ctx.Request.Headers["X-Foyer-CSRF"] != "1" || ctx.Request.Headers.Origin.Count > 0) throw new RuleException("Connexion mobile requise.", 403);
    if (settings.GoogleAudiences.Length == 0) throw new RuleException("Connexion Google non configurée.", 503);
    if (string.IsNullOrWhiteSpace(input.IdToken) || input.IdToken.Length > 16000) throw new RuleException("Identité Google invalide.", 401);
    GoogleJsonWebSignature.Payload payload;
    try { payload = await GoogleJsonWebSignature.ValidateAsync(input.IdToken, new GoogleJsonWebSignature.ValidationSettings { Audience = settings.GoogleAudiences }); }
    catch (InvalidJwtException) { throw new RuleException("Identité Google invalide.", 401); }
    if (!payload.EmailVerified) throw new RuleException("Adresse Google non vérifiée.", 403);
    var login = await store.Update(h => Security.Login(h, settings, payload.Subject, payload.Email, payload.Name ?? "Membre", "Android"));
    return Results.Ok(new { token = login.token });
});
// Démo locale (développement, boucle locale seulement) ou démonstration publique (instance dédiée, verrouillée au démarrage).
if (demoLogin)
{
    app.MapPost("/auth/demo/{who:int}", async (int who, HttpContext ctx, Store store) =>
    {
        if (who is < 0 or > 1) throw new RuleException("Compte de démonstration inconnu.", 404);
        if (!settings.PublicDemo && (ctx.Connection.RemoteIpAddress is not { } remote || !System.Net.IPAddress.IsLoopback(remote))) throw new RuleException("Démo locale uniquement.", 403);
        Security.CheckWrite(ctx, settings);
        var email = settings.AllowedEmails.ElementAtOrDefault(who) ?? throw new RuleException("Démo non configurée.");
        var login = await store.Update(h => { var l = Security.Login(h, settings, $"demo-{who}", email, who == 0 ? "Camille" : "Alex", settings.PublicDemo ? "Démonstration" : "Démo locale"); if (settings.PublicDemo) Demo.PruneSessions(h); return l; });
        ctx.Response.Cookies.Append(Security.Cookie, login.token, new CookieOptions { HttpOnly = true, Secure = settings.Secure, SameSite = SameSiteMode.Lax, Path = "/" });
        return Results.Ok(new { token = login.token });
    });
}
var api = app.MapGroup("/api/v1");
api.AddEndpointFilter(async (ctx, next) =>
{
    var http = ctx.HttpContext; var store = http.RequestServices.GetRequiredService<Store>();
    await store.Read(h =>
    {
        var member = Security.Member(http, h);
        if (!settings.AllowedEmails.Contains(member.Email, StringComparer.OrdinalIgnoreCase)) throw new RuleException("Compte désactivé.", 403);
        return member;
    });
    if (http.Request.Method is not ("GET" or "HEAD"))
    {
        Security.CheckWrite(http, settings);
        if (await store.Read(h => h.Maintenance)) throw new RuleException("Maintenance en cours. Réessayez plus tard.", 503);
    }
    return await next(ctx);
});
api.MapGet("/state", async (HttpContext ctx, Store store) => await store.Read(h => new
{
    h.Revision,
    h.TimeZone,
    h.Maintenance,
    me = Security.PublicMember(Security.Member(ctx, h)),
    members = h.Members.Select(Security.PublicMember),
    h.Stages,
    h.Tags,
    tickets = h.Tickets.OrderByDescending(t => t.UpdatedAt),
    today = Rules.Today(h, DateTimeOffset.UtcNow),
    todayIds = h.Tickets.Where(t => Rules.TodayView(h, t, Rules.Today(h, DateTimeOffset.UtcNow))).Select(t => t.Id),
    weekIds = h.Tickets.Where(t => Rules.WeekView(h, t, Rules.Today(h, DateTimeOffset.UtcNow))).Select(t => t.Id),
    notificationsEnabled = settings.WorkersEnabled,
    unreadNotifications = Rules.Unread(h, Security.Member(ctx, h)),
    shortcuts = h.Shortcuts.OrderBy(s => s.Order).Select(s => Shortcuts.Summary(h, s)),
    shopping = new { lists = Shopping.Lists(h), ingredients = h.Ingredients, aisles = Shopping.Ordered(h) },
    demo = settings.PublicDemo
}));
// Mise à jour Android : réservée aux membres connectés (filtre du groupe), réponses no-store.
api.MapGet("/app/android", () => Updates.Android(settings.Updates) is { } release ? Results.Ok(release) : Results.NotFound());
api.MapGet("/app/android.apk", () => Updates.Android(settings.Updates) is null
    ? Results.NotFound()
    : Results.File(Path.Combine(settings.Updates, Updates.Apk), "application/vnd.android.package-archive", Updates.Apk, enableRangeProcessing: true));
api.MapGet("/widget", async (HttpContext ctx, Store store) => await store.Read(h => Widgets.Build(h, Security.Member(ctx, h), DateTimeOffset.UtcNow)));
api.MapGet("/revision", async (Store store) => await store.Read(h => new { h.Revision, h.Maintenance }));
api.MapGet("/notifications", async (HttpContext ctx, Store store) => await store.Read(h => { var me = Security.Member(ctx, h); return h.Notifications.Where(n => n.MemberId == me.Id && Rules.Historic(n)).OrderByDescending(n => n.CreatedAt).Select(n => new { n.Id, n.Kind, n.Title, n.Body, n.Count, n.TicketId, n.CreatedAt, unread = Rules.Unseen(me, n) }).ToList(); }));
api.MapPost("/notifications/seen", async (HttpContext ctx, Store store) => await store.Update(h => { Security.Member(ctx, h).NotificationsSeenAt = DateTimeOffset.UtcNow; return Results.NoContent(); }));
api.MapGet("/sessions", async (HttpContext ctx, Store store) => await store.Read(h => { var me = Security.Member(ctx, h); return h.Sessions.Where(s => s.MemberId == me.Id).Select(s => new { id = s.Hash, s.DeviceName, s.CreatedAt, s.ExpiresAt, current = s.Hash == Security.Hash(Security.Token(ctx)!) }).ToList(); }));
api.MapDelete("/sessions/{id}", async (string id, HttpContext ctx, Store store) => await store.Update(h => { var me = Security.Member(ctx, h); h.Sessions.RemoveAll(s => s.Hash == id && s.MemberId == me.Id); h.Devices.RemoveAll(d => d.SessionHash == id && d.MemberId == me.Id); return Results.NoContent(); }));
api.MapPost("/logout", async (HttpContext ctx, Store store) => { await store.Update(h => { var hash = Security.Hash(Security.Token(ctx)!); h.Sessions.RemoveAll(s => s.Hash == hash); h.Devices.RemoveAll(d => d.SessionHash == hash); return true; }); ctx.Response.Cookies.Delete(Security.Cookie); return Results.NoContent(); });
api.MapPut("/appearance", async (AppearanceInput input, HttpContext ctx, Store store) => await store.Update(h =>
{
    var me = Security.Member(ctx, h);
    Appearance.Apply(me, input);
    return Security.PublicMember(me);
}));
api.MapPut("/preferences", async (PreferenceInput input, HttpContext ctx, Store store) => await store.Update(h =>
{
    var me = Security.Member(ctx, h); if (!TimeOnly.TryParseExact(input.DigestTime, "HH:mm", out _)) throw new RuleException("Heure invalide.");
    me.DigestTime = input.DigestTime; me.DigestEnabled = input.DigestEnabled; return Security.PublicMember(me);
}));
api.MapPost("/devices", async (DeviceInput input, HttpContext ctx, Store store) => await store.Update(h =>
{
    var me = Security.Member(ctx, h); if (input.Token is null || input.Token.Length is < 20 or > 4096) throw new RuleException("Jeton appareil invalide.");
    if (settings.PublicDemo) return Results.NoContent(); // aucune notification en démonstration
    h.Devices.RemoveAll(d => d.Token == input.Token || (d.MemberId == me.Id && d.SessionHash == Security.Hash(Security.Token(ctx)!)));
    if (input.AppVersion is <= 0) throw new RuleException("Version d’application invalide.");
    h.Devices.Add(new(Guid.NewGuid().ToString("N"), me.Id, Security.Hash(Security.Token(ctx)!), input.Token, DateTimeOffset.UtcNow, input.AppVersion)); return Results.NoContent();
}));
api.MapPost("/tickets", async (TicketInput input, HttpContext ctx, Store store) => await store.Update(h =>
{
    if (settings.PublicDemo && h.Tickets.Count >= Demo.MaxTickets) throw new RuleException(Demo.Limit, 403);
    var me = Security.Member(ctx, h); var t = new Ticket { Number = h.Tickets.Select(t => t.Number).DefaultIfEmpty(0).Max() + 1 };
    Rules.Apply(h, t, input, me.Id, DateTimeOffset.UtcNow, true);
    if (input.ShortcutId is { } sid && h.Shortcuts.Any(s => s.Id == sid)) t.ShortcutId = sid;
    h.Tickets.Add(t); return t;
}));
api.MapPut("/tickets/{id}", async (string id, TicketInput input, HttpContext ctx, Store store) => await store.Update(h => { var me = Security.Member(ctx, h); var t = Find(h, id); Rules.Apply(h, t, input, me.Id, DateTimeOffset.UtcNow); return t; }));
api.MapPost("/tickets/{id}/comments", async (string id, CommentInput input, HttpContext ctx, Store store) => await store.Update(h =>
{
    var me = Security.Member(ctx, h); var t = Find(h, id);
    if (string.IsNullOrWhiteSpace(input.Text) || input.Text.Length > 6000) throw new RuleException("Commentaire requis, 6 000 caractères maximum.");
    if (settings.PublicDemo && (t.Comments.Count >= Demo.MaxCommentsPerTicket || input.Text.Length > 1000)) throw new RuleException(Demo.Limit, 403);
    var now = DateTimeOffset.UtcNow; t.Comments.Add(new(Guid.NewGuid().ToString("N"), me.Id, input.Text.Trim(), now)); t.Version++;
    Rules.Event(t, me.Id, "comment", "Commentaire ajouté", now);
    Notify.Commented(h, t, me.Id, input.Text, now);
    return t;
}));
api.MapPost("/shortcuts", async (ShortcutInput input, Store store) => await store.Update(h =>
{
    if (h.Shortcuts.Count >= (settings.PublicDemo ? 20 : Shortcuts.Max)) throw new RuleException(settings.PublicDemo ? Demo.Limit : "40 raccourcis maximum.", 403);
    Shortcuts.Validate(h, input);
    var s = new Shortcut { Order = h.Shortcuts.Select(x => x.Order).DefaultIfEmpty(-1).Max() + 1 };
    Shortcuts.Apply(s, input); h.Shortcuts.Add(s); return Shortcuts.Summary(h, s);
}));
api.MapPut("/shortcuts/{id}", async (string id, ShortcutInput input, Store store) => await store.Update(h =>
{
    var s = h.Shortcuts.FirstOrDefault(x => x.Id == id) ?? throw new RuleException("Raccourci introuvable.", 404);
    Shortcuts.Validate(h, input); Shortcuts.Apply(s, input); return Shortcuts.Summary(h, s);
}));
api.MapDelete("/shortcuts/{id}", async (string id, Store store) => await store.Update(h =>
{
    // Les tâches déjà créées restent ; elles perdent seulement le lien.
    if (h.Shortcuts.RemoveAll(x => x.Id == id) == 0) throw new RuleException("Raccourci introuvable.", 404);
    foreach (var t in h.Tickets.Where(t => t.ShortcutId == id)) t.ShortcutId = null;
    return Results.NoContent();
}));
api.MapPut("/shortcuts-order", async (List<string> ids, Store store) => await store.Update(h =>
{
    if (ids is null || ids.Count != h.Shortcuts.Count || ids.Distinct().Count() != ids.Count || ids.Any(id => !h.Shortcuts.Any(s => s.Id == id))) throw new RuleException("Ordre des raccourcis invalide.");
    foreach (var (id, i) in ids.Select((id, i) => (id, i))) h.Shortcuts.First(s => s.Id == id).Order = i;
    return Results.NoContent();
}));
api.MapPost("/tickets/{id}/done", async (string id, HttpContext ctx, Store store) => await store.Update(h =>
{
    var me = Security.Member(ctx, h); var t = Find(h, id);
    Rules.Done(h, t, me.Id, DateTimeOffset.UtcNow);
    return t;
}));
api.MapPost("/tickets/{id}/skip", async (string id, HttpContext ctx, Store store) => await store.Update(h =>
{
    var me = Security.Member(ctx, h); var t = Find(h, id);
    Recurrence.Skip(h, t, me.Id, DateTimeOffset.UtcNow);
    return t;
}));
api.MapPost("/tickets/{id}/undo-launch", async (string id, HttpContext ctx, Store store) => await store.Update(h =>
{
    var me = Security.Member(ctx, h);
    Shortcuts.UndoLaunch(h, Find(h, id), me.Id, DateTimeOffset.UtcNow);
    return Results.NoContent();
}));
api.MapPost("/shortcuts/{id}/launch", async (string id, bool? withList, HttpContext ctx, Store store) => await store.Update(h =>
{
    if (settings.PublicDemo && h.Tickets.Count >= Demo.MaxTickets) throw new RuleException(Demo.Limit, 403);
    var me = Security.Member(ctx, h);
    var s = h.Shortcuts.FirstOrDefault(x => x.Id == id) ?? throw new RuleException("Raccourci introuvable.", 404);
    return Shortcuts.Launch(h, s, me.Id, DateTimeOffset.UtcNow, withList == true);
}));
// Courses : écritures article par article, pour cocher à deux sans conflit de version.
api.MapPost("/shopping/items", async (ShoppingItemInput input, HttpContext ctx, Store store) => await store.Update(h =>
    Shopping.Add(h, input, Security.Member(ctx, h).Id, DateTimeOffset.UtcNow)));
// Import d’une liste collée : analyse sans écrire, puis ajout en une fois des articles validés.
api.MapPost("/shopping/import/preview", async (ShoppingImportInput input, Store store) => await store.Read(h =>
    Shopping.Preview(h, input.List ?? "", input.Text)));
api.MapPost("/shopping/items/batch", async (ShoppingBatchInput input, HttpContext ctx, Store store) => await store.Update(h =>
    Shopping.Import(h, input, Security.Member(ctx, h).Id, DateTimeOffset.UtcNow)));
api.MapPatch("/shopping/items/{list}/{id}", async (string list, string id, ShoppingItemPatch input, HttpContext ctx, Store store) => await store.Update(h =>
    Shopping.Update(h, list, id, input, Security.Member(ctx, h).Id, DateTimeOffset.UtcNow)));
api.MapDelete("/shopping/items/{list}/{id}", async (string list, string id, HttpContext ctx, Store store) => await store.Update(h =>
{
    Shopping.Remove(h, list, id, Security.Member(ctx, h).Id, DateTimeOffset.UtcNow); return Results.NoContent();
}));
api.MapPost("/shopping/{list}/clear-done", async (string list, HttpContext ctx, Store store) => await store.Update(h =>
{
    Shopping.ClearDone(h, list, Security.Member(ctx, h).Id, DateTimeOffset.UtcNow); return Results.NoContent();
}));
api.MapPost("/shopping/{list}/date", async (string list, ShoppingDateInput input, HttpContext ctx, Store store) => await store.Update(h =>
{
    var t = Find(h, list); Shopping.Move(h, t, input.Date, Security.Member(ctx, h).Id, DateTimeOffset.UtcNow); return t;
}));
api.MapPost("/shopping/schedule", async (ShoppingScheduleInput input, HttpContext ctx, Store store) => await store.Update(h =>
{
    if (settings.PublicDemo && input.Mode == "new" && h.Tickets.Count >= Demo.MaxTickets) throw new RuleException(Demo.Limit, 403);
    return Shopping.Schedule(h, input, Security.Member(ctx, h).Id, DateTimeOffset.UtcNow);
}));
api.MapPut("/shopping/ingredients/{name}", async (string name, IngredientInput input, HttpContext ctx, Store store) => await store.Update(h =>
    Shopping.EditIngredient(h, name, input, Security.Member(ctx, h).Id, DateTimeOffset.UtcNow)));
api.MapDelete("/shopping/ingredients/{name}", async (string name, Store store) => await store.Update(h => { Shopping.Forget(h, name); return Results.NoContent(); }));
api.MapPut("/shopping/aisle-order", async (List<string> ids, Store store) => await store.Update(h => { Shopping.ReorderAisles(h, ids); return Results.NoContent(); }));
api.MapPost("/tags", async (TagInput input, Store store) => await store.Update(h =>
{
    if (string.IsNullOrWhiteSpace(input.Name) || input.Name.Length > 40 || (input.Color == null || !System.Text.RegularExpressions.Regex.IsMatch(input.Color, "^#[0-9a-fA-F]{6}$"))) throw new RuleException("Nom ou couleur invalide.");
    if (h.Tags.Any(t => t.Name.Equals(input.Name.Trim(), StringComparison.OrdinalIgnoreCase))) throw new RuleException("Ce tag existe déjà.", 409);
    if (settings.PublicDemo && h.Tags.Count >= Demo.MaxTags) throw new RuleException(Demo.Limit, 403);
    var tag = new Tag(Guid.NewGuid().ToString("N"), input.Name.Trim(), input.Color); h.Tags.Add(tag); return tag;
}));
api.MapPut("/stages", async (StageInput input, Store store) => await store.Update(h =>
{
    if (input.Revision != h.Revision) throw new RuleException("Le foyer a changé. Rechargez avant de modifier les étapes.", 409);
    var stages = input.Stages ?? throw new RuleException("Étapes requises.");
    if (stages.Any(s => s is null || string.IsNullOrWhiteSpace(s.Id) || s.Id.Length > 64)) throw new RuleException("Identifiants d’étapes invalides.");
    if (stages.Count is < 1 or > 12 || stages.Select(s => s.Id).Distinct().Count() != stages.Count || !stages.Any(s => s.Id == "todo" && s.Category == "todo") || stages.Any(s => string.IsNullOrWhiteSpace(s.Name) || s.Name.Length > 40 || s.Category is not ("todo" or "doing" or "waiting") || s.Id is "backlog" or "done" or "abandoned")) throw new RuleException("Étapes invalides. L’étape À faire doit conserver sa fonction.");
    if (h.Tickets.Any(t => !Rules.Closed(t) && t.StageId != "backlog" && !stages.Any(s => s.Id == t.StageId))) throw new RuleException("Déplacez les tickets avant de retirer leur étape.", 409);
    h.Stages = stages.Select((s, i) => s with { Order = i }).ToList(); return h.Stages;
}));
api.MapPost("/tickets/{id}/images", async (string id, HttpContext ctx, Store store) =>
{
    // Aucun fichier d’inconnus hébergé ni décodé sur la démonstration publique.
    if (settings.PublicDemo) throw new RuleException("Les images sont désactivées dans la démonstration.", 403);
    await store.Read(h => Find(h, id));
    var form = await ctx.Request.ReadFormAsync(); var file = form.Files.GetFile("image") ?? throw new RuleException("Image requise.");
    if (file.Length > 10 * 1024 * 1024 || file.Length == 0) throw new RuleException("Image limitée à 10 Mo.");
    using var source = new MemoryStream(); await file.CopyToAsync(source); source.Position = 0;
    Image image;
    try { var info = await Image.IdentifyAsync(source); if ((long)info.Width * info.Height > 40_000_000) throw new RuleException("Image trop grande."); source.Position = 0; image = await Image.LoadAsync(new SixLabors.ImageSharp.Formats.DecoderOptions { MaxFrames = 1 }, source); }
    catch (InvalidImageContentException) { throw new RuleException("Image invalide."); }
    catch (UnknownImageFormatException) { throw new RuleException("Format image non reconnu."); }
    using (image)
    {
        image.Mutate(x => x.AutoOrient().Resize(new ResizeOptions { Mode = ResizeMode.Max, Size = new Size(2048, 2048) }));
        image.Metadata.ExifProfile = null; image.Metadata.IptcProfile = null; image.Metadata.XmpProfile = null;
        var imageId = Guid.NewGuid().ToString("N"); var path = Path.Combine(settings.Images, imageId + ".jpg");
        await image.SaveAsJpegAsync(path);
        var bytes = await File.ReadAllBytesAsync(path); var attachment = new Attachment(imageId, imageId + ".jpg", Convert.ToHexString(SHA256.HashData(bytes)), bytes.Length, DateTimeOffset.UtcNow);
        try { return await store.Update(h => { if (h.Maintenance) throw new RuleException("Maintenance en cours.", 503); var me = Security.Member(ctx, h); var t = Find(h, id); if (t.Images.Count >= 20) throw new RuleException("20 images maximum par ticket."); t.Images.Add(attachment); t.Version++; Rules.Event(t, me.Id, "image", "Image ajoutée", DateTimeOffset.UtcNow); return t; }); }
        catch { File.Delete(path); throw; }
    }
});
api.MapGet("/images/{id}", async (string id, Store store) =>
{
    var image = await store.Read(h => h.Tickets.SelectMany(t => t.Images).FirstOrDefault(i => i.Id == id)) ?? throw new RuleException("Image introuvable.", 404);
    return Results.File(Path.Combine(settings.Images, image.FileName), "image/jpeg");
});
if (app.Environment.IsDevelopment()) app.MapOpenApi();
app.UseDefaultFiles(); app.UseStaticFiles(new StaticFileOptions { OnPrepareResponse = ctx => ctx.Context.Response.Headers.CacheControl = "no-cache" });
app.MapFallback(async ctx => { if (ctx.Request.Path.StartsWithSegments("/api") || ctx.Request.Path.StartsWithSegments("/auth")) { ctx.Response.StatusCode = 404; return; } var index = Path.Combine(app.Environment.WebRootPath ?? Path.Combine(app.Environment.ContentRootPath, "wwwroot"), "index.html"); if (File.Exists(index)) { ctx.Response.ContentType = "text/html"; await ctx.Response.SendFileAsync(index); } else { ctx.Response.StatusCode = 503; await ctx.Response.WriteAsync("Client web non compilé. Consultez docs/installation.md."); } });
app.Run();
static Ticket Find(Household h, string id) => h.Tickets.FirstOrDefault(t => t.Id == id) ?? throw new RuleException("Ticket introuvable.", 404);
public record GoogleLogin(string IdToken);
public record PreferenceInput(string DigestTime, bool DigestEnabled);
public record DeviceInput(string Token, long? AppVersion = null);
public record CommentInput(string Text);
public record TagInput(string Name, string Color);
public record StageInput(List<Stage> Stages, long Revision);
public partial class Program { }

public record AppearanceInput(string? PaletteId, string? FontId = null, string? ListStyle = null, string? Density = null, string? Corners = null);
