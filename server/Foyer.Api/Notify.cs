namespace Foyer;

// Construction des notifications : un titre qui dit qui/quoi, un corps qui dit sur quoi.
public static class Notify
{
    static readonly string[] Weekdays = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"];
    static readonly string[] Months = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."];

    public static string FirstName(Household h, string memberId) =>
        h.Members.FirstOrDefault(m => m.Id == memberId)?.Name.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "Quelqu’un";

    // « aujourd’hui », « demain », « pour samedi », « pour le 3 oct. » (null sans date).
    public static string? When(DateOnly? date, DateOnly today) => date switch
    {
        null => null,
        { } d when d <= today => "aujourd’hui",
        { } d when d == today.AddDays(1) => "demain",
        { } d when d.DayNumber - today.DayNumber < 7 => $"pour {Weekdays[(int)d.DayOfWeek]}",
        { } d => $"pour le {d.Day} {Months[d.Month - 1]}",
    };

    // Titre et corps envoyés au téléphone. Les notifications d’avant (sans corps) gardent
    // l’ancien format : « Foyer » en titre, leur texte en corps.
    public static (string Title, string Body) Text(Notification n) =>
        string.IsNullOrEmpty(n.Body) ? ("Foyer", n.Title) : (n.Title, n.Body);

    // Canal Android selon le type (les anciens APK sans ces canaux prennent le canal par défaut).
    public static string Channel(string kind) => kind switch
    {
        "start" or "digest" => "foyer_reminders",
        "update" => "foyer_updates",
        _ => "foyer_activity",
    };

    // Rafale : une notification du même type pour la même personne depuis moins de 30 minutes
    // est reprise (même identifiant, donc remplacée sur le téléphone) au lieu d’en empiler une autre.
    static readonly TimeSpan Burst = TimeSpan.FromMinutes(30);
    static Notification? Recent(Household h, string memberId, string kind, string? ticketId, DateTimeOffset now) =>
        h.Notifications.LastOrDefault(n => n.MemberId == memberId && n.Kind == kind && n.CreatedAt > now - Burst && (ticketId == null || n.TicketId == ticketId));

    static void Resend(Notification n, DateTimeOffset now, TimeSpan life)
    {
        n.Count++; n.Finished = false; n.DeliveredDeviceIds.Clear(); n.Attempts = 0; n.NextAttempt = now; n.ExpiresAt = now + life;
    }

    // Tâche confiée par quelqu’un d’autre ; jamais pour soi-même ni pour l’automatisation.
    public static void Assigned(Household h, Ticket t, string memberId, string actor, DateTimeOffset now)
    {
        if (actor == "system" || memberId == actor || Rules.Closed(t)) return;
        var when = When(t.DueDate ?? t.StartDate, Rules.Today(h, now));
        var subject = when == null ? t.Title : $"{t.Title} · {when}";
        var who = FirstName(h, actor);
        if (Recent(h, memberId, "assign", null, now) is { } burst && burst.TicketId != t.Id)
        {
            Resend(burst, now, TimeSpan.FromDays(3));
            burst.Subjects.Add(t.Title);
            burst.TicketId = null; // plusieurs tâches : on ouvre Aujourd’hui
            burst.Title = $"{who} vous a confié {burst.Count} tâches";
            burst.Body = string.Join(" · ", burst.Subjects.Take(3)) + (burst.Subjects.Count > 3 ? $" (+{burst.Subjects.Count - 3})" : "");
            return;
        }
        h.Notifications.Add(new()
        {
            MemberId = memberId, Kind = "assign", TicketId = t.Id, ActorId = actor, Subjects = [t.Title],
            Title = $"{who} vous a confié une tâche", Body = subject,
            CreatedAt = now, NextAttempt = now, ExpiresAt = now.AddDays(3),
        });
    }

    // Heures calmes : de 22 h à l’heure du résumé du membre (08:00 si elle tombe l’après-midi).
    // Seules les notifications automatiques attendent ; celles d’une personne partent tout de suite.
    static readonly TimeOnly QuietFrom = new(22, 0);
    static TimeOnly QuietUntil(Member m) =>
        TimeOnly.TryParseExact(m.DigestTime, "HH:mm", out var at) && at <= new TimeOnly(12, 0) ? at : new TimeOnly(8, 0);

    public static bool Quiet(Household h, Member m, DateTimeOffset now)
    {
        var time = TimeOnly.FromDateTime(TimeZoneInfo.ConvertTime(now, Zone(h)).DateTime);
        return time >= QuietFrom || time < QuietUntil(m);
    }

    // Premier instant où le membre peut être notifié : maintenant, ou la fin des heures calmes.
    public static DateTimeOffset WakeAt(Household h, Member m, DateTimeOffset now)
    {
        if (!Quiet(h, m, now)) return now;
        var zone = Zone(h);
        var local = TimeZoneInfo.ConvertTime(now, zone).DateTime;
        var day = TimeOnly.FromDateTime(local) >= QuietFrom ? local.Date.AddDays(1) : local.Date;
        var wake = day.Add(QuietUntil(m).ToTimeSpan());
        return new DateTimeOffset(wake, zone.GetUtcOffset(wake));
    }

    static TimeZoneInfo Zone(Household h) => TimeZoneInfo.FindSystemTimeZoneById(h.TimeZone);

    static string Items(int n) => n == 1 ? "1 article" : $"{n} articles";
    static int Left(Ticket t) => t.Checklist.Count(c => !c.Done);
    // « Courses (12 articles) » pour une tâche Courses avec une liste, sinon le titre.
    static string Label(Ticket t) => t.Shopping && Left(t) > 0 ? $"Courses ({Items(Left(t))})" : t.Title;
    static string Titles(IReadOnlyList<Ticket> tasks) =>
        string.Join(" · ", tasks.Take(3).Select(Label)) + (tasks.Count > 3 ? $" (+{tasks.Count - 3})" : "");

    // Rappel du jour : des tâches du Backlog dont la date de début est arrivée.
    public static Notification Start(Household h, Member m, IReadOnlyList<Ticket> tasks, DateTimeOffset now)
    {
        var one = tasks.Count == 1 ? tasks[0] : null;
        var at = WakeAt(h, m, now);
        return new()
        {
            MemberId = m.Id, Kind = "start", TicketId = one?.Id,
            Title = one != null ? "À faire aujourd’hui" : $"{tasks.Count} tâches à faire aujourd’hui",
            Body = one == null ? Titles(tasks) : one.Shopping && Left(one) > 0 ? $"{one.Title} · {Items(Left(one))}" : one.Title,
            CreatedAt = now, NextAttempt = at, ExpiresAt = at.AddHours(14),
        };
    }

    // Résumé du matin : les tâches du jour du membre (ou sans responsable), retards d’abord.
    // Null quand il n’y a rien à faire : pas de notification vide.
    public static Notification? Digest(Household h, Member m, DateOnly today, DateTimeOffset now)
    {
        var tasks = h.Tickets
            .Where(t => Rules.TodayView(h, t, today) && (t.Assignees.Count == 0 || t.Assignees.Contains(m.Id)))
            .OrderBy(t => t.DueDate < today ? 0 : 1)
            .ThenBy(t => t.Priority switch { "urgent" => 0, "high" => 1, "normal" => 2, _ => 3 })
            .ThenBy(t => t.DueDate ?? t.StartDate ?? DateOnly.MaxValue)
            .ToList();
        if (tasks.Count == 0) return null;
        var late = tasks.Count(t => t.DueDate < today);
        var one = tasks.Count == 1 ? tasks[0] : null;
        return new()
        {
            MemberId = m.Id, Kind = "digest", TicketId = one?.Id,
            Title = one != null ? $"Aujourd’hui : {one.Title}"
                : late > 0 ? $"Aujourd’hui : {tasks.Count} tâches, dont {late} en retard"
                : $"Aujourd’hui : {tasks.Count} tâches",
            Body = one == null ? Titles(tasks)
                : one.DueDate < today ? "En retard"
                : one.Shopping && Left(one) > 0 ? $"{Items(Left(one))} sur la liste"
                : "La seule tâche du jour",
            CreatedAt = now, NextAttempt = now, ExpiresAt = now.AddHours(12),
        };
    }

    // Commentaire : qui, sur quelle tâche, et le début du texte (choix assumé : il transite par
    // FCM, voir docs/securite.md). En rafale, le dernier commentaire reste affiché.
    public static void Commented(Household h, Ticket t, string author, string text, DateTimeOffset now)
    {
        var snippet = text.Trim().ReplaceLineEndings(" ");
        if (snippet.Length > 80) snippet = snippet[..79].TrimEnd() + "…";
        var body = $"{t.Title} — « {snippet} »";
        foreach (var other in h.Members.Where(m => m.Id != author))
        {
            if (Recent(h, other.Id, "comment", t.Id, now) is { } burst)
            {
                Resend(burst, now, TimeSpan.FromDays(7));
                burst.Title = $"{burst.Count} nouveaux commentaires";
                burst.Body = body;
                continue;
            }
            h.Notifications.Add(new()
            {
                MemberId = other.Id, Kind = "comment", TicketId = t.Id, ActorId = author,
                Title = $"{FirstName(h, author)} a commenté", Body = body,
                CreatedAt = now, NextAttempt = now, ExpiresAt = now.AddDays(7),
            });
        }
    }
}
