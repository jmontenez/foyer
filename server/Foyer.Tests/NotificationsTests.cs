using Foyer;
using Xunit;
namespace Foyer.Tests;

public class NotificationsTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 27, 10, 0, 0, TimeSpan.Zero);
    private static Household Home() => new() { Members = [new() { Id = "a", Subject = "a", Name = "Alice" }, new() { Id = "b", Subject = "b", Name = "Bob" }] };
    [Fact] public void UnreadCountsPerMemberAndOnlyAfterSeen() { var h = Home(); h.Notifications = [new() { MemberId = "a", Kind = "comment", CreatedAt = Now.AddMinutes(-10) }, new() { MemberId = "a", Kind = "assign", CreatedAt = Now }, new() { MemberId = "b", Kind = "digest", CreatedAt = Now }]; Assert.Equal(2, Rules.Unread(h, h.Members[0])); Assert.Equal(1, Rules.Unread(h, h.Members[1])); h.Members[0].NotificationsSeenAt = Now.AddMinutes(-5); Assert.Equal(1, Rules.Unread(h, h.Members[0])); h.Members[0].NotificationsSeenAt = Now; Assert.Equal(0, Rules.Unread(h, h.Members[0])); }
    [Fact] public void UpdateAnnouncementsStayOutOfHistoryAndUnread() { var h = Home(); h.Notifications = [new() { MemberId = "a", Kind = "update", CreatedAt = Now, BelowVersion = 2110 }, new() { MemberId = "a", Kind = "start", CreatedAt = Now }]; Assert.Equal(1, Rules.Unread(h, h.Members[0])); Assert.Equal(["start"], h.Notifications.Where(n => Rules.Historic(n)).Select(n => n.Kind)); }
    [Fact] public void PreviousDataDeserializesWithoutSeenAt() { var h = System.Text.Json.JsonSerializer.Deserialize<Household>("""{"members":[{"id":"a","subject":"a","name":"Alice"}],"notifications":[{"id":"n","memberId":"a","kind":"comment","createdAt":"2026-09-24T20:00:00+00:00"}]}""", Defaults.Json)!; Assert.Null(h.Members[0].NotificationsSeenAt); Assert.Equal(1, Rules.Unread(h, h.Members[0])); }
}
