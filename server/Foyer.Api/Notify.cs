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

    // Tâche confiée par quelqu’un d’autre ; jamais pour soi-même ni pour l’automatisation.
    public static void Assigned(Household h, Ticket t, string memberId, string actor, DateTimeOffset now)
    {
        if (actor == "system" || memberId == actor || Rules.Closed(t)) return;
        var when = When(t.DueDate ?? t.StartDate, Rules.Today(h, now));
        h.Notifications.Add(new()
        {
            MemberId = memberId, Kind = "assign", TicketId = t.Id, ActorId = actor,
            Title = $"{FirstName(h, actor)} vous a confié une tâche",
            Body = when == null ? t.Title : $"{t.Title} · {when}",
            CreatedAt = now, NextAttempt = now, ExpiresAt = now.AddDays(3),
        });
    }
}
