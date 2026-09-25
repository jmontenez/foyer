using Foyer;
using Xunit;
namespace Foyer.Tests;

public class ShortcutsTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 25, 10, 0, 0, TimeSpan.Zero);
    private static Household Home()
    {
        var h = new Household { Members = [new() { Id = "a", Subject = "a", Name = "Alice" }, new() { Id = "b", Subject = "b", Name = "Bob" }] };
        Shortcuts.SeedOnce(h);
        return h;
    }
    private static ShortcutInput Input(string title = "Lessive", string assign = "launcher", string? assignee = null, int? due = 0, List<string>? steps = null) =>
        new(title, "", "obligation", "normal", [], steps ?? [], due, assign, assignee);

    [Fact]
    public void CommonShortcutsAreSeededOnceAndNeverReinserted()
    {
        var h = Home();
        Assert.Equal(8, h.Shortcuts.Count);
        Assert.Equal(h.Shortcuts.Count, h.Shortcuts.Select(s => s.SeedKey).Distinct().Count());
        var laundry = h.Shortcuts.Single(s => s.SeedKey == "laundry");
        Assert.Contains(h.Tags.Single(t => t.Name == "Entretien").Id, laundry.TagIds);
        Assert.Equal(4, laundry.Checklist.Count);
        h.Shortcuts.Clear();
        Shortcuts.SeedOnce(h);
        Assert.Empty(h.Shortcuts);
    }

    [Fact]
    public void RenamedOrDeletedTagsDoNotBreakSeeding()
    {
        var h = new Household { Tags = [] };
        Shortcuts.SeedOnce(h);
        Assert.All(h.Shortcuts, s => Assert.Empty(s.TagIds));
    }

    [Theory]
    [InlineData("", "launcher", null, 0)]
    [InlineData("Lessive", "rotation", null, -1)]
    [InlineData("Lessive", "rotation", null, 61)]
    [InlineData("Lessive", "everyone", null, 0)]
    [InlineData("Lessive", "member", "inconnu", 0)]
    public void InvalidShortcutsAreRefused(string title, string assign, string? assignee, int due) =>
        Assert.Throws<RuleException>(() => Shortcuts.Validate(Home(), Input(title, assign, assignee, due)));

    [Fact]
    public void TooManyStepsOrUnknownTagsAreRefused()
    {
        var h = Home();
        Assert.Throws<RuleException>(() => Shortcuts.Validate(h, Input(steps: [.. Enumerable.Repeat("x", 21)])));
        Assert.Throws<RuleException>(() => Shortcuts.Validate(h, Input() with { TagIds = ["inconnu"] }));
    }

    [Fact]
    public void LaunchCreatesATodoTaskFromTheShortcut()
    {
        var h = Home();
        var s = h.Shortcuts.Single(x => x.SeedKey == "laundry");
        var t = Shortcuts.Launch(h, s, "b", Now);
        Assert.Equal(("Faire une lessive", "todo", s.Id), (t.Title, t.StageId, t.ShortcutId));
        Assert.Equal(new DateOnly(2026, 9, 25), t.DueDate);
        Assert.Equal(["b"], t.Assignees);
        Assert.Equal(4, t.Checklist.Count);
        Assert.All(t.Checklist, c => Assert.False(c.Done));
        Assert.Equal(s.TagIds, t.TagIds);
        Assert.Single(h.Tickets);
    }

    [Fact]
    public void DueDelayAndNoDate()
    {
        var h = Home();
        var s = new Shortcut(); Shortcuts.Apply(s, Input(due: 2)); h.Shortcuts.Add(s);
        Assert.Equal(new DateOnly(2026, 9, 27), Shortcuts.Launch(h, s, "a", Now).DueDate);
        Shortcuts.Apply(s, Input(due: null));
        Assert.Null(Shortcuts.Launch(h, s, "a", Now).DueDate);
    }

    [Fact]
    public void AssignmentModes()
    {
        var h = Home();
        var s = new Shortcut(); h.Shortcuts.Add(s);
        Shortcuts.Apply(s, Input(assign: "none"));
        Assert.Empty(Shortcuts.Launch(h, s, "a", Now).Assignees);
        Shortcuts.Apply(s, Input(assign: "member", assignee: "b"));
        Assert.Equal(["b"], Shortcuts.Launch(h, s, "a", Now).Assignees);
        Assert.Null(new Shortcut { Assign = "launcher", AssigneeId = null }.AssigneeId);
    }

    [Fact]
    public void RotationAlternatesBetweenMembers()
    {
        var h = Home();
        var s = new Shortcut(); Shortcuts.Apply(s, Input(assign: "rotation")); h.Shortcuts.Add(s);
        var first = Shortcuts.Launch(h, s, "a", Now).Assignees.Single();
        var second = Shortcuts.Launch(h, s, "a", Now.AddMinutes(1)).Assignees.Single();
        var third = Shortcuts.Launch(h, s, "a", Now.AddMinutes(2)).Assignees.Single();
        Assert.Equal("a", first);
        Assert.Equal("b", second);
        Assert.Equal("a", third);
    }

    [Fact]
    public void SummaryReportsLastDoneAndOpenOccurrence()
    {
        var h = Home();
        var s = h.Shortcuts.Single(x => x.SeedKey == "bins");
        Assert.Null(Shortcuts.Summary(h, s).LastDoneAt);
        var done = Shortcuts.Launch(h, s, "a", Now);
        done.StageId = "done"; done.ClosedAt = Now.AddDays(-1);
        var open = Shortcuts.Launch(h, s, "a", Now);
        var summary = Shortcuts.Summary(h, s);
        Assert.Equal(Now.AddDays(-1), summary.LastDoneAt);
        Assert.Equal(open.Id, summary.OpenTicketId);
        Assert.Equal(2, summary.Uses);
    }

    [Fact]
    public void PreviousHouseholdsDeserializeWithoutShortcuts()
    {
        var h = System.Text.Json.JsonSerializer.Deserialize<Household>("""{"tickets":[{"title":"x"}]}""", Defaults.Json)!;
        Assert.Empty(h.Shortcuts);
        Assert.False(h.ShortcutsSeeded);
        Assert.Null(h.Tickets[0].ShortcutId);
    }
}
