using Foyer;
using Xunit;
namespace Foyer.Tests;

public class WidgetsTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 25, 10, 0, 0, TimeSpan.Zero);
    private static readonly DateOnly Today = new(2026, 9, 25);
    private static Household Home() => new() { Members = [new() { Id = "a", Subject = "a", Name = "Jonathan" }, new() { Id = "b", Subject = "b", Name = "Clemence" }] };

    [Fact]
    public void TodayListsMyTasksLateFirstWithShortLabels()
    {
        var h = Home();
        h.Tickets.Add(new() { Id = "t1", Title = "Laver la couette", StageId = "todo", DueDate = Today });
        h.Tickets.Add(new() { Id = "t2", Title = "Papiers École", StageId = "todo", DueDate = Today.AddDays(-2), Assignees = ["a"] });
        h.Tickets.Add(new() { Id = "t3", Title = "Faire les courses", StageId = "todo", StartDate = Today, Shopping = true, Checklist = [new("1", "Lait", false), new("2", "Pain", true)] });
        h.Tickets.Add(new() { Id = "t4", Title = "Peindre", StageId = "doing" });
        h.Tickets.Add(new() { Id = "t5", Title = "Pour Clemence", StageId = "todo", DueDate = Today, Assignees = ["b"] });
        h.Tickets.Add(new() { Id = "t6", Title = "Fini", StageId = "done", DueDate = Today });
        var w = Widgets.Build(h, h.Members[0], Now).Today;
        Assert.Equal((Today, 4, 1), (w.Date, w.Count, w.Late));
        Assert.Equal(["t2", "t1", "t3", "t4"], w.Tasks.Select(t => t.Id));
        Assert.Equal(["En retard", "Aujourd’hui", "1 article", "En cours"], w.Tasks.Select(t => t.Meta));
        Assert.True(w.Tasks[0].Late);
    }

    [Fact]
    public void EmptyDayAndLongListsStayBounded()
    {
        var h = Home();
        Assert.Empty(Widgets.Build(h, h.Members[0], Now).Today.Tasks);
        for (var i = 0; i < 15; i++) h.Tickets.Add(new() { Title = $"T{i}", StageId = "todo", DueDate = Today });
        var w = Widgets.Build(h, h.Members[0], Now).Today;
        Assert.Equal((15, Widgets.MaxTasks), (w.Count, w.Tasks.Count));
    }

    [Fact]
    public void DoneInOneTapIsByMeAndKeepsTheRest()
    {
        var h = Home();
        var t = new Ticket { Title = "Faire les courses", StageId = "todo", Assignees = ["b"], Shopping = true, Checklist = [new("1", "Lait", true), new("2", "Pain", false)] };
        h.Tickets.Add(t);
        Rules.Done(h, t, "a", Now);
        Assert.Equal(("done", "Faire les courses"), (t.StageId, t.Title));
        Assert.Equal(["a"], t.Performers);
        Assert.Equal(["b"], t.Assignees);
        Assert.Equal(["Pain"], h.ShoppingDraft.Select(c => c.Text));
        var ex = Assert.Throws<RuleException>(() => Rules.Done(h, t, "a", Now));
        Assert.Equal(409, ex.Status);
    }

    [Fact]
    public void ShoppingShowsTheCurrentListByAisle()
    {
        var h = Home();
        Shopping.SeedOnce(h);
        var draft = Widgets.Build(h, h.Members[0], Now).Shopping;
        Assert.Equal(("draft", "non programmées", 0), (draft.List, draft.When, draft.Rows.Count));
        Shopping.Add(h, new ShoppingItemInput("draft", "Lait", "2 L", null), "a", Now);
        Shopping.Add(h, new ShoppingItemInput("draft", "Tomates", null, null), "a", Now);
        Shopping.Add(h, new ShoppingItemInput("draft", "Pain", null, null), "a", Now);
        var t = Shopping.Schedule(h, new ShoppingScheduleInput(new DateOnly(2026, 9, 26), "new", null), "a", Now);
        Shopping.Update(h, t.Id, t.Checklist.Single(c => c.Text == "Pain").Id, new ShoppingItemPatch(true, null, null), "a", Now);
        var w = Widgets.Build(h, h.Members[0], Now).Shopping;
        Assert.Equal((t.Id, "demain", 2, 1), (w.List, w.When, w.Left, w.Done));
        // Ordre du magasin : Fruits & légumes avant Crèmerie & œufs.
        Assert.Equal(["Fruits & légumes", "Tomates", "Crèmerie & œufs", "Lait"], w.Rows.Select(r => r.Text));
        Assert.Null(w.Rows[0].Id);
        Assert.Equal("2 L", w.Rows[3].Qty);
    }
}
