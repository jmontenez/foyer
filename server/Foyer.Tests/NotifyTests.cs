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

    // Heure de Paris (UTC+2 fin septembre).
    private static DateTimeOffset Paris(int day, int hour, int minute = 0) => new(2026, 9, day, hour, minute, 0, TimeSpan.FromHours(2));
    private static Ticket Backlog(Household h, string title, DateOnly start, List<string>? who = null)
    {
        var t = new Ticket { Title = title, StageId = "backlog", StartDate = start, DueDate = start, Assignees = who ?? [] };
        h.Tickets.Add(t);
        return t;
    }

    [Fact]
    public void AtMidnightTheMorningDigestAnnouncesTheDay()
    {
        var h = Home();
        var bins = Backlog(h, "Sortir les poubelles", new(2026, 9, 26));
        Rules.Schedule(h, Paris(26, 0, 5));
        Assert.Equal("todo", bins.StageId);
        Assert.Empty(h.Notifications);
        Rules.Schedule(h, Paris(26, 8, 0));
        var digest = h.Notifications.Where(n => n.Kind == "digest").ToList();
        Assert.Equal(2, digest.Count);
        Assert.All(digest, n => Assert.Equal(("Aujourd’hui : Sortir les poubelles", "La seule tâche du jour", bins.Id), (n.Title, n.Body, n.TicketId)));
    }

    [Fact]
    public void WithoutDigestTheNightReminderWaitsForTheMorning()
    {
        var h = Home();
        h.Members.ForEach(m => m.DigestEnabled = false);
        h.Members[1].DigestTime = "07:15";
        Backlog(h, "Sortir les poubelles", new(2026, 9, 26));
        Rules.Schedule(h, Paris(26, 0, 5));
        Assert.Equal(new DateTimeOffset(2026, 9, 26, 6, 0, 0, TimeSpan.Zero), h.Notifications.Single(n => n.MemberId == "a").NextAttempt);
        Assert.Equal(new DateTimeOffset(2026, 9, 26, 5, 15, 0, TimeSpan.Zero), h.Notifications.Single(n => n.MemberId == "b").NextAttempt);
        // À 22 h 30 : le lendemain matin.
        Assert.Equal(new DateTimeOffset(2026, 9, 27, 6, 0, 0, TimeSpan.Zero), Notify.WakeAt(h, h.Members[0], Paris(26, 22, 30)));
    }

    [Fact]
    public void DaytimeRemindersLeaveRightAway()
    {
        var h = Home();
        h.Members.ForEach(m => m.DigestEnabled = false);
        var t = Backlog(h, "Faire les courses", new(2026, 9, 25), ["a"]);
        t.Shopping = true;
        t.Checklist = [new("1", "Lait", false), new("2", "Pain", true), new("3", "Œufs", false)];
        Rules.Schedule(h, Paris(25, 15));
        var n = Assert.Single(h.Notifications);
        Assert.Equal(("À faire aujourd’hui", "Faire les courses · 2 articles", Paris(25, 15)), (n.Title, n.Body, n.NextAttempt));
        Backlog(h, "A", new(2026, 9, 25)); Backlog(h, "B", new(2026, 9, 25)); Backlog(h, "C", new(2026, 9, 25)); Backlog(h, "D", new(2026, 9, 25));
        Rules.Schedule(h, Paris(25, 16));
        var many = h.Notifications.Last(x => x.MemberId == "a");
        Assert.Equal(("4 tâches à faire aujourd’hui", "A · B · C (+1)"), (many.Title, many.Body));
    }

    [Fact]
    public void DigestListsLateFirstAndSkipsEmptyDays()
    {
        var h = Home();
        var today = new DateOnly(2026, 9, 25);
        Assert.Null(Notify.Digest(h, h.Members[0], today, Now));
        h.Tickets.Add(new() { Title = "Laver la couette", StageId = "todo", DueDate = today });
        h.Tickets.Add(new() { Title = "Papiers École", StageId = "todo", DueDate = today.AddDays(-2), Assignees = ["a"] });
        var courses = new Ticket { Title = "Faire les courses", StageId = "todo", StartDate = today, Shopping = true, Checklist = [new("1", "Lait", false)] };
        h.Tickets.Add(courses);
        h.Tickets.Add(new() { Title = "Pour Clemence", StageId = "todo", DueDate = today, Assignees = ["b"] });
        var d = Notify.Digest(h, h.Members[0], today, Now)!;
        Assert.Equal("Aujourd’hui : 3 tâches, dont 1 en retard", d.Title);
        Assert.Equal("Papiers École · Laver la couette · Courses (1 article)", d.Body);
    }

    [Fact]
    public void CommentsSayWhoAndWhat()
    {
        var h = Home();
        var t = Create(h, "a", ["a"]);
        Notify.Commented(h, t, "b", "J’ai trouvé le formulaire\nil faut juste le signer et le rendre à la maîtresse avant vendredi, sinon on est en retard", Now);
        var n = Assert.Single(h.Notifications, x => x.Kind == "comment");
        Assert.Equal(("a", "Clemence a commenté"), (n.MemberId, n.Title));
        Assert.StartsWith("Papiers École — « J’ai trouvé le formulaire il faut", n.Body);
        Assert.EndsWith("… »", n.Body);
        Assert.Equal("Papiers École — « Court »", CommentBody(h, "Court"));
    }

    private static string? CommentBody(Household h, string text)
    {
        var t = Create(h, "a", ["a"]);
        Notify.Commented(h, t, "b", text, Now);
        return h.Notifications.Last(x => x.Kind == "comment").Body;
    }

    [Fact]
    public void UpdateAnnouncementsWaitForTheMorning()
    {
        var h = Home();
        h.Devices = [new("p", "a", "s", "token", Now, 1)];
        Rules.AnnounceUpdate(h, 2, Paris(25, 23, 30));
        var n = Assert.Single(h.Notifications);
        Assert.Equal(("Mise à jour de Foyer", new DateTimeOffset(2026, 9, 26, 6, 0, 0, TimeSpan.Zero)), (n.Title, n.NextAttempt));
    }

    [Fact]
    public void CommentBurstsReplaceOneNotification()
    {
        var h = Home();
        var t = Create(h, "a", ["a"]);
        var other = Create(h, "a", ["a"]);
        Notify.Commented(h, t, "b", "Premier", Now);
        var first = Assert.Single(h.Notifications, n => n.Kind == "comment");
        first.Finished = true; first.DeliveredDeviceIds.Add("p");
        Notify.Commented(h, t, "b", "Deuxième", Now.AddMinutes(2));
        Notify.Commented(h, t, "b", "Troisième", Now.AddMinutes(5));
        var n = Assert.Single(h.Notifications, x => x.Kind == "comment");
        Assert.Equal((3, "3 nouveaux commentaires", "Papiers École — « Troisième »", false), (n.Count, n.Title, n.Body, n.Finished));
        Assert.Empty(n.DeliveredDeviceIds);
        Assert.Equal(Now.AddMinutes(5), n.NextAttempt);
        // Autre tâche, ou plus de 30 minutes après : une nouvelle notification.
        Notify.Commented(h, other, "b", "Ailleurs", Now.AddMinutes(6));
        Notify.Commented(h, t, "b", "Plus tard", Now.AddMinutes(31));
        Assert.Equal(3, h.Notifications.Count(x => x.Kind == "comment"));
    }

    [Fact]
    public void AssignmentBurstsListTheTasks()
    {
        var h = Home();
        foreach (var title in new[] { "Lessive", "Poubelles", "Courses", "Vaisselle" })
        {
            var t = new Ticket();
            Rules.Apply(h, t, Input(["a"]) with { Title = title }, "b", Now, true);
            h.Tickets.Add(t);
        }
        var n = Assert.Single(Assigns(h));
        Assert.Equal((4, "Clemence vous a confié 4 tâches", "Lessive · Poubelles · Courses (+1)", (string?)null), (n.Count, n.Title, n.Body, n.TicketId));
    }

    [Theory]
    [InlineData("start", "foyer_reminders")]
    [InlineData("digest", "foyer_reminders")]
    [InlineData("comment", "foyer_activity")]
    [InlineData("assign", "foyer_activity")]
    [InlineData("update", "foyer_updates")]
    public void EachKindHasItsAndroidChannel(string kind, string channel) => Assert.Equal(channel, Notify.Channel(kind));
}
