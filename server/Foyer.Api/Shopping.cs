using System.Globalization;
using System.Text;
namespace Foyer;

// Ingrédient connu du foyer : alimente l’accès rapide et la recherche de l’écran Courses.
public sealed class Ingredient
{
    public string Name { get; set; } = "";
    public string Aisle { get; set; } = "other";
    public int Uses { get; set; }
    public string? LastQty { get; set; }
    public DateTimeOffset? LastUsedAt { get; set; }
}

public record Aisle(string Id, string Name);
public record ShoppingList(string Id, string? TicketId, DateOnly? Date, List<CheckItem> Items);
public record ShoppingItemInput(string List, string Name, string? Qty, string? Aisle);
public record ShoppingItemPatch(bool? Done, string? Qty, string? Aisle);
public record ShoppingScheduleInput(DateOnly Date, string Mode, string? TargetId);
public record ShoppingDateInput(DateOnly Date);

// Liste de courses : la checklist d’une tâche Courses (Shopping), ou le brouillon du foyer tant
// qu’aucune date n’est programmée. Une seule donnée, cochée depuis l’écran Courses ou la tâche.
public static class Shopping
{
    public const string Draft = "draft";
    public const int MaxItems = 100, MaxIngredients = 500, MaxName = 60, MaxQty = 40;
    public static readonly Aisle[] Aisles =
    [
        new("produce", "Fruits & légumes"), new("bakery", "Boulangerie"), new("dairy", "Crèmerie & œufs"), new("meat", "Viande & poisson"),
        new("savory", "Épicerie salée"), new("sweet", "Épicerie sucrée"), new("drinks", "Boissons"), new("frozen", "Surgelés"),
        new("hygiene", "Hygiène"), new("cleaning", "Entretien"), new("other", "Autre"),
    ];
    static string NewId() => Guid.NewGuid().ToString("N")[..12];
    public static bool KnownAisle(string? id) => Aisles.Any(a => a.Id == id);

    // Clé de comparaison : sans accents ni casse, ligatures dépliées, pluriel en s/x ignoré.
    public static string Key(string name)
    {
        var s = name.Trim().ToLowerInvariant().Replace("œ", "oe").Replace("æ", "ae").Normalize(NormalizationForm.FormD);
        var plain = new StringBuilder();
        foreach (var c in s) if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) plain.Append(c);
        return string.Join(' ', plain.ToString().Split([' ', '-', '\''], StringSplitOptions.RemoveEmptyEntries)
            .Select(w => w.Length > 2 && w[^1] is 's' or 'x' ? w[..^1] : w));
    }

    // Ordre du magasin choisi par le foyer, complété des rayons ajoutés depuis.
    public static List<Aisle> Ordered(Household h) =>
        [.. h.AisleOrder.Select(id => Aisles.FirstOrDefault(a => a.Id == id)).OfType<Aisle>().Concat(Aisles).DistinctBy(a => a.Id)];

    public static void ReorderAisles(Household h, List<string> ids)
    {
        if (ids is null || ids.Count != Aisles.Length || ids.Distinct().Count() != ids.Count || ids.Any(id => !KnownAisle(id))) throw new RuleException("Ordre des rayons invalide.");
        h.AisleOrder = [.. ids];
    }

    static DateOnly? Date(Ticket t) => t.StartDate ?? t.DueDate;
    public static IEnumerable<Ticket> Open(Household h) =>
        h.Tickets.Where(t => t.Shopping && !Rules.Closed(t)).OrderBy(t => Date(t) ?? DateOnly.MaxValue).ThenBy(t => t.CreatedAt);

    // Tâches Courses ouvertes, de la plus proche à la plus lointaine, puis le brouillon.
    public static List<ShoppingList> Lists(Household h) =>
        [.. Open(h).Select(t => new ShoppingList(t.Id, t.Id, Date(t), t.Checklist)), new(Draft, null, null, h.ShoppingDraft)];

    static (List<CheckItem> items, Ticket? ticket) Resolve(Household h, string list)
    {
        if (list == Draft) return (h.ShoppingDraft, null);
        var t = h.Tickets.FirstOrDefault(t => t.Id == list && t.Shopping && !Rules.Closed(t)) ?? throw new RuleException("Liste de courses introuvable.", 404);
        return (t.Checklist, t);
    }

    // Une écriture sur la liste d’une tâche compte comme une modification de la tâche ; les
    // modifications rapprochées d’une même personne ne font qu’une ligne d’historique.
    static void Touched(Ticket? t, string member, DateTimeOffset now)
    {
        if (t == null) return;
        t.Version++;
        if (t.History.LastOrDefault() is { Action: "shopping" } last && last.ActorId == member && last.At > now.AddMinutes(-10))
        {
            t.History[^1] = last with { At = now }; t.UpdatedAt = now;
        }
        else Rules.Event(t, member, "shopping", "Liste de courses mise à jour", now);
    }

    static string? CleanQty(string? qty)
    {
        var q = qty?.Trim();
        if (q?.Length > MaxQty) throw new RuleException($"Quantité limitée à {MaxQty} caractères.");
        return string.IsNullOrEmpty(q) ? null : q;
    }

    public static CheckItem Add(Household h, ShoppingItemInput i, string member, DateTimeOffset now)
    {
        var name = i.Name?.Trim() ?? "";
        if (name.Length is < 1 or > MaxName) throw new RuleException($"Nom d’ingrédient requis ({MaxName} caractères maximum).");
        if (i.Aisle != null && !KnownAisle(i.Aisle)) throw new RuleException("Rayon inconnu.");
        var qty = CleanQty(i.Qty);
        var (items, ticket) = Resolve(h, i.List ?? "");
        var key = Key(name);
        var known = h.Ingredients.FirstOrDefault(x => Key(x.Name) == key);
        var aisle = i.Aisle ?? known?.Aisle ?? "other";
        var index = items.FindIndex(c => Key(c.Text) == key);
        CheckItem item;
        if (index >= 0)
        {
            // Déjà dans la liste : on met à jour l’article plutôt que de créer un doublon.
            item = items[index] with { Qty = qty ?? items[index].Qty, Aisle = aisle, Done = false };
            items[index] = item;
        }
        else
        {
            if (items.Count >= MaxItems) throw new RuleException($"{MaxItems} articles maximum par liste.");
            item = new CheckItem(NewId(), known?.Name ?? name, false, qty, aisle);
            items.Add(item);
        }
        Remember(h, known?.Name ?? name, aisle, qty, index < 0, now);
        Touched(ticket, member, now);
        return item;
    }

    static void Remember(Household h, string name, string aisle, string? qty, bool used, DateTimeOffset now)
    {
        var known = h.Ingredients.FirstOrDefault(x => Key(x.Name) == Key(name));
        if (known == null)
        {
            // Catalogue plein : on oublie l’ingrédient le moins utilisé, le plus ancien d’abord.
            if (h.Ingredients.Count >= MaxIngredients)
                h.Ingredients.Remove(h.Ingredients.OrderBy(x => x.Uses).ThenBy(x => x.LastUsedAt ?? DateTimeOffset.MinValue).First());
            known = new Ingredient { Name = name };
            h.Ingredients.Add(known);
        }
        known.Aisle = aisle;
        if (qty != null) known.LastQty = qty;
        if (used) { known.Uses++; known.LastUsedAt = now; }
    }

    public static CheckItem Update(Household h, string list, string id, ShoppingItemPatch p, string member, DateTimeOffset now)
    {
        if (p.Aisle != null && !KnownAisle(p.Aisle)) throw new RuleException("Rayon inconnu.");
        var (items, ticket) = Resolve(h, list);
        var index = items.FindIndex(c => c.Id == id);
        if (index < 0) throw new RuleException("Article introuvable.", 404);
        var item = items[index];
        item = item with { Done = p.Done ?? item.Done, Qty = p.Qty == null ? item.Qty : CleanQty(p.Qty), Aisle = p.Aisle ?? item.Aisle };
        items[index] = item;
        // Un rayon corrigé vaut pour les prochaines fois ; la quantité aussi.
        if (p.Aisle != null || p.Qty != null) Remember(h, item.Text, item.Aisle ?? "other", item.Qty, false, now);
        Touched(ticket, member, now);
        return item;
    }

    public static void Remove(Household h, string list, string id, string member, DateTimeOffset now)
    {
        var (items, ticket) = Resolve(h, list);
        if (items.RemoveAll(c => c.Id == id) == 0) throw new RuleException("Article introuvable.", 404);
        Touched(ticket, member, now);
    }

    public static void ClearDone(Household h, string list, string member, DateTimeOffset now)
    {
        var (items, ticket) = Resolve(h, list);
        if (items.RemoveAll(c => c.Done) > 0) Touched(ticket, member, now);
    }

    public static void Forget(Household h, string name)
    {
        if (h.Ingredients.RemoveAll(x => Key(x.Name) == Key(name ?? "")) == 0) throw new RuleException("Ingrédient introuvable.", 404);
    }

    // Réunit [from] dans [into] : même ingrédient = un seul article, quantités mises bout à bout.
    static void Merge(List<CheckItem> into, IEnumerable<CheckItem> from)
    {
        var incoming = from.ToList();
        var added = incoming.Select(c => Key(c.Text)).Distinct().Count(k => !into.Any(x => Key(x.Text) == k));
        if (into.Count + added > MaxItems) throw new RuleException($"{MaxItems} articles maximum par liste.");
        foreach (var c in incoming)
        {
            var index = into.FindIndex(x => Key(x.Text) == Key(c.Text));
            if (index < 0) { into.Add(c); continue; }
            var x = into[index];
            var qty = x.Qty == null || c.Qty == null || x.Qty == c.Qty ? x.Qty ?? c.Qty : $"{x.Qty} + {c.Qty}";
            into[index] = x with { Qty = qty?.Length > MaxQty ? qty[..MaxQty] : qty, Done = x.Done && c.Done };
        }
    }

    // Le brouillon rejoint la tâche (lancement du raccourci Courses, répétition, programmation).
    public static void AttachDraft(Household h, Ticket t)
    {
        if (h.ShoppingDraft.Count == 0) return;
        Merge(t.Checklist, h.ShoppingDraft.Select(c => c with { Done = false }));
        h.ShoppingDraft.Clear();
    }

    // Tâche Courses close (faite, abandonnée, passée) : les articles non achetés reviennent dans la
    // liste en cours (la prochaine tâche Courses, sinon le brouillon). Renvoie leur nombre.
    public static int ReturnUnbought(Household h, Ticket t, bool toDraft = false)
    {
        var left = t.Checklist.Where(c => !c.Done).ToList();
        if (left.Count == 0) return 0;
        var next = toDraft ? null : Open(h).FirstOrDefault(x => x.Id != t.Id);
        var target = next?.Checklist ?? h.ShoppingDraft;
        foreach (var c in left)
            if (target.Count < MaxItems || target.Any(x => Key(x.Text) == Key(c.Text))) Merge(target, [c with { Id = NewId() }]);
        if (next != null) next.Version++;
        return left.Count;
    }

    // Programme les courses du brouillon : new = nouvelle tâche ; append = dans la tâche [targetId]
    // (sa date reste) ; merge = dans la tâche [targetId], déplacée à [date].
    public static Ticket Schedule(Household h, ShoppingScheduleInput i, string member, DateTimeOffset now)
    {
        var today = Rules.Today(h, now);
        if (i.Date < today) throw new RuleException("Choisissez aujourd’hui ou une date à venir.");
        if (i.Mode is "append" or "merge")
        {
            if (i.TargetId is null or Draft) throw new RuleException("Choisissez la tâche Courses à compléter.");
            var (_, target) = Resolve(h, i.TargetId);
            AttachDraft(h, target!);
            if (i.Mode == "merge") Move(h, target!, i.Date, member, now);
            Touched(target, member, now);
            return target!;
        }
        if (i.Mode != "new") throw new RuleException("Mode de programmation inconnu.");
        if (h.Tickets.Count(t => !Rules.Closed(t)) >= 1000) throw new RuleException("Trop de tâches ouvertes.");
        var s = h.Shortcuts.FirstOrDefault(x => x.SeedKey == "groceries");
        var t = s != null ? Shortcuts.Launch(h, s, member, now) : Plain(h, member, now);
        t.Shopping = true;
        AttachDraft(h, t);
        Place(t, i.Date, s?.DueInDays, today);
        return t;
    }

    // Tâche Courses quand le raccourci « Faire les courses » a été supprimé.
    static Ticket Plain(Household h, string member, DateTimeOffset now)
    {
        var tag = h.Tags.FirstOrDefault(x => x.Name == "Courses")?.Id;
        var t = new Ticket { Number = h.Tickets.Select(t => t.Number).DefaultIfEmpty(0).Max() + 1, CreatedAt = now, UpdatedAt = now };
        Rules.Apply(h, t, new TicketInput("Faire les courses", "", "obligation", "normal", "todo", null, null, [member], [], tag == null ? [] : [tag], []), member, now, true);
        h.Tickets.Add(t);
        return t;
    }

    // Date des courses : aujourd’hui = À faire ; plus tard = Backlog, que Rules.Schedule passera
    // À faire (avec une notification) le jour venu. Les étapes En cours / Bloqué ne bougent pas.
    static void Place(Ticket t, DateOnly date, int? dueInDays, DateOnly today)
    {
        t.StartDate = date;
        t.DueDate = date.AddDays(dueInDays ?? 0);
        if (date <= today && t.StageId == "backlog") t.StageId = "todo";
        else if (date > today && t.StageId == "todo") t.StageId = "backlog";
    }

    public static void Move(Household h, Ticket t, DateOnly date, string member, DateTimeOffset now)
    {
        if (!t.Shopping || Rules.Closed(t)) throw new RuleException("Liste de courses introuvable.", 404);
        var today = Rules.Today(h, now);
        if (date < today) throw new RuleException("Choisissez aujourd’hui ou une date à venir.");
        var (start, due, stage) = (t.StartDate, t.DueDate, t.StageId);
        var delay = t.StartDate is { } s && t.DueDate is { } d ? d.DayNumber - s.DayNumber : 0;
        Place(t, date, delay, today);
        if (stage != t.StageId) Rules.Event(t, member, "stage", $"{stage} → {t.StageId}", now);
        if (start != t.StartDate || due != t.DueDate) Rules.Event(t, member, "dates", $"{start}/{due} → {t.StartDate}/{t.DueDate}", now);
        t.Version++;
    }

    // Catalogue de départ, pour que la recherche serve dès le premier jour (chargé une seule fois).
    public static void SeedOnce(Household h)
    {
        if (h.IngredientsSeeded) return;
        h.IngredientsSeeded = true;
        (string aisle, string[] names)[] seeds =
        [
            ("dairy", ["Lait", "Œufs", "Beurre", "Yaourts", "Fromage râpé", "Crème fraîche"]),
            ("bakery", ["Pain"]),
            ("produce", ["Tomates", "Pommes", "Bananes", "Carottes", "Pommes de terre", "Oignons", "Salade", "Citrons"]),
            ("savory", ["Pâtes", "Riz", "Huile d’olive", "Sauce tomate", "Sel"]),
            ("sweet", ["Café", "Sucre", "Farine", "Chocolat", "Céréales"]),
            ("meat", ["Poulet", "Jambon", "Steak haché"]),
            ("drinks", ["Eau", "Jus d’orange"]),
            ("frozen", ["Légumes surgelés"]),
            ("hygiene", ["Papier toilette", "Dentifrice", "Gel douche"]),
            ("cleaning", ["Lessive", "Liquide vaisselle", "Éponges", "Sacs poubelle"]),
        ];
        foreach (var (aisle, names) in seeds)
            foreach (var name in names)
                if (!h.Ingredients.Any(x => Key(x.Name) == Key(name))) h.Ingredients.Add(new Ingredient { Name = name, Aisle = aisle });
    }
}
