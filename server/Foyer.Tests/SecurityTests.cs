using Foyer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Xunit;
namespace Foyer.Tests;

public class SecurityTests
{
    private static Settings Settings(string? clientIpHeader = null) => new(new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
    {
        ["AllowedEmails"] = "a@example.invalid,b@example.invalid",
        ["PublicOrigin"] = "https://foyer.test",
        ["ClientIpHeader"] = clientIpHeader
    }).Build(), new TestEnvironment());

    [Fact]
    public void ThirdAccountCannotCreateMemberOrSession()
    {
        var h = new Household();
        var ex = Assert.Throws<RuleException>(() => Security.Login(h, Settings(), "stranger", "c@example.invalid", "Other", "Test"));
        Assert.Equal(403, ex.Status);
        Assert.Empty(h.Members);
        Assert.Empty(h.Sessions);
    }

    [Fact]
    public void SameEmailCannotRebindExistingGoogleSubject()
    {
        var h = new Household();
        Security.Login(h, Settings(), "original", "a@example.invalid", "A", "Test");
        Assert.Throws<RuleException>(() => Security.Login(h, Settings(), "replacement", "a@example.invalid", "A", "Test"));
        Assert.Single(h.Members);
    }

    [Fact]
    public void OnlyHashIsPersistedAndRevocationTakesEffect()
    {
        var h = new Household();
        var login = Security.Login(h, Settings(), "a", "a@example.invalid", "A", "Test");
        Assert.NotEqual(login.token, h.Sessions[0].Hash);
        Assert.Equal(Security.Hash(login.token), h.Sessions[0].Hash);
        var ctx = new DefaultHttpContext();
        ctx.Request.Headers.Authorization = "Bearer " + login.token;
        Assert.Equal(login.member.Id, Security.Member(ctx, h).Id);
        h.Sessions.Clear();
        Assert.Equal(401, Assert.Throws<RuleException>(() => Security.Member(ctx, h)).Status);
    }

    [Fact]
    public void CookieWritesNeedSameOriginAndCustomHeader()
    {
        var ctx = new DefaultHttpContext();
        ctx.Request.Headers["X-Foyer-CSRF"] = "1";
        Assert.Throws<RuleException>(() => Security.CheckWrite(ctx, Settings()));
        ctx.Request.Headers.Origin = "https://intrus.invalid";
        Assert.Throws<RuleException>(() => Security.CheckWrite(ctx, Settings()));
        ctx.Request.Headers.Origin = "https://foyer.test";
        Security.CheckWrite(ctx, Settings());
        ctx.Request.Headers.Remove("X-Foyer-CSRF");
        Assert.Throws<RuleException>(() => Security.CheckWrite(ctx, Settings()));
    }

    [Fact]
    public void NativeBearerCanWriteWithoutBrowserOrigin()
    {
        var ctx = new DefaultHttpContext();
        ctx.Request.Headers.Authorization = "Bearer test";
        ctx.Request.Headers["X-Foyer-CSRF"] = "1";
        Security.CheckWrite(ctx, Settings());
    }

    private static DefaultHttpContext Peer(string ip)
    {
        var ctx = new DefaultHttpContext();
        ctx.Connection.RemoteIpAddress = System.Net.IPAddress.Parse(ip);
        return ctx;
    }

    [Fact]
    public void SpoofedClientIpHeaderIsIgnoredWithoutConfiguredProxy()
    {
        var ctx = Peer("10.0.0.9");
        ctx.Request.Headers["CF-Connecting-IP"] = "203.0.113.7";
        Assert.Equal("10.0.0.9", Security.ClientIp(ctx, Settings()));
    }

    [Fact]
    public void ConfiguredProxyHeaderResolvesVisitorAddress()
    {
        var ctx = Peer("10.0.0.9");
        ctx.Request.Headers["CF-Connecting-IP"] = "203.0.113.7";
        Assert.Equal("203.0.113.7", Security.ClientIp(ctx, Settings("CF-Connecting-IP")));
    }

    [Fact]
    public void MissingOrUnparseableHeaderFallsBackToNetworkPeer()
    {
        var settings = Settings("CF-Connecting-IP");
        Assert.Equal("10.0.0.9", Security.ClientIp(Peer("10.0.0.9"), settings));
        var ctx = Peer("10.0.0.9");
        ctx.Request.Headers["CF-Connecting-IP"] = "not-an-address";
        Assert.Equal("10.0.0.9", Security.ClientIp(ctx, settings));
    }

    [Fact]
    public void LastHeaderValueWinsWhenSeveralArePresent()
    {
        // Seule la valeur écrite par le proxy de confiance (la dernière) fait foi.
        var ctx = Peer("10.0.0.9");
        ctx.Request.Headers.Append("CF-Connecting-IP", "198.51.100.1");
        ctx.Request.Headers.Append("CF-Connecting-IP", "203.0.113.7");
        Assert.Equal("203.0.113.7", Security.ClientIp(ctx, Settings("CF-Connecting-IP")));
    }

    [Fact]
    public void AuthPathsCoverAuthenticationAndOauthCallback()
    {
        Assert.True(Security.AuthPath("/auth/google/start"));
        Assert.True(Security.AuthPath("/auth/config"));
        Assert.True(Security.AuthPath("/signin-google"));
        Assert.False(Security.AuthPath("/api/v1/state"));
        Assert.False(Security.AuthPath("/"));
        Assert.False(Security.AuthPath("/authother"));
    }

    private sealed class TestEnvironment : IWebHostEnvironment
    {
        public string ApplicationName { get; set; } = "Foyer.Tests";
        public string EnvironmentName { get; set; } = "Development";
        public string ContentRootPath { get; set; } = "/tmp";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
        public string WebRootPath { get; set; } = "/tmp";
        public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
    }
}
