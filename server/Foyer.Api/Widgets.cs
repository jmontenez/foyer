namespace Foyer;

public record WidgetTask(string Id, string Title, string Meta, bool Late);
public record WidgetToday(DateOnly Date, int Count, int Late, List<WidgetTask> Tasks);
public record WidgetData(WidgetToday Today);

// Widgets Android : des lignes prêtes à afficher, pour que le code natif ne fasse que du rendu.
public static class Widgets
{
    public const int MaxTasks = 10;

    public static WidgetData Build(Household h, Member me, DateTimeOffset now)
    {
        var today = Rules.Today(h, now);
        var tasks = Notify.TodayFor(h, me, today);
        return new(new WidgetToday(today, tasks.Count, tasks.Count(t => t.DueDate < today),
            [.. tasks.Take(MaxTasks).Select(t => new WidgetTask(t.Id, t.Title, Meta(h, t, today), t.DueDate < today))]));
    }

    // Libellé court sous le titre : retard, liste de courses, étape en cours.
    static string Meta(Household h, Ticket t, DateOnly today)
    {
        if (t.DueDate < today) return "En retard";
        if (t.Shopping && Notify.Left(t) > 0) return Notify.Items(Notify.Left(t));
        var stage = h.Stages.FirstOrDefault(s => s.Id == t.StageId);
        if (stage?.Category is "doing" or "waiting") return stage.Name;
        return t.DueDate == today ? "Aujourd’hui" : "";
    }
}
