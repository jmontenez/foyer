using System.Text.Json;
namespace Foyer;

public sealed class Household
{
    public int SchemaVersion { get; set; } = 1;
    public long Revision { get; set; }
    public string TimeZone { get; set; } = "Europe/Paris";
    public bool Maintenance { get; set; }
    public List<Member> Members { get; set; } = [];
    public List<Stage> Stages { get; set; } = [new("todo", "À faire", "todo", 0), new("doing", "En cours", "doing", 1), new("waiting", "En attente / Bloqué", "waiting", 2)];
    public List<Tag> Tags { get; set; } = Defaults.Tags();
    public List<Ticket> Tickets { get; set; } = [];
    public List<LoginSession> Sessions { get; set; } = [];
    public List<Device> Devices { get; set; } = [];
    public List<Notification> Notifications { get; set; } = [];
    // Dernier versionCode Android annoncé par notification : une seule annonce par version.
    public long AnnouncedAndroidVersion { get; set; }
    public List<Shortcut> Shortcuts { get; set; } = [];
    public bool ShortcutsSeeded { get; set; }
}
public sealed class Member
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Subject { get; set; } = "";
    public string Name { get; set; } = "";
    public string Email { get; set; } = "";
    public string PaletteId { get; set; } = "sage";
    // Jetons de design choisis par le membre (apparence propre à chacun).
    public string FontId { get; set; } = "system";
    public string ListStyle { get; set; } = "cards";
    public string Density { get; set; } = "comfortable";
    public string Corners { get; set; } = "soft";
    public string DigestTime { get; set; } = "08:00";
    public bool DigestEnabled { get; set; } = true;
    public string? LastDigestDate { get; set; }
}
public record Stage(string Id, string Name, string Category, int Order);
public record Tag(string Id, string Name, string Color);
public sealed class Ticket
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public int Number { get; set; }
    public int Version { get; set; } = 1;
    public string Title { get; set; } = "";
    public string Description { get; set; } = "";
    public string Kind { get; set; } = "obligation";
    public string Priority { get; set; } = "normal";
    public string StageId { get; set; } = "backlog";
    public DateOnly? StartDate { get; set; }
    public DateOnly? DueDate { get; set; }
    public List<string> Assignees { get; set; } = [];
    public List<string> Performers { get; set; } = [];
    public List<string> TagIds { get; set; } = [];
    public List<CheckItem> Checklist { get; set; } = [];
    public List<Comment> Comments { get; set; } = [];
    public List<Attachment> Images { get; set; } = [];
    public List<Activity> History { get; set; } = [];
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? ClosedAt { get; set; }
    // Raccourci d’origine (null pour une tâche créée à la main).
    public string? ShortcutId { get; set; }
}
public record CheckItem(string Id, string Text, bool Done);
public record Comment(string Id, string AuthorId, string Text, DateTimeOffset At);
public record Attachment(string Id, string FileName, string Sha256, long Bytes, DateTimeOffset At);
public record Activity(string Id, string ActorId, string Action, string Detail, DateTimeOffset At);
public record LoginSession(string Hash, string MemberId, string DeviceName, DateTimeOffset CreatedAt, DateTimeOffset ExpiresAt);
// AppVersion : versionCode Android déclaré par l’appareil (absent pour les versions antérieures).
public record Device(string Id, string MemberId, string SessionHash, string Token, DateTimeOffset UpdatedAt, long? AppVersion = null);
public sealed class Notification
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string MemberId { get; set; } = "";
    public string Kind { get; set; } = "";
    public string Title { get; set; } = "";
    public string? TicketId { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset ExpiresAt { get; set; } = DateTimeOffset.UtcNow.AddDays(7);
    public DateTimeOffset NextAttempt { get; set; } = DateTimeOffset.UtcNow;
    public int Attempts { get; set; }
    public List<string> DeliveredDeviceIds { get; set; } = [];
    public bool Finished { get; set; }
    // Annonce de mise à jour : seuls les appareils de version inférieure (ou inconnue) la reçoivent.
    public long? BelowVersion { get; set; }
}
public record TicketInput(string Title, string Description, string Kind, string Priority, string StageId,
    DateOnly? StartDate, DateOnly? DueDate, List<string> Assignees, List<string> Performers,
    List<string> TagIds, List<CheckItem> Checklist, int Version = 0, string? ShortcutId = null);
public sealed class RuleException(string message, int status = 400) : Exception(message) { public int Status { get; } = status; }
public static class Defaults
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public static List<Tag> Tags() => new[] { "Bricolage", "Intérieur", "Extérieur", "Cuisine", "Santé", "Famille", "Administratif", "Courses", "Entretien", "Voiture", "Vacances", "Finances" }
        .Select((name, i) => new Tag($"tag-{i}", name, new[] { "#B86545", "#557B6E", "#9272A3", "#B18A38" }[i % 4])).ToList();
}
public static class Rules
{
    public static bool Closed(Ticket t) => t.StageId is "done" or "abandoned";
    public static DateOnly Today(Household h, DateTimeOffset now) => DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(now, TimeZoneInfo.FindSystemTimeZoneById(h.TimeZone)).DateTime);
    public static bool TodayView(Household h, Ticket t, DateOnly today) => !Closed(t) &&
        (t.StartDate <= today || t.DueDate <= today || h.Stages.Any(s => s.Id == t.StageId && s.Category == "doing"));
    public static bool WeekView(Household h, Ticket t, DateOnly today)
    {
        var end = today.AddDays(6 - (((int)today.DayOfWeek + 6) % 7));
        return !Closed(t) && (t.StartDate <= end || t.DueDate <= end || h.Stages.Any(s => s.Id == t.StageId && s.Category == "doing"));
    }
    public static void Event(Ticket t, string actor, string action, string detail, DateTimeOffset now)
    {
        t.History.Add(new(Guid.NewGuid().ToString("N"), actor, action, detail, now)); t.UpdatedAt = now;
    }
    public static void Apply(Household h, Ticket t, TicketInput i, string actor, DateTimeOffset now, bool create = false)
    {
        if (i.Description is null || i.Assignees is null || i.Performers is null || i.TagIds is null || i.Checklist is null || i.Checklist.Any(c => c is null)) throw new RuleException("Champs de ticket manquants.");
        if (!create && i.Version != t.Version) throw new RuleException("Ce ticket a été modifié. Rechargez-le avant de réessayer.", 409);
        if (string.IsNullOrWhiteSpace(i.Title) || i.Title.Length > 160 || i.Description.Length > 12000) throw new RuleException("Titre requis (160 caractères maximum) ; description limitée à 12 000 caractères.");
        if (i.Kind is not ("obligation" or "wish") || i.Priority is not ("low" or "normal" or "high" or "urgent")) throw new RuleException("Type ou priorité invalide.");
        if (!h.Stages.Any(s => s.Id == i.StageId) && i.StageId is not ("backlog" or "done" or "abandoned")) throw new RuleException("Étape inconnue.");
        if (i.StartDate > i.DueDate) throw new RuleException("Le début doit précéder l’échéance.");
        if (i.Assignees.Concat(i.Performers).Any(id => !h.Members.Any(m => m.Id == id))) throw new RuleException("Membre inconnu.");
        if (i.StageId == "done" && i.Performers.Distinct().Count() is < 1 or > 2) throw new RuleException("Choisissez qui a réalisé cette tâche.");
        if (i.TagIds.Any(id => !h.Tags.Any(tag => tag.Id == id))) throw new RuleException("Tag inconnu.");
        if (i.Checklist.Count > 100 || i.Checklist.Any(c => string.IsNullOrWhiteSpace(c.Text) || c.Text.Length > 300) || i.Checklist.Select(c => c.Id).Distinct().Count() != i.Checklist.Count) throw new RuleException("Checklist invalide.");
        var performers = i.StageId == "done" ? i.Performers.Distinct().ToList() : new List<string>();
        if (create)
        {
            Event(t, actor, "created", "Ticket créé", now);
            if (performers.Count > 0) Event(t, actor, "performers", JsonSerializer.Serialize(new { before = Array.Empty<string>(), after = performers }, Defaults.Json), now);
        }
        else
        {
            if (t.StageId != i.StageId) Event(t, actor, "stage", $"{t.StageId} → {i.StageId}", now);
            if (!t.Assignees.SequenceEqual(i.Assignees)) Event(t, actor, "assignees", JsonSerializer.Serialize(new { before = t.Assignees, after = i.Assignees }, Defaults.Json), now);
            if (!t.Performers.SequenceEqual(performers)) Event(t, actor, "performers", JsonSerializer.Serialize(new { before = t.Performers, after = performers }, Defaults.Json), now);
            if (t.StartDate != i.StartDate || t.DueDate != i.DueDate) Event(t, actor, "dates", $"{t.StartDate}/{t.DueDate} → {i.StartDate}/{i.DueDate}", now);
            if (JsonSerializer.Serialize(t.Checklist) != JsonSerializer.Serialize(i.Checklist)) Event(t, actor, "checklist", JsonSerializer.Serialize(new { before = t.Checklist, after = i.Checklist }, Defaults.Json), now);
            if (t.Title != i.Title || t.Description != i.Description || t.Priority != i.Priority || t.Kind != i.Kind || !t.TagIds.SequenceEqual(i.TagIds)) Event(t, actor, "edited", "Contenu du ticket modifié", now);
            t.Version++;
        }
        t.Title = i.Title.Trim(); t.Description = i.Description; t.Kind = i.Kind; t.Priority = i.Priority; t.StageId = i.StageId;
        t.StartDate = i.StartDate; t.DueDate = i.DueDate; t.Assignees = i.Assignees.Distinct().ToList(); t.Performers = i.StageId == "done" ? i.Performers.Distinct().ToList() : [];
        t.TagIds = i.TagIds.Distinct().ToList(); t.Checklist = i.Checklist; t.UpdatedAt = now;
        t.ClosedAt = Closed(t) ? t.ClosedAt ?? now : null;
    }
    // Appareils du destinataire concernés par une notification.
    public static IEnumerable<Device> Recipients(Household h, Notification n) =>
        h.Devices.Where(d => d.MemberId == n.MemberId && (n.BelowVersion is not { } below || d.AppVersion is not { } version || version < below));

    // Annonce une version Android publiée plus récente que la dernière annoncée, aux seuls membres
    // ayant un appareil en retard ; une annonce encore en attente est remplacée par la nouvelle.
    public static void AnnounceUpdate(Household h, long? versionCode, DateTimeOffset now)
    {
        if (h.Maintenance || versionCode is not { } version || version <= h.AnnouncedAndroidVersion) return;
        h.AnnouncedAndroidVersion = version;
        foreach (var old in h.Notifications.Where(n => n.Kind == "update" && !n.Finished)) old.Finished = true;
        foreach (var m in h.Members)
        {
            var n = new Notification { MemberId = m.Id, Kind = "update", Title = "Une nouvelle version de Foyer est disponible", CreatedAt = now, ExpiresAt = now.AddDays(3), NextAttempt = now, BelowVersion = version };
            if (Recipients(h, n).Any()) h.Notifications.Add(n);
        }
    }
    public static void Schedule(Household h, DateTimeOffset now)
    {
        if (h.Maintenance) return;
        var local = TimeZoneInfo.ConvertTime(now, TimeZoneInfo.FindSystemTimeZoneById(h.TimeZone));
        var today = DateOnly.FromDateTime(local.DateTime);
        var moved = h.Tickets.Where(t => t.StageId == "backlog" && t.StartDate <= today).ToList();
        foreach (var t in moved) { t.StageId = "todo"; t.Version++; Event(t, "system", "stage", "Date de début atteinte : À faire", now); }
        foreach (var m in h.Members)
        {
            var mine = moved.Where(t => t.Assignees.Count == 0 || t.Assignees.Contains(m.Id)).ToList();
            if (mine.Count > 0) h.Notifications.Add(new() { MemberId = m.Id, Kind = "start", Title = mine.Count == 1 ? $"À faire : {mine[0].Title}" : $"{mine.Count} tâches sont à faire", TicketId = mine.Count == 1 ? mine[0].Id : null, CreatedAt = now, ExpiresAt = now.AddDays(1), NextAttempt = now });
            if (m.DigestEnabled && TimeOnly.TryParseExact(m.DigestTime, "HH:mm", out var at) && TimeOnly.FromDateTime(local.DateTime) >= at && m.LastDigestDate != today.ToString("yyyy-MM-dd"))
            {
                m.LastDigestDate = today.ToString("yyyy-MM-dd");
                h.Notifications.Add(new() { MemberId = m.Id, Kind = "digest", Title = "Votre résumé est prêt", CreatedAt = now, ExpiresAt = now.AddHours(12), NextAttempt = now });
            }
        }
        h.Sessions.RemoveAll(s => s.ExpiresAt <= now);
        h.Devices.RemoveAll(d => !h.Sessions.Any(s => s.Hash == d.SessionHash));
        h.Notifications.RemoveAll(n => n.CreatedAt < now.AddDays(-30));
    }
}

public static class Appearance
{
    public static readonly HashSet<string> PaletteIds = ["sky-orange", "sage", "violet-navy", "rose-plum", "navy-gold", "turquoise-coral", "forest-mint", "terracotta-sand", "cherry-cream", "indigo-ice", "slate-copper",
        "ember-night", "lime-charcoal", "ruby-onyx", "electric-violet", "abyss-cyan", "tomato-teal", "royal-sun", "fuchsia-lemon", "ink-coral"];
    public static readonly HashSet<string> FontIds = ["system", "grotesk", "serif", "manrope"];
    public static readonly HashSet<string> ListStyles = ["cards", "rows"];
    public static readonly HashSet<string> Densities = ["comfortable", "compact"];
    public static readonly HashSet<string> CornerStyles = ["soft", "sharp"];
    public static void Apply(Member member, string? paletteId) => Apply(member, new AppearanceInput(paletteId));
    // Chaque jeton est facultatif (les anciennes versions n’envoient que la palette) ; tout est validé avant d’appliquer.
    public static void Apply(Member member, AppearanceInput input)
    {
        if (input.PaletteId is null && input.FontId is null && input.ListStyle is null && input.Density is null && input.Corners is null) throw new RuleException("Palette inconnue.");
        if (input.PaletteId is not null && !PaletteIds.Contains(input.PaletteId)) throw new RuleException("Palette inconnue.");
        if (input.FontId is not null && !FontIds.Contains(input.FontId)) throw new RuleException("Police inconnue.");
        if (input.ListStyle is not null && !ListStyles.Contains(input.ListStyle)) throw new RuleException("Affichage inconnu.");
        if (input.Density is not null && !Densities.Contains(input.Density)) throw new RuleException("Densité inconnue.");
        if (input.Corners is not null && !CornerStyles.Contains(input.Corners)) throw new RuleException("Angles inconnus.");
        member.PaletteId = input.PaletteId ?? member.PaletteId;
        member.FontId = input.FontId ?? member.FontId;
        member.ListStyle = input.ListStyle ?? member.ListStyle;
        member.Density = input.Density ?? member.Density;
        member.Corners = input.Corners ?? member.Corners;
    }
}
