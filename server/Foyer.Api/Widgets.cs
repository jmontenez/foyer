namespace Foyer;

public record WidgetTask(string Id, string Title, string Meta, bool Late);
public record WidgetToday(DateOnly Date, int Count, int Late, List<WidgetTask> Tasks);
// Ligne du widget Courses : intertitre de rayon (Id null) ou article à cocher.
public record WidgetRow(string? Id, string Text, string? Qty);
public record WidgetShopping(string List, string When, int Left, int Done, List<WidgetRow> Rows);
public record WidgetData(WidgetToday Today, WidgetShopping Shopping);

// Widgets Android : des lignes prêtes à afficher, pour que le code natif ne fasse que du rendu.
public static class Widgets
{
    public const int MaxTasks = 10;

    public static WidgetData Build(Household h, Member me, DateTimeOffset now)
    {
        var today = Rules.Today(h, now);
        var tasks = Notify.TodayFor(h, me, today);
        return new(new WidgetToday(today, tasks.Count, tasks.Count(t => t.DueDate < today),
            [.. tasks.Take(MaxTasks).Select(t => new WidgetTask(t.Id, t.Title, Meta(h, t, today), t.DueDate < today))]),
            ShoppingOf(h, today));
    }

    // Liste en cours (prochaine tâche Courses, sinon le brouillon) : articles à acheter groupés par
    // rayon dans l’ordre du magasin ; les articles cochés ne sont que comptés.
    static WidgetShopping ShoppingOf(Household h, DateOnly today)
    {
        var list = Shopping.Lists(h)[0];
        var left = list.Items.Where(i => !i.Done).ToList();
        var rows = new List<WidgetRow>();
        foreach (var aisle in Shopping.Ordered(h))
        {
            var items = left.Where(i => (Shopping.KnownAisle(i.Aisle) ? i.Aisle : "other") == aisle.Id).ToList();
            if (items.Count == 0) continue;
            rows.Add(new(null, aisle.Name, null));
            rows.AddRange(items.Select(i => new WidgetRow(i.Id, i.Text, i.Qty)));
        }
        var when = list.Date is { } d ? Notify.When(d, today)!.Replace("pour ", "") : "non programmées";
        return new(list.Id, when, left.Count, list.Items.Count - left.Count, rows);
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
