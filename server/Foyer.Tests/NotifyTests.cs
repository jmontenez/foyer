using Foyer;
using Xunit;
namespace Foyer.Tests;

public class NotifyTests
{
    // Vendredi 25 septembre 2026, 10 h UTC (midi à Paris).
    private static readonly DateTimeOffset Now = new(2026, 9, 25, 10, 0, 0, TimeSpan.Zero);
    private static readonly DateOnly Today = new(2026, 9, 25);
    private static Household Home()
    {
        var h = new Household { Members = [new() { Id = "a", Subject = "a", Name = "Jonathan Montenez" }, new() { Id = "b", Subject = "b", Name = "Clemence Henry" }] };
        Shortcuts.SeedOnce(h);
        return h;
    }
    private static TicketInput Input(List<string> assignees, DateOnly? due = null, int version = 0) =>
        new("Papiers École", "", "obligation", "normal", "todo", null, due, assignees, [], [], [], version);
    private static Ticket Create(Household h, string actor, List<string> assignees, DateOnly? due = null)
    {
        var t = new Ticket();
        Rules.Apply(h, t, Input(assignees, due), actor, Now, true);
        h.Tickets.Add(t);
        return t;
    }
    private static List<Notification> Assigns(Household h) => [.. h.Notifications.Where(n => n.Kind == "assign")];

    [Fact]
    public void AssigningSomeoneElseNotifiesThem()
    {
        var h = Home();
        var t = Create(h, "b", ["a", "b"], Today.AddDays(1));
        var n = Assert.Single(Assigns(h));
        Assert.Equal(("a", t.Id, "b"), (n.MemberId, n.TicketId, n.ActorId));
        Assert.Equal("Clemence vous a confié une tâche", n.Title);
        Assert.Equal("Papiers École · demain", n.Body);
    }

    [Fact]
    public void OnlyNewlyAddedAssigneesAreNotified()
    {
        var h = Home();
        var t = Create(h, "a", ["a"]);
        Assert.Empty(Assigns(h));
        Rules.Apply(h, t, Input(["a", "b"], version: t.Version), "a", Now);
        Assert.Equal("b", Assert.Single(Assigns(h)).MemberId);
        // Retirer quelqu’un, ou garder les mêmes responsables : rien de plus.
        Rules.Apply(h, t, Input(["b"], version: t.Version), "a", Now);
        Rules.Apply(h, t, Input(["b"], version: t.Version), "b", Now);
        Assert.Single(Assigns(h));
    }

    [Fact]
    public void AutomationAndClosedTasksNotifyNobody()
    {
        var h = Home();
        Create(h, "system", ["a"]);
        var t = new Ticket();
        Rules.Apply(h, t, Input(["a"]) with { StageId = "done", Performers = ["b"] }, "b", Now, true);
        Assert.Empty(Assigns(h));
    }

    [Fact]
    public void ShortcutLaunchedForTheOtherNotifiesThem()
    {
        var h = Home();
        var bins = h.Shortcuts.Single(s => s.SeedKey == "bins");
        bins.Assign = "member"; bins.AssigneeId = "b";
        Shortcuts.Launch(h, bins, "a", Now);
        var n = Assert.Single(Assigns(h));
        Assert.Equal(("b", "Jonathan vous a confié une tâche", "Sortir les poubelles · aujourd’hui"), (n.MemberId, n.Title, n.Body));
    }

    [Theory]
    [InlineData(0, "aujourd’hui")]
    [InlineData(-3, "aujourd’hui")]
    [InlineData(1, "demain")]
    [InlineData(2, "pour dimanche")]
    [InlineData(8, "pour le 3 oct.")]
    public void DatesReadNaturally(int days, string expected) => Assert.Equal(expected, Notify.When(Today.AddDays(days), Today));

    [Fact]
    public void OlderNotificationsKeepTheirFormat()
    {
        Assert.Equal(("Foyer", "Votre résumé est prêt"), Notify.Text(new Notification { Title = "Votre résumé est prêt" }));
        Assert.Equal(("Titre", "Corps"), Notify.Text(new Notification { Title = "Titre", Body = "Corps" }));
    }
}
