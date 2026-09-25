using Foyer;
using Xunit;
namespace Foyer.Tests;

public class RecurrenceTests
{
    private static readonly TimeZoneInfo Paris = TimeZoneInfo.FindSystemTimeZoneById("Europe/Paris");
    private static DateTimeOffset At(int m, int d, int hour = 10) => new(2026, m, d, hour, 0, 0, TimeSpan.Zero);
    private static DateOnly Day(int m, int d, int y = 2026) => new(y, m, d);
    private static Household Home()
    {
        var h = new Household { Members = [new() { Id = "a", Subject = "a", Name = "Alice" }, new() { Id = "b", Subject = "b", Name = "Bob" }] };
        Shortcuts.SeedOnce(h);
        return h;
    }
    private static Shortcut Repeating(Household h, RepeatRule r, string assign = "none")
    {
        var s = new Shortcut { Title = "Lessive", Assign = assign, DueInDays = 0, Repeat = r };
        h.Shortcuts.Add(s);
        return s;
    }
    private static Ticket Open(Household h, Shortcut s) => h.Tickets.Single(t => t.ShortcutId == s.Id && !Rules.Closed(t));
    private static void Close(Ticket t, DateTimeOffset when, string stage = "done", string by = "a")
    {
        t.StageId = stage; t.ClosedAt = when; t.Performers = stage == "done" ? [by] : [];
    }

    [Fact]
    public void AfterModeCountsFromTheDayItWasDoneInParisTime()
    {
        var r = new RepeatRule { Mode = "after", Every = 3, Active = true };
        // 22 h 30 UTC le 24 = 0 h 30 à Paris le 25.
        var last = new Ticket { ClosedAt = new DateTimeOffset(2026, 9, 24, 22, 30, 0, TimeSpan.Zero) };
        Assert.Equal(Day(9, 28), Recurrence.NextDate(r, last, Day(9, 25), Paris));
        Assert.Equal(Day(9, 25), Recurrence.NextDate(r, null, Day(9, 25), Paris));
        // Fait il y a longtemps : pas de date passée.
        Assert.Equal(Day(9, 25), Recurrence.NextDate(r, new Ticket { ClosedAt = At(8, 1) }, Day(9, 25), Paris));
    }

    [Fact]
    public void WeeklyPicksTheNextChosenWeekday()
    {
        var tuesday = new RepeatRule { Mode = "weekly", Every = 1, Days = [2], Active = true };
        Assert.Equal(Day(9, 29), Recurrence.NextOnOrAfter(tuesday, Day(9, 25)));
        Assert.Equal(Day(9, 29), Recurrence.NextOnOrAfter(tuesday, Day(9, 29)));
        var monThu = new RepeatRule { Mode = "weekly", Every = 1, Days = [1, 4] };
        Assert.Equal(Day(10, 1), Recurrence.NextOnOrAfter(monThu, Day(9, 29)));
        // Occurrence du mardi 22 faite vendredi 25 : la suivante est le mardi 29, pas une date passée.
        Assert.Equal(Day(9, 29), Recurrence.NextDate(tuesday, new Ticket { StartDate = Day(9, 22), ClosedAt = At(9, 25) }, Day(9, 25), Paris));
    }

    [Fact]
    public void EveryOtherWeekFollowsTheAnchorWeek()
    {
        var r = new RepeatRule { Mode = "weekly", Every = 2, Days = [7], Anchor = Day(9, 21) };
        Assert.Equal(Day(9, 27), Recurrence.NextOnOrAfter(r, Day(9, 25)));
        Assert.Equal(Day(10, 11), Recurrence.NextOnOrAfter(r, Day(9, 28)));
    }

    [Fact]
    public void MonthlyClampsToShortMonths()
    {
        var r = new RepeatRule { Mode = "monthly", MonthDay = 31 };
        Assert.Equal(Day(1, 31, 2027), Recurrence.NextOnOrAfter(r, Day(1, 5, 2027)));
        Assert.Equal(Day(2, 28, 2027), Recurrence.NextOnOrAfter(r, Day(2, 1, 2027)));
        Assert.Equal(Day(3, 31, 2027), Recurrence.NextDate(r, new Ticket { StartDate = Day(2, 28, 2027), ClosedAt = At(2, 28) }, Day(3, 1, 2027), Paris));
        var fifth = new RepeatRule { Mode = "monthly", MonthDay = 5 };
        Assert.Equal(Day(10, 5), Recurrence.NextOnOrAfter(fifth, Day(9, 25)));
    }

    [Theory]
    [InlineData("after", 0, new int[0], 1)]
    [InlineData("after", 366, new int[0], 1)]
    [InlineData("weekly", 1, new int[0], 1)]
    [InlineData("weekly", 9, new[] { 1 }, 1)]
    [InlineData("weekly", 1, new[] { 8 }, 1)]
    [InlineData("monthly", 1, new int[0], 32)]
    [InlineData("yearly", 1, new int[0], 1)]
    public void InvalidRulesAreRefused(string mode, int every, int[] days, int monthDay) =>
        Assert.Throws<RuleException>(() => Recurrence.Validate(new RepeatRule { Mode = mode, Every = every, Days = [.. days], MonthDay = monthDay }));

    [Fact]
    public void OneOpenOccurrenceAtATimeThenTheNextOnceClosed()
    {
        var h = Home();
        var s = Repeating(h, new RepeatRule { Mode = "after", Every = 3, Active = true });
        Recurrence.Tick(h, At(9, 25));
        Recurrence.Tick(h, At(9, 25, 11));
        var first = Open(h, s);
        Assert.Equal(("backlog", Day(9, 25), Day(9, 25)), (first.StageId, first.StartDate, first.DueDate));
        Close(first, At(9, 26));
        Recurrence.Tick(h, At(9, 26, 11));
        var second = Open(h, s);
        Assert.Equal(Day(9, 29), second.StartDate);
        Assert.Equal(2, h.Tickets.Count(t => t.ShortcutId == s.Id));
    }

    [Fact]
    public void TodaysOccurrenceBecomesTodoAndIsAnnounced()
    {
        var h = Home();
        var s = Repeating(h, new RepeatRule { Mode = "after", Every = 2, Active = true }, "member");
        s.AssigneeId = "b";
        Recurrence.Tick(h, At(9, 25));
        Rules.Schedule(h, At(9, 25));
        Assert.Equal("todo", Open(h, s).StageId);
        Assert.Contains(h.Notifications, n => n.Kind == "start" && n.MemberId == "b");
    }

    [Fact]
    public void PausedOrManualShortcutsCreateNothing()
    {
        var h = Home();
        Repeating(h, new RepeatRule { Mode = "after", Every = 1, Active = false });
        Recurrence.Tick(h, At(9, 25));
        Assert.Empty(h.Tickets);
        h.Maintenance = true;
        Repeating(h, new RepeatRule { Mode = "after", Every = 1, Active = true });
        Recurrence.Tick(h, At(9, 25));
        Assert.Empty(h.Tickets);
    }

    [Fact]
    public void SkipClosesWithoutCountingAndSchedulesTheNext()
    {
        var h = Home();
        var s = Repeating(h, new RepeatRule { Mode = "weekly", Every = 1, Days = [2], Active = true });
        Recurrence.Tick(h, At(9, 25));
        var first = Open(h, s);
        Assert.Equal(Day(9, 29), first.StartDate);
        Recurrence.Skip(h, first, "a", At(9, 25));
        Assert.Equal("abandoned", first.StageId);
        Assert.Contains(first.History, e => e.Action == "skip");
        Recurrence.Tick(h, At(9, 25));
        Assert.Equal(Day(10, 6), Open(h, s).StartDate);
        Assert.Throws<RuleException>(() => Recurrence.Skip(h, first, "a", At(9, 25)));
    }

    [Fact]
    public void AutomaticAssignmentFollowsTheLastPerformerOrAlternates()
    {
        var h = Home();
        var byLauncher = Repeating(h, new RepeatRule { Mode = "after", Every = 1, Active = true }, "launcher");
        var rotating = Repeating(h, new RepeatRule { Mode = "after", Every = 1, Active = true }, "rotation");
        Recurrence.Tick(h, At(9, 25));
        Assert.Empty(Open(h, byLauncher).Assignees);
        var firstRotation = Open(h, rotating).Assignees.Single();
        Close(Open(h, byLauncher), At(9, 25), by: "b");
        Close(Open(h, rotating), At(9, 25), by: firstRotation);
        Recurrence.Tick(h, At(9, 25, 12));
        Assert.Equal(["b"], Open(h, byLauncher).Assignees);
        Assert.NotEqual(firstRotation, Open(h, rotating).Assignees.Single());
    }

    [Fact]
    public void SuggestionsAreProposedInactiveOnceAndNeverOverrideAChoice()
    {
        var h = Home();
        var bins = h.Shortcuts.Single(s => s.SeedKey == "bins");
        bins.Repeat = new RepeatRule { Mode = "weekly", Every = 1, Days = [4], Active = true };
        Recurrence.SuggestOnce(h);
        var laundry = h.Shortcuts.Single(s => s.SeedKey == "laundry");
        Assert.Equal(("after", 3, false), (laundry.Repeat!.Mode, laundry.Repeat.Every, laundry.Repeat.Active));
        Assert.Equal([4], bins.Repeat.Days);
        laundry.Repeat = null;
        Recurrence.SuggestOnce(h);
        Assert.Null(laundry.Repeat);
        Recurrence.Tick(h, At(9, 25));
        Assert.Single(h.Tickets, t => t.ShortcutId == bins.Id);
    }

    [Fact]
    public void PreviewShowsTheOpenOccurrenceOrTheNextOne()
    {
        var h = Home();
        var s = Repeating(h, new RepeatRule { Mode = "monthly", MonthDay = 5, Active = true });
        Assert.Equal(Day(10, 5), Recurrence.Preview(h, s, At(9, 25)));
        Recurrence.Tick(h, At(9, 25));
        Assert.Equal(Day(10, 5), Recurrence.Preview(h, s, At(9, 26)));
        Assert.Null(Recurrence.Preview(h, new Shortcut(), At(9, 25)));
    }
}
