using System.Security.Cryptography;
using System.Text;
namespace Foyer;

public sealed class Settings(IConfiguration c, IWebHostEnvironment env)
{
    public string Origin { get; } = c["PublicOrigin"]?.TrimEnd('/') ?? "http://localhost:5080";
    public string Images { get; } = c["ImagesPath"] ?? Path.Combine(env.ContentRootPath, "images");
    public string Updates { get; } = c["UpdatesPath"] ?? Path.Combine(env.ContentRootPath, "updates");
    public string[] AllowedEmails { get; } = (c["AllowedEmails"] ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    public string[] GoogleAudiences { get; } = (c["GoogleAudiences"] ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    public string? GoogleClientId { get; } = c["GoogleClientId"];
    public string ClientIpHeader { get; } = c["ClientIpHeader"]?.Trim() ?? "";
    public bool WorkersEnabled { get; } = c.GetValue("WorkersEnabled", false);
    public bool PublicDemo { get; } = c.GetValue("PublicDemo", false);
    // Budget général par visiteur et par minute (180 en production ; relevé pour les recettes locales).
    public int RequestsPerMinute { get; } = Math.Clamp(c.GetValue("RequestsPerMinute", 180), 30, 100_000);
    public bool Secure { get; } = !env.IsDevelopment();
    public string ConnectionString { get; } = Connection(c);
    private static string Connection(IConfiguration c)
    {
        if (!string.IsNullOrEmpty(c.GetConnectionString("Database"))) return c.GetConnectionString("Database")!;
        var file = c["DatabasePasswordFile"];
        if (string.IsNullOrEmpty(file)) return "";
        return new Npgsql.NpgsqlConnectionStringBuilder { Host = c["DatabaseHost"] ?? "db", Database = "foyer", Username = "foyer", Password = File.ReadAllText(file).Trim(), IncludeErrorDetail = false }.ConnectionString;
    }
}
public static class Security
{
    public const string Cookie = "foyer_session";
    public static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    // L’en-tête n’est digne de confiance que parce que le port API n’est joignable
    // que depuis la boucle locale de l’hôte (connecteur cloudflared sur le même Mac).
    // Sans en-tête configuré ou avec une valeur non parsable, on retombe sur le pair réseau.
    public static string ClientIp(HttpContext ctx, Settings settings)
    {
        var peer = ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        if (settings.ClientIpHeader.Length == 0) return peer;
        var values = ctx.Request.Headers[settings.ClientIpHeader];
        return values.Count > 0 && System.Net.IPAddress.TryParse(values[^1]?.Trim(), out var ip) ? ip.ToString() : peer;
    }
    public static bool AuthPath(PathString path) => path.StartsWithSegments("/auth") || path.StartsWithSegments("/signin-google");
    public static string? Token(HttpContext ctx)
    {
        var auth = ctx.Request.Headers.Authorization.ToString();
        return auth.StartsWith("Bearer ", StringComparison.Ordinal) ? auth[7..] : ctx.Request.Cookies[Cookie];
    }
    public static Member Member(HttpContext ctx, Household h)
    {
        var token = Token(ctx) ?? throw new RuleException("Connexion requise.", 401);
        var hash = Hash(token);
        var session = h.Sessions.FirstOrDefault(s => s.Hash == hash && s.ExpiresAt > DateTimeOffset.UtcNow) ?? throw new RuleException("Session expirée.", 401);
        return h.Members.FirstOrDefault(m => m.Id == session.MemberId) ?? throw new RuleException("Accès refusé.", 403);
    }
    public static (Member member, string token) Login(Household h, Settings settings, string subject, string email, string name, string device)
    {
        if (!settings.AllowedEmails.Contains(email, StringComparer.OrdinalIgnoreCase)) throw new RuleException("Ce compte n’est pas autorisé.", 403);
        var member = h.Members.FirstOrDefault(m => m.Subject == subject);
        if (member == null)
        {
            if (h.Members.Count >= 2 || h.Members.Any(m => m.Email.Equals(email, StringComparison.OrdinalIgnoreCase))) throw new RuleException("Identité non autorisée.", 403);
            member = new() { Subject = subject, Email = email, Name = name }; h.Members.Add(member);
        }
        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        h.Sessions.Add(new(Hash(token), member.Id, device[..Math.Min(device.Length, 80)], DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddDays(30)));
        return (member, token);
    }
    public static void CheckWrite(HttpContext ctx, Settings settings)
    {
        if (ctx.Request.Headers["X-Foyer-CSRF"] != "1") throw new RuleException("En-tête de protection requis.", 403);
        var origin = ctx.Request.Headers.Origin.ToString();
        if (origin.Length > 0 && origin != settings.Origin) throw new RuleException("Origine refusée.", 403);
        if (!ctx.Request.Headers.Authorization.ToString().StartsWith("Bearer ", StringComparison.Ordinal) && origin.Length == 0)
            throw new RuleException("Origine navigateur requise.", 403);
    }
    public static object PublicMember(Member m) => new { m.Id, m.Name, m.DigestTime, m.DigestEnabled, m.PaletteId, m.FontId, m.ListStyle, m.Density, m.Corners, m.CustomPrimary, m.CustomAccent, m.CustomDark };
}
