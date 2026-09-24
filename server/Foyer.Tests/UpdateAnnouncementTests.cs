using Foyer;
using Xunit;
namespace Foyer.Tests;

public class UpdateAnnouncementTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 24, 20, 0, 0, TimeSpan.Zero);
    private static Household Home(params Device[] devices) => new()
    {
        Members = [new() { Id = "a", Subject = "a", Name = "Alice" }, new() { Id = "b", Subject = "b", Name = "Bob" }],
        Devices = [.. devices]
    };
    private static Device Phone(string id, string member, long? version) => new(id, member, "s-" + id, "token-" + id, Now, version);

    [Fact]
    public void NewVersionIsAnnouncedOnceToMembersWithOutdatedDevices()
    {
        var h = Home(Phone("pa", "a", 2115), Phone("pb", "b", 2116));
        Rules.AnnounceUpdate(h, 2116, Now);
        Rules.AnnounceUpdate(h, 2116, Now);
        var n = Assert.Single(h.Notifications);
        Assert.Equal(("a", "update", 2116L), (n.MemberId, n.Kind, n.BelowVersion!.Value));
        Assert.Equal(2116, h.AnnouncedAndroidVersion);
    }

    [Fact]
    public void DevicesWithoutDeclaredVersionAreConsideredOutdated()
    {
        var h = Home(Phone("pa", "a", null));
        Rules.AnnounceUpdate(h, 2116, Now);
        Assert.Equal(["pa"], Rules.Recipients(h, Assert.Single(h.Notifications)).Select(d => d.Id));
    }

    [Fact]
    public void OnlyOutdatedDevicesOfTheMemberReceiveTheAnnouncement()
    {
        var h = Home(Phone("old", "a", 2110), Phone("new", "a", 2116), Phone("other", "b", 2100));
        var n = new Notification { MemberId = "a", Kind = "update", BelowVersion = 2116 };
        Assert.Equal(["old"], Rules.Recipients(h, n).Select(d => d.Id));
        var comment = new Notification { MemberId = "a", Kind = "comment" };
        Assert.Equal(["old", "new"], Rules.Recipients(h, comment).Select(d => d.Id));
    }

    [Fact]
    public void NewerVersionReplacesPendingAnnouncementAndOlderIsIgnored()
    {
        var h = Home(Phone("pa", "a", 2110));
        Rules.AnnounceUpdate(h, 2116, Now);
        Rules.AnnounceUpdate(h, 2117, Now);
        Rules.AnnounceUpdate(h, 2112, Now);
        Assert.Equal(2, h.Notifications.Count);
        Assert.True(h.Notifications[0].Finished);
        Assert.Equal(2117, h.Notifications.Single(n => !n.Finished).BelowVersion);
        Assert.Equal(2117, h.AnnouncedAndroidVersion);
    }

    [Fact]
    public void NothingPublishedOrMaintenanceAnnouncesNothing()
    {
        var h = Home(Phone("pa", "a", 2110));
        Rules.AnnounceUpdate(h, null, Now);
        h.Maintenance = true;
        Rules.AnnounceUpdate(h, 2116, Now);
        Assert.Empty(h.Notifications);
        Assert.Equal(0, h.AnnouncedAndroidVersion);
    }

    [Fact]
    public void PreviousDataDeserializesWithoutVersions()
    {
        var h = System.Text.Json.JsonSerializer.Deserialize<Household>("""{"devices":[{"id":"d","memberId":"a","sessionHash":"s","token":"t","updatedAt":"2026-09-24T20:00:00+00:00"}],"notifications":[{"id":"n","memberId":"a"}]}""", Defaults.Json)!;
        Assert.Null(h.Devices[0].AppVersion);
        Assert.Null(h.Notifications[0].BelowVersion);
        Assert.Equal(0, h.AnnouncedAndroidVersion);
    }
}
