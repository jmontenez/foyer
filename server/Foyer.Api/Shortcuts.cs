namespace Foyer;

// Raccourci : tâche type du foyer, lancée d’un toucher (et, plus tard, répétée automatiquement).
public sealed class Shortcut
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    // Identifiant stable des raccourcis pré-chargés (null pour ceux créés par le foyer).
    public string? SeedKey { get; set; }
    public string Title { get; set; } = "";
    public string Description { get; set; } = "";
    public string Kind { get; set; } = "obligation";
    public string Priority { get; set; } = "normal";
    public List<string> TagIds { get; set; } = [];
    public List<string> Checklist { get; set; } = [];
    // Échéance en jours à partir du lancement (null = sans date).
    public int? DueInDays { get; set; }
    // launcher = qui lance ; member = AssigneeId ; none = personne ; rotation = à tour de rôle.
    public string Assign { get; set; } = "launcher";
    public string? AssigneeId { get; set; }
    public int Order { get; set; }
    public RepeatRule? Repeat { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public record ShortcutSummary(string Id, string? SeedKey, string Title, string Description, string Kind, string Priority,
    List<string> TagIds, List<string> Checklist, int? DueInDays, string Assign, string? AssigneeId, int Order,
    DateTimeOffset? LastDoneAt, string? OpenTicketId, int Uses, RepeatRule? Repeat = null, DateOnly? NextDate = null);

public record ShortcutInput(string Title, string? Description, string Kind, string Priority, List<string> TagIds,
    List<string> Checklist, int? DueInDays, string Assign, string? AssigneeId, RepeatRule? Repeat = null);

public static class Shortcuts
{
    public const int Max = 40;
    static readonly HashSet<string> AssignModes = ["launcher", "member", "none", "rotation"];

    public static void Validate(Household h, ShortcutInput i)
    {
        if (i.TagIds is null || i.Checklist is null) throw new RuleException("Champs de raccourci manquants.");
        if (string.IsNullOrWhiteSpace(i.Title) || i.Title.Length > 160 || (i.Description?.Length ?? 0) > 4000) throw new RuleException("Titre requis (160 caractères maximum), description limitée à 4 000.");
        if (i.Kind is not ("obligation" or "wish") || i.Priority is not ("low" or "normal" or "high" or "urgent")) throw new RuleException("Type ou priorité invalide.");
        if (i.TagIds.Any(id => !h.Tags.Any(t => t.Id == id))) throw new RuleException("Tag inconnu.");
        if (i.Checklist.Count > 20 || i.Checklist.Any(c => string.IsNullOrWhiteSpace(c) || c.Length > 300)) throw new RuleException("Checklist limitée à 20 étapes.");
        if (i.DueInDays is < 0 or > 60) throw new RuleException("Échéance entre aujourd’hui et 60 jours.");
        if (!AssignModes.Contains(i.Assign)) throw new RuleException("Attribution inconnue.");
        if (i.Assign == "member" && !h.Members.Any(m => m.Id == i.AssigneeId)) throw new RuleException("Membre inconnu.");
        Recurrence.Validate(i.Repeat);
    }

    public static void Apply(Shortcut s, ShortcutInput i)
    {
        s.Title = i.Title.Trim(); s.Description = i.Description?.Trim() ?? ""; s.Kind = i.Kind; s.Priority = i.Priority;
        s.TagIds = i.TagIds.Distinct().ToList(); s.Checklist = i.Checklist.Select(c => c.Trim()).ToList();
        s.DueInDays = i.DueInDays; s.Assign = i.Assign; s.AssigneeId = i.Assign == "member" ? i.AssigneeId : null;
        // Nouvelle semaine de référence quand la répétition change de rythme ou s’active.
        var anchor = s.Repeat is { } old && i.Repeat is { } r && old.Mode == r.Mode && old.Every == r.Every && old.Active == r.Active ? old.Anchor : null;
        s.Repeat = i.Repeat;
        if (s.Repeat != null) s.Repeat.Anchor = anchor ?? DateOnly.FromDateTime(DateTime.UtcNow);
    }

    // Qui reçoit la tâche lancée par [launcher]. À tour de rôle : l’autre membre que la dernière fois.
    public static List<string> Assignees(Household h, Shortcut s, string launcher)
    {
        switch (s.Assign)
        {
            case "none": return [];
            case "member": return h.Members.Any(m => m.Id == s.AssigneeId) ? [s.AssigneeId!] : [launcher];
            case "rotation":
                var last = h.Tickets.Where(t => t.ShortcutId == s.Id && t.Assignees.Count == 1).OrderByDescending(t => t.CreatedAt).FirstOrDefault();
                var other = last == null ? null : h.Members.FirstOrDefault(m => m.Id != last.Assignees[0]);
                return [other?.Id ?? launcher];
            default: return [launcher];
        }
    }

    // Crée la tâche du raccourci, avec les règles habituelles des tickets.
    // Raccourci « Faire les courses » : tâche Courses, qui peut reprendre la liste en cours.
    public static Ticket Launch(Household h, Shortcut s, string launcher, DateTimeOffset now, bool withList = false)
    {
        var today = Rules.Today(h, now);
        var input = new TicketInput(s.Title, s.Description, s.Kind, s.Priority, "todo", null,
            s.DueInDays is { } d ? today.AddDays(d) : null, Assignees(h, s, launcher), [],
            s.TagIds.Where(id => h.Tags.Any(t => t.Id == id)).ToList(),
            s.Checklist.Select((text, i) => new CheckItem($"s{i}", text, false)).ToList());
        var t = new Ticket { Number = h.Tickets.Select(t => t.Number).DefaultIfEmpty(0).Max() + 1, ShortcutId = s.Id, CreatedAt = now, UpdatedAt = now };
        Rules.Apply(h, t, input, launcher, now, true);
        t.Shopping = s.SeedKey == "groceries";
        if (withList && t.Shopping) Shopping.AttachDraft(h, t);
        h.Tickets.Add(t);
        return t;
    }

    // « Annuler » juste après un toucher : seulement la tâche qu’on vient de lancer, intacte,
    // par la même personne et dans les 5 minutes. Sinon on garde l’historique (abandonner la tâche).
    public static void UndoLaunch(Household h, Ticket t, string member, DateTimeOffset now)
    {
        if (t.ShortcutId == null || t.Version != 1 || t.CreatedAt < now.AddMinutes(-5) || t.History.FirstOrDefault()?.ActorId != member || t.Comments.Count > 0 || t.Images.Count > 0)
            throw new RuleException("Cette tâche ne peut plus être annulée ; abandonnez-la si besoin.", 409);
        if (t.Shopping) Shopping.ReturnUnbought(h, t, toDraft: true);
        h.Tickets.Remove(t);
    }

    // Pour l’affichage : dernière réalisation, occurrence encore ouverte, nombre d’utilisations.
    public static ShortcutSummary Summary(Household h, Shortcut s) => Summary(h, s, DateTimeOffset.UtcNow);

    public static ShortcutSummary Summary(Household h, Shortcut s, DateTimeOffset now)
    {
        var mine = h.Tickets.Where(t => t.ShortcutId == s.Id).ToList();
        return new(s.Id, s.SeedKey, s.Title, s.Description, s.Kind, s.Priority, s.TagIds, s.Checklist, s.DueInDays, s.Assign, s.AssigneeId, s.Order,
            mine.Where(t => t.StageId == "done").Max(t => t.ClosedAt),
            mine.Where(t => !Rules.Closed(t)).OrderBy(t => t.CreatedAt).Select(t => t.Id).FirstOrDefault(),
            mine.Count, s.Repeat, Recurrence.Preview(h, s, now));
    }

    // Raccourcis courants, chargés une seule fois par foyer (supprimables, jamais réinsérés).
    public static void SeedOnce(Household h)
    {
        if (h.ShortcutsSeeded) return;
        h.ShortcutsSeeded = true;
        string[] Tag(params string[] names) => [.. names.Select(n => h.Tags.FirstOrDefault(t => t.Name == n)?.Id).OfType<string>()];
        (string key, string title, string[] tags, string[] steps)[] seeds =
        [
            ("laundry", "Faire une lessive", Tag("Entretien"), ["Trier le linge", "Lancer la machine", "Étendre ou sécher", "Plier et ranger"]),
            ("bins", "Sortir les poubelles", Tag("Entretien"), []),
            ("groceries", "Faire les courses", Tag("Courses"), []),
            ("vacuum", "Passer l’aspirateur", Tag("Entretien", "Intérieur"), []),
            ("sheets", "Changer les draps", Tag("Entretien"), ["Défaire le lit", "Lancer les draps", "Refaire le lit"]),
            ("bathroom", "Nettoyer la salle de bain", Tag("Entretien", "Intérieur"), ["Lavabo et miroir", "Douche ou baignoire", "Toilettes", "Sol"]),
            ("dishwasher", "Vider le lave-vaisselle", Tag("Cuisine"), []),
            ("plants", "Arroser les plantes", Tag("Intérieur"), []),
        ];
        var order = h.Shortcuts.Count;
        foreach (var (key, title, tags, steps) in seeds)
        {
            if (h.Shortcuts.Any(s => s.SeedKey == key)) continue;
            h.Shortcuts.Add(new Shortcut { SeedKey = key, Title = title, TagIds = [.. tags], Checklist = [.. steps], DueInDays = 0, Order = order++ });
        }
    }
}
