using Foyer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Xunit;
namespace Foyer.Tests;

public class DemoTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 25, 10, 0, 0, TimeSpan.Zero);
    private static IConfiguration Config(Dictionary<string, string?> extra) => new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
    {
        ["PublicDemo"] = "true",
        ["AllowedEmails"] = "camille@demo.invalid,alex@demo.invalid",
        ["PublicOrigin"] = "https://demofoyer.test",
    }.Concat(extra).GroupBy(p => p.Key).ToDictionary(g => g.Key, g => g.Last().Value)).Build();
    private static (Settings, IConfiguration) Demo_(Dictionary<string, string?>? extra = null)
    {
        var c = Config(extra ?? []);
        return (new Settings(c, new TestEnvironment()), c);
    }

    [Fact]
    public void FictitiousDemoStarts()
    {
        var (s, c) = Demo_();
        Assert.True(s.PublicDemo);
        Assert.Null(Demo.Refusal(s, c));
    }

    [Theory]
    [InlineData("AllowedEmails", "vrai@gmail.com,alex@demo.invalid")]
    [InlineData("AllowedEmails", "camille@demo.invalid")]
    [InlineData("GoogleClientId", "123.apps.googleusercontent.com")]
    [InlineData("GoogleClientSecret", "secret")]
    [InlineData("FirebaseCredentialFile", "/run/secrets/firebase")]
    [InlineData("WorkersEnabled", "true")]
    public void RealAccountsSecretsOrWorkersRefuseToStart(string key, string value)
    {
        var (s, c) = Demo_(new() { [key] = value });
        Assert.NotNull(Demo.Refusal(s, c));
    }

    [Fact]
    public void SeedIsCompleteAndRelativeToToday()
    {
        var (s, _) = Demo_();
        var today = new DateOnly(2026, 9, 25);
        var h = Demo.Seed(s, today, Now);
        Assert.Equal(["camille@demo.invalid", "alex@demo.invalid"], h.Members.Select(m => m.Email));
        Assert.Equal(["demo-0", "demo-1"], h.Members.Select(m => m.Subject));
        Assert.Equal(h.Tickets.Count, h.Tickets.Select(t => t.Number).Distinct().Count());
        Assert.Contains(h.Tickets, t => t.DueDate < today && !Rules.Closed(t));
        Assert.Contains(h.Tickets, t => t.Kind == "wish" && t.StageId == "backlog");
        Assert.Contains(h.Tickets, t => t.StageId == "done" && t.Performers.Count > 0 && t.ClosedAt is not null);
        var ids = h.Members.Select(m => m.Id).ToHashSet();
        Assert.All(h.Tickets, t =>
        {
            Assert.All(t.Assignees.Concat(t.Performers), id => Assert.Contains(id, ids));
            Assert.All(t.TagIds, id => Assert.Contains(h.Tags, g => g.Id == id));
            Assert.True(t.StageId is "backlog" or "done" or "abandoned" || h.Stages.Any(st => st.Id == t.StageId), t.StageId);
        });
        Assert.Contains(h.Tickets, t => Rules.TodayView(h, t, today));
    }

    [Fact]
    public void DemoLoginReusesSeededMembers()
    {
        var (s, _) = Demo_();
        var h = new Household();
        Demo.Reset(h, s, Now);
        var (member, _) = Security.Login(h, s, "demo-1", "alex@demo.invalid", "Alex", "Démonstration");
        Assert.Equal("Alex", member.Name);
        Assert.Equal(2, h.Members.Count);
    }

    [Fact]
    public void ResetWipesEverythingIncludingSessions()
    {
        var (s, _) = Demo_();
        var h = new Household();
        Demo.Reset(h, s, Now);
        Security.Login(h, s, "demo-0", "camille@demo.invalid", "Camille", "Test");
        h.Tickets.Add(new Ticket { Title = "Graffiti" });
        h.Maintenance = true;
        Demo.Reset(h, s, Now);
        Assert.Empty(h.Sessions);
        Assert.DoesNotContain(h.Tickets, t => t.Title == "Graffiti");
        Assert.False(h.Maintenance);
    }

    [Fact]
    public void SessionsAreCapped()
    {
        var h = new Household();
        for (var i = 0; i < Demo.MaxSessions + 25; i++)
            h.Sessions.Add(new($"h{i}", "m", "d", Now.AddMinutes(i), Now.AddDays(30)));
        h.Devices.Add(new("d0", "m", "h0", "token", Now));
        Demo.PruneSessions(h);
        Assert.Equal(Demo.MaxSessions, h.Sessions.Count);
        Assert.DoesNotContain(h.Sessions, x => x.Hash == "h0");
        Assert.Empty(h.Devices);
    }

    private sealed class TestEnvironment : IWebHostEnvironment
    {
        public string ApplicationName { get; set; } = "Foyer.Tests";
        public string EnvironmentName { get; set; } = "Production";
        public string ContentRootPath { get; set; } = "/tmp";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
        public string WebRootPath { get; set; } = "/tmp";
        public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
    }
}
