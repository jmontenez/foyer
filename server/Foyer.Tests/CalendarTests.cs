using Foyer;
using Xunit;
namespace Foyer.Tests;

public class CalendarTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 5, 8, 0, 0, TimeSpan.Zero);
    private static Household Home() => new() { Members = [new() { Id = "a", Subject = "a", Name = "Alice" }, new() { Id = "b", Subject = "b", Name = "Bob" }] };

    // Tâche avec heure + durée (nouvelle option « temps » des tâches).
    private static TicketInput Task(Ticket t, int? startMinute = null, int? duration = null, DateOnly? due = null) =>
        new(t.Title, "", "obligation", "normal", "todo", t.StartDate, due ?? t.DueDate, t.Assignees, [], [], [], t.Version, null, startMinute, duration);

    private static CalendarEventInput Ev(string title = "Anniv Léa", bool allDay = true, string category = "birthday",
        List<string>? participants = null, string? taskId = null) => new(
        title,
        new DateTimeOffset(2026, 11, 10, 0, 0, 0, TimeSpan.Zero),
        new DateTimeOffset(2026, 11, 10, 23, 59, 0, TimeSpan.Zero),
        allDay, category, participants, null, null, null, taskId);

    [Fact]
    public void DatedTaskGainsTimeAndDuration()
    {
        var h = Home();
        var t = new Ticket { Title = "RDV dentiste" };
        Rules.Apply(h, t, Task(t, 540, 60, new(2026, 11, 6)), "a", Now);
        Assert.Equal((540, 60), (t.StartMinute, t.DurationMinutes));
    }

    [Fact]
    public void TimeNeedsADateAndValidRange()
    {
        var h = Home();
        var t = new Ticket { Title = "X" };
        // Une heure sans date d'échéance est refusée.
        Assert.Throws<RuleException>(() => Rules.Apply(h, t, Task(t, 540, 60), "a", Now));
        // Heure et durée hors bornes.
        Assert.Throws<RuleException>(() => Rules.Apply(h, t, Task(t, 1440, 60, new(2026, 11, 6)), "a", Now));
        Assert.Throws<RuleException>(() => Rules.Apply(h, t, Task(t, 540, 0, new(2026, 11, 6)), "a", Now));
        Assert.Null(t.StartMinute);
    }

    [Fact]
    public void DoneKeepsTheTime()
    {
        var h = Home();
        var t = new Ticket { Title = "RDV" };
        Rules.Apply(h, t, Task(t, 600, 30, new(2026, 11, 6)), "a", Now);
        Rules.Done(h, t, "a", Now);
        Assert.Equal((600, 30, "done"), (t.StartMinute, t.DurationMinutes, t.StageId));
    }

    [Fact]
    public void EventCreateValidatesAndStoresLocal()
    {
        var h = Home();
        var e = CalendarEvents.Apply(h, null, Ev(participants: ["a"]), Now);
        Assert.Single(h.Events);
        Assert.Equal(("Anniv Léa", "birthday", "local", true), (e.Title, e.Category, e.Source, e.AllDay));
        Assert.Equal(["a"], e.Participants);
    }

    [Fact]
    public void EventUpdateKeepsIdentity()
    {
        var h = Home();
        var e = CalendarEvents.Apply(h, null, Ev(), Now);
        var again = CalendarEvents.Apply(h, e, Ev(title: "Anniv Léa (déplacé)"), Now);
        Assert.Same(e, again);
        Assert.Single(h.Events);
        Assert.Equal("Anniv Léa (déplacé)", h.Events[0].Title);
    }

    [Fact]
    public void EventRejectsBadInputAndStoresNothing()
    {
        var h = Home();
        Assert.Throws<RuleException>(() => CalendarEvents.Apply(h, null, Ev(title: " "), Now));
        Assert.Throws<RuleException>(() => CalendarEvents.Apply(h, null, Ev(category: "party"), Now));
        Assert.Throws<RuleException>(() => CalendarEvents.Apply(h, null, Ev(participants: ["zzz"]), Now));
        Assert.Throws<RuleException>(() => CalendarEvents.Apply(h, null, Ev(taskId: "nope"), Now));
        var endBeforeStart = new CalendarEventInput("X",
            new DateTimeOffset(2026, 11, 10, 12, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 11, 10, 11, 0, 0, TimeSpan.Zero));
        Assert.Throws<RuleException>(() => CalendarEvents.Apply(h, null, endBeforeStart, Now));
        Assert.Empty(h.Events);
    }

    [Fact]
    public void EventReminderFiresOnceInWindowAndSkipsAllDay()
    {
        var h = Home();
        h.Members.ForEach(m => m.DigestEnabled = false);
        var start = new DateTimeOffset(2026, 11, 10, 14, 0, 0, TimeSpan.Zero);
        CalendarEvents.Apply(h, null, new CalendarEventInput("RDV", start, start.AddHours(1), ReminderMinutes: 60, Participants: ["a"]), Now);
        CalendarEvents.Apply(h, null, new CalendarEventInput("Anniv", start, start, AllDay: true, ReminderMinutes: 60), Now);
        List<Notification> fired() => h.Notifications.Where(n => n.Kind == "event").ToList();
        // Trop tôt (2 h avant) : rien.
        Rules.Schedule(h, start.AddHours(-2));
        Assert.Empty(fired());
        // Dans la fenêtre (1 h avant = le rappel choisi) : un rappel pour le participant, pas pour l'anniv.
        Rules.Schedule(h, start.AddMinutes(-60));
        Assert.Equal(("a", "RDV"), (Assert.Single(fired()).MemberId, fired()[0].Title));
        // Idempotent : une seconde passe ne re-notifie pas.
        Rules.Schedule(h, start.AddMinutes(-50));
        Assert.Single(fired());
    }
}
