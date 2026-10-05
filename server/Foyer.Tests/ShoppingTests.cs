using Foyer;
using Xunit;
namespace Foyer.Tests;

public class ShoppingTests
{
    // Vendredi 25 septembre 2026, 10 h UTC.
    private static readonly DateTimeOffset Now = new(2026, 9, 25, 10, 0, 0, TimeSpan.Zero);
    private static readonly DateOnly Today = new(2026, 9, 25), Saturday = new(2026, 9, 26), Tuesday = new(2026, 9, 29);
    private static Household Home()
    {
        var h = new Household { Members = [new() { Id = "a", Subject = "a", Name = "Alice" }, new() { Id = "b", Subject = "b", Name = "Bob" }] };
        Shortcuts.SeedOnce(h);
        Shopping.SeedOnce(h);
        return h;
    }
    private static CheckItem Add(Household h, string name, string? qty = null, string list = Shopping.Draft, string? aisle = null) =>
        Shopping.Add(h, new ShoppingItemInput(list, name, qty, aisle), "a", Now);
    private static Shortcut Groceries(Household h) => h.Shortcuts.Single(s => s.SeedKey == "groceries");
    private static Ticket Schedule(Household h, DateOnly date, string mode = "new", string? target = null) =>
        Shopping.Schedule(h, new ShoppingScheduleInput(date, mode, target), "a", Now);
    private static TicketInput Done(Ticket t) => new(t.Title, t.Description, t.Kind, t.Priority, "done", t.StartDate, t.DueDate, t.Assignees, ["a"], t.TagIds, t.Checklist, t.Version);

    [Theory]
    [InlineData("Œufs", "oeuf")]
    [InlineData("  Pommes de terre ", "pomme de terre")]
    [InlineData("Crème fraîche", "creme fraiche")]
    [InlineData("Huile d’olive", "huile d’olive")]
    public void KeysIgnoreCaseAccentsAndPlural(string name, string key) => Assert.Equal(key, Shopping.Key(name));

    [Fact]
    public void SameIngredientIsUpdatedRatherThanDuplicated()
    {
        var h = Home();
        var first = Add(h, "oeuf", "6");
        Assert.Equal(("Œufs", "dairy"), (first.Text, first.Aisle));
        var again = Add(h, "ŒUF", "12");
        Assert.Single(h.ShoppingDraft);
        Assert.Equal((first.Id, "12"), (again.Id, again.Qty));
        // Sans nouvelle quantité, l’ancienne reste.
        Assert.Equal("12", Add(h, "Oeufs").Qty);
        Assert.Equal(1, h.Ingredients.Single(i => i.Name == "Œufs").Uses);
    }

    [Fact]
    public void CatalogRemembersNewIngredientsAislesAndLastQuantity()
    {
        var h = Home();
        Add(h, "Frites", "1 sac", aisle: "frozen");
        var frites = h.Ingredients.Single(i => i.Name == "Frites");
        Assert.Equal(("frozen", "1 sac", 1), (frites.Aisle, frites.LastQty, frites.Uses));
        var item = h.ShoppingDraft.Single();
        Shopping.Remove(h, Shopping.Draft, item.Id, "a", Now);
        // La fois suivante, le rayon n’est plus à redonner.
        Assert.Equal("frozen", Add(h, "frite").Aisle);
        Shopping.Update(h, Shopping.Draft, h.ShoppingDraft.Single().Id, new ShoppingItemPatch(null, null, "other"), "a", Now);
        Assert.Equal("other", frites.Aisle);
        Shopping.Forget(h, "FRITES");
        Assert.DoesNotContain(h.Ingredients, i => i.Name == "Frites");
    }

    [Fact]
    public void IngredientPhotoIsRememberedReplacedAndRemoved()
    {
        var h = Home();
        // Posée sur un nom inconnu du catalogue : l’ingrédient est créé au passage.
        Assert.Null(Shopping.SetImage(h, " granola ", "img-1", Now));
        var granola = h.Ingredients.Single(i => i.Name == "granola");
        Assert.Equal("img-1", granola.ImageId);
        // Remplacée : l’ancienne photo est renvoyée, à supprimer du disque par l’appelant.
        Assert.Equal("img-1", Shopping.SetImage(h, "GRANOLAS", "img-2", Now));
        Assert.Equal("img-2", granola.ImageId);
        // Reposer la même photo ne demande aucune suppression.
        Assert.Null(Shopping.SetImage(h, "granola", "img-2", Now));
        Assert.Equal("img-2", Shopping.RemoveImage(h, "granola"));
        Assert.Null(granola.ImageId);
        Assert.Null(Shopping.RemoveImage(h, "granola"));
        Assert.Throws<RuleException>(() => Shopping.RemoveImage(h, "inconnu du catalogue"));
        Assert.Throws<RuleException>(() => Shopping.SetImage(h, " ", "img-3", Now));
    }

    [Fact]
    public void ForgettingAnIngredientReturnsItsPhoto()
    {
        var h = Home();
        Shopping.SetImage(h, "Tomates", "img-tomates", Now);
        Assert.Equal("img-tomates", Shopping.Forget(h, "tomate"));
        Assert.DoesNotContain(h.Ingredients, i => Shopping.Key(i.Name) == "tomate");
        Assert.Null(Shopping.Forget(h, "Pain"));
    }

    [Fact]
    public void EditingAnIngredientFollowsIntoOpenLists()
    {
        var h = Home();
        Add(h, "Yaourts", "4");
        var t = Schedule(h, Today);
        Add(h, "yaourt", list: t.Id);
        Add(h, "Yaourts");
        var version = t.Version;
        var edited = Shopping.EditIngredient(h, "yaourts", new IngredientInput("Yaourts nature", "dairy", "8"), "a", Now);
        Assert.Equal(("Yaourts nature", "8"), (edited.Name, edited.LastQty));
        Assert.Equal("Yaourts nature", t.Checklist.Single().Text);
        Assert.Equal("4", t.Checklist.Single().Qty);
        Assert.Equal("Yaourts nature", h.ShoppingDraft.Single().Text);
        Assert.True(t.Version > version);
        Assert.Throws<RuleException>(() => Shopping.EditIngredient(h, "Yaourts nature", new IngredientInput("Lait", null, null), "a", Now));
        Assert.Throws<RuleException>(() => Shopping.EditIngredient(h, "Yaourts nature", new IngredientInput(" ", null, null), "a", Now));
        Assert.Throws<RuleException>(() => Shopping.EditIngredient(h, "Yaourts nature", new IngredientInput("X", "rayon-x", null), "a", Now));
        Assert.Throws<RuleException>(() => Shopping.EditIngredient(h, "inconnu", new IngredientInput("X", null, null), "a", Now));
        // Changer seulement la casse ou le rayon est permis.
        Assert.Equal("frozen", Shopping.EditIngredient(h, "Yaourts nature", new IngredientInput("yaourts nature", "frozen", null), "a", Now).Aisle);
        Assert.Equal("frozen", h.ShoppingDraft.Single().Aisle);
    }

    [Fact]
    public void InvalidInputsAreRefused()
    {
        var h = Home();
        Assert.Throws<RuleException>(() => Add(h, " "));
        Assert.Throws<RuleException>(() => Add(h, new string('x', 61)));
        Assert.Throws<RuleException>(() => Add(h, "Lait", new string('1', 41)));
        Assert.Throws<RuleException>(() => Add(h, "Lait", aisle: "rayon-x"));
        Assert.Throws<RuleException>(() => Add(h, "Lait", list: "inconnue"));
        for (var i = 0; i < Shopping.MaxItems; i++) Add(h, $"Article {i}");
        Assert.Throws<RuleException>(() => Add(h, "Encore un"));
    }

    [Fact]
    public void AisleOrderMustBeAPermutation()
    {
        var h = Home();
        var ids = Shopping.Aisles.Select(a => a.Id).Reverse().ToList();
        Shopping.ReorderAisles(h, ids);
        Assert.Equal("other", Shopping.Ordered(h)[0].Id);
        Assert.Throws<RuleException>(() => Shopping.ReorderAisles(h, ids.Skip(1).ToList()));
        Assert.Throws<RuleException>(() => Shopping.ReorderAisles(h, [.. ids.Skip(1), "inconnu"]));
        // Un rayon ajouté plus tard apparaît quand même.
        h.AisleOrder = ["frozen"];
        Assert.Equal(Shopping.Aisles.Length, Shopping.Ordered(h).Count);
        Assert.Equal("frozen", Shopping.Ordered(h)[0].Id);
    }

    [Fact]
    public void SchedulingCreatesTheGroceriesTaskWithTheDraft()
    {
        var h = Home();
        Add(h, "Lait", "2 L");
        var t = Schedule(h, Saturday);
        Assert.True(t.Shopping);
        Assert.Equal((Groceries(h).Id, "backlog", Saturday, Saturday), (t.ShortcutId, t.StageId, t.StartDate, t.DueDate));
        Assert.Equal("2 L", t.Checklist.Single().Qty);
        Assert.Empty(h.ShoppingDraft);
        Assert.Equal(t.Id, Shortcuts.Summary(h, Groceries(h)).OpenTicketId);
        // Le jour venu, la tâche passe À faire avec une notification.
        Rules.Schedule(h, new DateTimeOffset(2026, 9, 26, 8, 0, 0, TimeSpan.Zero));
        Assert.Equal("todo", t.StageId);
        Assert.Contains(h.Notifications, n => n.Kind == "start" && n.TicketId == t.Id);
    }

    [Fact]
    public void SchedulingTodayIsTodoAndPastDatesAreRefused()
    {
        var h = Home();
        Assert.Equal("todo", Schedule(h, Today).StageId);
        Assert.Throws<RuleException>(() => Schedule(h, Today.AddDays(-1)));
    }

    [Fact]
    public void ThreeWaysToScheduleNextToAnExistingTask()
    {
        var h = Home();
        Add(h, "Lait", "1 L");
        var saturday = Schedule(h, Saturday);
        // Ajouter à la tâche existante : sa date ne change pas.
        Add(h, "Lait", "2 L"); Add(h, "Pain");
        Assert.Same(saturday, Schedule(h, Tuesday, "append", saturday.Id));
        Assert.Equal(Saturday, saturday.StartDate);
        Assert.Equal(["Lait", "Pain"], saturday.Checklist.Select(c => c.Text));
        Assert.Equal("1 L + 2 L", saturday.Checklist[0].Qty);
        // Tout regrouper : la tâche existante est déplacée.
        Add(h, "Café");
        Schedule(h, Tuesday, "merge", saturday.Id);
        Assert.Equal((Tuesday, 3), (saturday.StartDate, saturday.Checklist.Count));
        Assert.Single(h.Tickets);
        // Deux tâches séparées.
        Add(h, "Beurre");
        var other = Schedule(h, Saturday);
        Assert.Equal(2, Shopping.Open(h).Count());
        Assert.Equal(other.Id, Shopping.Lists(h)[0].Id);
        Assert.Equal(["Beurre"], other.Checklist.Select(c => c.Text));
        Assert.Throws<RuleException>(() => Schedule(h, Tuesday, "append", Shopping.Draft));
    }

    [Fact]
    public void MovingAScheduledListUpdatesItsStage()
    {
        var h = Home();
        var t = Schedule(h, Today);
        Shopping.Move(h, t, Tuesday, "a", Now);
        Assert.Equal(("backlog", Tuesday), (t.StageId, t.StartDate));
        Shopping.Move(h, t, Today, "a", Now);
        Assert.Equal("todo", t.StageId);
    }

    [Fact]
    public void GroceriesShortcutLoadsTheDraftOnlyWhenAsked()
    {
        var h = Home();
        Add(h, "Lait");
        var without = Shortcuts.Launch(h, Groceries(h), "a", Now);
        Assert.True(without.Shopping);
        Assert.Empty(without.Checklist);
        Assert.Single(h.ShoppingDraft);
        var with = Shortcuts.Launch(h, Groceries(h), "a", Now, withList: true);
        Assert.Single(with.Checklist);
        Assert.Empty(h.ShoppingDraft);
        // Annuler juste après : la liste revient dans le brouillon.
        Shortcuts.UndoLaunch(h, with, "a", Now);
        Assert.Single(h.ShoppingDraft);
        Assert.False(Shortcuts.Launch(h, h.Shortcuts.Single(s => s.SeedKey == "laundry"), "a", Now, withList: true).Shopping);
    }

    [Fact]
    public void RecurrenceTakesTheDraftWithIt()
    {
        var h = Home();
        Add(h, "Lait");
        Groceries(h).Repeat = new RepeatRule { Mode = "weekly", Every = 1, Days = [6], Active = true };
        Recurrence.Tick(h, Now);
        var t = h.Tickets.Single();
        Assert.True(t.Shopping);
        Assert.Equal((Saturday, "Lait"), (t.StartDate, t.Checklist.Single().Text));
        Assert.Empty(h.ShoppingDraft);
    }

    [Fact]
    public void UnboughtItemsComeBackWhenTheTaskIsClosed()
    {
        var h = Home();
        Add(h, "Lait"); Add(h, "Pain"); Add(h, "Café");
        var t = Schedule(h, Today);
        Shopping.Update(h, t.Id, t.Checklist[0].Id, new ShoppingItemPatch(true, null, null), "b", Now);
        Rules.Apply(h, t, Done(t), "a", Now);
        Assert.Equal(["Pain", "Café"], h.ShoppingDraft.Select(c => c.Text));
        Assert.All(h.ShoppingDraft, c => Assert.False(c.Done));
        Assert.Throws<RuleException>(() => Add(h, "Lait", list: t.Id));
        // Passer une occurrence : même chose, vers la prochaine liste s’il y en a une.
        var next = Schedule(h, Saturday);
        Groceries(h).Repeat = new RepeatRule { Mode = "weekly", Every = 1, Days = [6], Active = true };
        Add(h, "Sucre", list: next.Id);
        var later = Schedule(h, Tuesday);
        Recurrence.Skip(h, next, "a", Now);
        Assert.Equal(["Pain", "Café", "Sucre"], later.Checklist.Select(c => c.Text));
    }

    [Fact]
    public void ItemWritesBumpTheTaskAndGroupHistory()
    {
        var h = Home();
        var t = Schedule(h, Today);
        var version = t.Version;
        Add(h, "Lait", list: t.Id);
        var item = Add(h, "Pain", list: t.Id);
        Shopping.Update(h, t.Id, item.Id, new ShoppingItemPatch(true, null, null), "a", Now);
        Assert.Equal(version + 3, t.Version);
        Assert.Single(t.History, e => e.Action == "shopping");
        Shopping.ClearDone(h, t.Id, "b", Now);
        Assert.Equal(["Lait"], t.Checklist.Select(c => c.Text));
        Assert.Equal(2, t.History.Count(e => e.Action == "shopping"));
    }

    [Fact]
    public void WithoutTheGroceriesShortcutAPlainTaskIsCreated()
    {
        var h = Home();
        h.Shortcuts.RemoveAll(s => s.SeedKey == "groceries");
        var t = Schedule(h, Saturday);
        Assert.Equal(("Faire les courses", true, null), (t.Title, t.Shopping, t.ShortcutId));
        Assert.Contains(h.Tags.Single(x => x.Name == "Courses").Id, t.TagIds);
    }

    [Fact]
    public void CatalogIsSeededOnceAndStaysBounded()
    {
        var h = Home();
        var count = h.Ingredients.Count;
        Assert.True(count >= 30);
        Assert.All(h.Ingredients, i => Assert.True(Shopping.KnownAisle(i.Aisle)));
        h.Ingredients.Clear();
        Shopping.SeedOnce(h);
        Assert.Empty(h.Ingredients);
        for (var i = 0; i < Shopping.MaxIngredients + 5; i++)
        {
            var item = Add(h, $"Produit {i}");
            Shopping.Remove(h, Shopping.Draft, item.Id, "a", Now);
        }
        Assert.Equal(Shopping.MaxIngredients, h.Ingredients.Count);
    }

    [Fact]
    public void PreviewParsesBulletsQuantitiesAndSkipsHeaders()
    {
        var h = Home();
        var items = Shopping.Preview(h, Shopping.Draft, """
            Pour la pâte :
            - 500 g de farine
            * 6 œufs
            1. 25 cl de lait
            [ ] 2 sachets de levure

            Beurre : 250 g
            3,5
            """);
        Assert.Equal(["Farine", "Œufs", "Lait", "Levure", "Beurre"], items.Select(i => i.Name));
        Assert.Equal(["500 g", "6", "25 cl", "2 sachets", "250 g"], items.Select(i => i.Qty));
        // « farine » et « lait » sont au catalogue : rayon repris, nom canonique.
        Assert.Equal(("sweet", true), (items[0].Aisle, items[0].Known));
        Assert.Equal(("dairy", true), (items[2].Aisle, items[2].Known));
        // « levure » est inconnue : rayon Autre, à préciser.
        Assert.Equal(("other", false), (items[3].Aisle, items[3].Known));
        Assert.Empty(h.ShoppingDraft); // la prévisualisation n’écrit rien
    }

    [Fact]
    public void PreviewGuessesAisleFromCatalogWords()
    {
        var h = Home();
        var items = Shopping.Preview(h, Shopping.Draft, "filet de poulet\ntomates cerises\njus de grenade");
        // Le rayon vient du mot connu, mais le nom importé est conservé tel quel.
        Assert.Equal(("Filet de poulet", "meat", true), (items[0].Name, items[0].Aisle, items[0].Known));
        Assert.Equal(("Tomates cerises", "produce", true), (items[1].Name, items[1].Aisle, items[1].Known));
        Assert.Equal(("other", false), (items[2].Aisle, items[2].Known));
    }

    [Fact]
    public void PreviewMergesDuplicateLinesAndFlagsItemsAlreadyListed()
    {
        var h = Home();
        Add(h, "Farine", "1 kg");
        var items = Shopping.Preview(h, Shopping.Draft, "200 g de farine\nfarine 100 g\n2 courgettes");
        var farine = Assert.Single(items, i => i.Name == "Farine");
        Assert.Equal(("200 g + 100 g", true), (farine.Qty, farine.Merge));
        Assert.False(Assert.Single(items, i => i.Name == "Courgettes").Merge);
    }

    [Fact]
    public void PreviewAcceptsJson()
    {
        var h = Home();
        var items = Shopping.Preview(h, Shopping.Draft,
            """[{"name":"Lessive","qty":"2 L"},{"name":"Comté","aisle":"dairy"},{"name":"Chips","aisle":"rayon-inconnu"}]""");
        Assert.Equal(("cleaning", true), (items[0].Aisle, items[0].Known)); // catalogue
        Assert.Equal(("dairy", true), (items[1].Aisle, items[1].Known)); // rayon fourni
        Assert.Equal(("other", false), (items[2].Aisle, items[2].Known)); // rayon invalide ignoré
    }

    [Fact]
    public void PreviewRejectsEmptyOrUnusableText()
    {
        var h = Home();
        Assert.Throws<RuleException>(() => Shopping.Preview(h, Shopping.Draft, "  "));
        Assert.Throws<RuleException>(() => Shopping.Preview(h, Shopping.Draft, "Pour la pâte :\n---\n42"));
        Assert.Throws<RuleException>(() => Shopping.Preview(h, Shopping.Draft, new string('x', 20_001)));
    }

    [Fact]
    public void ImportAddsMergesAndLearnsAisles()
    {
        var h = Home();
        Add(h, "Œufs", "6");
        var result = Shopping.Import(h, new ShoppingBatchInput(Shopping.Draft, [
            new("Œufs", "12", "dairy"),
            new("Levure", "2 sachets", "bakery"),
            new("Courgettes", null, "produce"),
        ]), "a", Now);
        Assert.Equal((2, 1), (result.Added, result.Merged));
        Assert.Equal(3, h.ShoppingDraft.Count);
        Assert.Equal("12", h.ShoppingDraft.Single(i => i.Text == "Œufs").Qty);
        // Le rayon validé à l’import est appris pour les prochaines fois.
        Assert.Equal("bakery", h.Ingredients.Single(i => i.Name == "Levure").Aisle);
    }

    [Fact]
    public void ImportIsRefusedWhenTheListWouldOverflow()
    {
        var h = Home();
        for (var i = 0; i < Shopping.MaxItems - 1; i++) Add(h, $"Produit {i}");
        var batch = new ShoppingBatchInput(Shopping.Draft, [new("Nouveau 1", null, null), new("Nouveau 2", null, null)]);
        Assert.Throws<RuleException>(() => Shopping.Import(h, batch, "a", Now));
        Assert.Equal(Shopping.MaxItems - 1, h.ShoppingDraft.Count); // rien n’a été écrit
        Assert.Throws<RuleException>(() => Shopping.Import(h, new ShoppingBatchInput(Shopping.Draft, []), "a", Now));
    }

    [Fact]
    public void PreviousHouseholdsDeserializeWithoutShopping()
    {
        var h = System.Text.Json.JsonSerializer.Deserialize<Household>("""{"tickets":[{"title":"x","checklist":[{"id":"1","text":"a","done":false}]}]}""", Defaults.Json)!;
        Assert.Empty(h.ShoppingDraft);
        Assert.False(h.IngredientsSeeded);
        Assert.Equal(Shopping.Aisles.Length, h.AisleOrder.Count);
        Assert.False(h.Tickets[0].Shopping);
        Assert.Null(h.Tickets[0].Checklist[0].Qty);
    }
}
