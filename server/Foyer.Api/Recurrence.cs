namespace Foyer;

// Répétition d’un raccourci. after = Every jours après la dernière fois (flottant) ;
// weekly = jours Days (1 lundi … 7 dimanche), toutes les Every semaines ; monthly = le jour MonthDay.
public sealed class RepeatRule
{
    public string Mode { get; set; } = "after";
    public int Every { get; set; } = 1;
    public List<int> Days { get; set; } = [];
    public int MonthDay { get; set; } = 1;
    public bool Active { get; set; }
    // Semaine de référence pour « toutes les N semaines » (fixée à l’activation).
    public DateOnly? Anchor { get; set; }
}

public static class Recurrence
{
    public static void Validate(RepeatRule? r)
    {
        if (r is null) return;
        var ok = r.Mode switch
        {
            "after" => r.Every is >= 1 and <= 365,
            "weekly" => r.Every is >= 1 and <= 8 && r.Days.Count is >= 1 and <= 7 && r.Days.All(d => d is >= 1 and <= 7) && r.Days.Distinct().Count() == r.Days.Count,
            "monthly" => r.MonthDay is >= 1 and <= 31,
            _ => false,
        };
        if (!ok) throw new RuleException("Répétition invalide.");
    }

    static DateOnly Monday(DateOnly d) => d.AddDays(-(((int)d.DayOfWeek + 6) % 7));
    static int IsoDay(DateOnly d) => ((int)d.DayOfWeek + 6) % 7 + 1;
    static DateOnly InMonth(int year, int month, int day) => new(year, month, Math.Min(day, DateTime.DaysInMonth(year, month)));

    // Prochaine date planifiée, au plus tôt [earliest] (inclus). Pour « after », [earliest] est
    // déjà « dernière fois + N jours » ; pour les calendriers fixes, jamais une date passée.
    public static DateOnly NextOnOrAfter(RepeatRule r, DateOnly earliest)
    {
        switch (r.Mode)
        {
            case "after":
                return earliest;
            case "weekly":
                var anchor = Monday(r.Anchor ?? earliest);
                for (var d = earliest; ; d = d.AddDays(1))
                {
                    var weeks = (Monday(d).DayNumber - anchor.DayNumber) / 7;
                    if (weeks >= 0 && weeks % r.Every == 0 && r.Days.Contains(IsoDay(d))) return d;
                }
            default:
                var candidate = InMonth(earliest.Year, earliest.Month, r.MonthDay);
                if (candidate < earliest)
                {
                    var next = earliest.AddMonths(1);
                    candidate = InMonth(next.Year, next.Month, r.MonthDay);
                }
                return candidate;
        }
    }

    // Date de la prochaine occurrence après [last] (occurrence précédente close), sinon la première.
    public static DateOnly NextDate(RepeatRule r, Ticket? last, DateOnly today, TimeZoneInfo zone)
    {
        if (last == null) return NextOnOrAfter(r, today);
        if (r.Mode == "after")
        {
            var closed = last.ClosedAt is { } c ? DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(c, zone).DateTime) : today;
            return closed.AddDays(r.Every) is var d && d < today ? today : d;
        }
        // Calendrier fixe : strictement après la date prévue de la précédente, jamais dans le passé.
        var planned = last.StartDate ?? last.DueDate ?? (last.ClosedAt is { } cc ? DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(cc, zone).DateTime) : today);
        var after = planned.AddDays(1);
        return NextOnOrAfter(r, after < today ? today : after);
    }

    // Une occurrence ouverte au plus par raccourci répété : sinon on crée la suivante, avec sa date
    // de début (Backlog ; Rules.Schedule la passe « À faire » et prévient le jour venu).
    public static void Tick(Household h, DateTimeOffset now)
    {
        if (h.Maintenance) return;
        var zone = TimeZoneInfo.FindSystemTimeZoneById(h.TimeZone);
        var today = Rules.Today(h, now);
        foreach (var s in h.Shortcuts.Where(s => s.Repeat is { Active: true }))
        {
            var mine = h.Tickets.Where(t => t.ShortcutId == s.Id).ToList();
            if (mine.Any(t => !Rules.Closed(t))) continue;
            var last = mine.Where(t => t.ClosedAt != null).OrderByDescending(t => t.ClosedAt).FirstOrDefault();
            var date = NextDate(s.Repeat!, last, today, zone);
            Create(h, s, last, date, now);
        }
    }

    static void Create(Household h, Shortcut s, Ticket? last, DateOnly date, DateTimeOffset now)
    {
        // Sans personne qui « lance », « qui le lance » revient à la dernière personne qui l’a fait.
        var assignees = s.Assign switch
        {
            "launcher" => last?.Performers.Take(1).ToList() ?? [],
            "rotation" => Shortcuts.Assignees(h, s, last?.Performers.FirstOrDefault() ?? h.Members.FirstOrDefault()?.Id ?? ""),
            _ => Shortcuts.Assignees(h, s, ""),
        };
        assignees = assignees.Where(id => h.Members.Any(m => m.Id == id)).ToList();
        var input = new TicketInput(s.Title, s.Description, s.Kind, s.Priority, "backlog", date,
            s.DueInDays is { } d ? date.AddDays(d) : null, assignees, [],
            s.TagIds.Where(id => h.Tags.Any(t => t.Id == id)).ToList(),
            s.Checklist.Select((text, i) => new CheckItem($"s{i}", text, false)).ToList());
        var t = new Ticket { Number = h.Tickets.Select(t => t.Number).DefaultIfEmpty(0).Max() + 1, ShortcutId = s.Id, CreatedAt = now, UpdatedAt = now };
        Rules.Apply(h, t, input, "system", now, true);
        // Courses : personne à qui demander, la liste en cours rejoint l’occurrence.
        if (s.SeedKey == "groceries")
        {
            t.Shopping = true;
            try { Shopping.AttachDraft(h, t); } catch (RuleException) { }
        }
        h.Tickets.Add(t);
    }

    // « Passer cette fois » : l’occurrence est close sans être comptée comme faite ; la suivante suit.
    public static void Skip(Household h, Ticket t, string member, DateTimeOffset now)
    {
        var s = h.Shortcuts.FirstOrDefault(x => x.Id == t.ShortcutId);
        if (s?.Repeat is not { Active: true } || Rules.Closed(t)) throw new RuleException("Seule une occurrence répétée en cours peut être passée.", 409);
        t.StageId = "abandoned"; t.ClosedAt = now; t.Version++;
        Rules.Event(t, member, "skip", "Passée cette fois", now);
        if (t.Shopping) Shopping.ReturnUnbought(h, t);
    }

    // Aperçu : date de l’occurrence ouverte, sinon de celle qui sera créée.
    public static DateOnly? Preview(Household h, Shortcut s, DateTimeOffset now)
    {
        if (s.Repeat is not { } r) return null;
        var mine = h.Tickets.Where(t => t.ShortcutId == s.Id).ToList();
        var open = mine.Where(t => !Rules.Closed(t)).OrderBy(t => t.CreatedAt).FirstOrDefault();
        if (open != null) return open.StartDate ?? open.DueDate;
        var last = mine.Where(t => t.ClosedAt != null).OrderByDescending(t => t.ClosedAt).FirstOrDefault();
        return NextDate(r, last, Rules.Today(h, now), TimeZoneInfo.FindSystemTimeZoneById(h.TimeZone));
    }

    // Répétitions suggérées des raccourcis pré-chargés : proposées, jamais activées d’office.
    public static void SuggestOnce(Household h)
    {
        if (h.RepeatsSuggested) return;
        h.RepeatsSuggested = true;
        var suggestions = new Dictionary<string, RepeatRule>
        {
            ["laundry"] = new() { Mode = "after", Every = 3 },
            ["bins"] = new() { Mode = "weekly", Every = 1, Days = [2] },
            ["groceries"] = new() { Mode = "weekly", Every = 1, Days = [6] },
            ["vacuum"] = new() { Mode = "weekly", Every = 1, Days = [6] },
            ["sheets"] = new() { Mode = "weekly", Every = 2, Days = [7] },
            ["bathroom"] = new() { Mode = "weekly", Every = 1, Days = [6] },
            ["dishwasher"] = new() { Mode = "after", Every = 1 },
            ["plants"] = new() { Mode = "after", Every = 4 },
        };
        foreach (var s in h.Shortcuts.Where(s => s.SeedKey != null && s.Repeat == null))
            if (suggestions.TryGetValue(s.SeedKey!, out var r)) s.Repeat = r;
    }
}
