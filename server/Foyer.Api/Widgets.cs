namespace Foyer;

public record WidgetTask(string Id, string Title, string Meta, bool Late);
public record WidgetToday(DateOnly Date, int Count, int Late, List<WidgetTask> Tasks);
// Ligne du widget Courses : intertitre de rayon (Id null) ou article à cocher.
public record WidgetRow(string? Id, string Text, string? Qty);
public record WidgetShopping(string List, string When, int Left, int Done, List<WidgetRow> Rows);
// Ligne du widget Agenda : en-tête de jour (Id null, Time null) ou élément (tâche/événement).
public record WidgetAgendaRow(string? Id, string Text, string? Time, bool IsEvent);
public record WidgetData(WidgetToday Today, WidgetShopping Shopping, List<WidgetAgendaRow> Agenda);

// Widgets Android : des lignes prêtes à afficher, pour que le code natif ne fasse que du rendu.
public static class Widgets
{
    public const int MaxTasks = 10;
    public const int MaxAgenda = 12;
    static readonly string[] Wd = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."];
    static readonly string[] Mo = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."];

    public static WidgetData Build(Household h, Member me, DateTimeOffset now)
    {
        var today = Rules.Today(h, now);
        var tasks = Notify.TodayFor(h, me, today);
        return new(new WidgetToday(today, tasks.Count, tasks.Count(t => t.DueDate < today),
            [.. tasks.Take(MaxTasks).Select(t => new WidgetTask(t.Id, t.Title, Meta(h, t, today), t.DueDate < today))]),
            ShoppingOf(h, today), AgendaOf(h, today, now));
    }

    static string DayLabel(DateOnly day, DateOnly today) =>
        day == today ? "Aujourd’hui"
        : day == today.AddDays(1) ? "Demain"
        : $"{Wd[((int)day.DayOfWeek + 6) % 7]} {day.Day} {Mo[day.Month - 1]}";

    // Agenda : prochains événements et tâches datées (14 jours), groupés par jour.
    static List<WidgetAgendaRow> AgendaOf(Household h, DateOnly today, DateTimeOffset now)
    {
        var tz = TimeZoneInfo.FindSystemTimeZoneById(h.TimeZone);
        var horizon = today.AddDays(14);
        var items = new List<(DateOnly Day, int Min, bool AllDay, string Id, string Title, bool IsEvent)>();
        foreach (var t in h.Tickets)
        {
            if (Rules.Closed(t) || t.DueDate is not { } due || due < today || due >= horizon) continue;
            items.Add((due, t.StartMinute ?? -1, t.StartMinute is null, t.Id, t.Title, false));
        }
        foreach (var e in h.Events)
        {
            var local = TimeZoneInfo.ConvertTime(e.Start, tz);
            var day = DateOnly.FromDateTime(local.DateTime);
            if (day < today || day >= horizon) continue;
            items.Add((day, e.AllDay ? -1 : local.Hour * 60 + local.Minute, e.AllDay, e.Id, e.Title, true));
        }
        items.Sort((a, b) => a.Day != b.Day ? a.Day.CompareTo(b.Day) : a.Min.CompareTo(b.Min));
        var rows = new List<WidgetAgendaRow>();
        DateOnly? last = null;
        foreach (var it in items.Take(MaxAgenda))
        {
            if (last != it.Day) { rows.Add(new(null, DayLabel(it.Day, today), null, false)); last = it.Day; }
            rows.Add(new(it.Id, it.Title, it.AllDay ? "journée" : $"{it.Min / 60:D2}:{it.Min % 60:D2}", it.IsEvent));
        }
        return rows;
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
