using Foyer;
using Xunit;
namespace Foyer.Tests;

public class AppearanceTests
{
    [Fact]
    public void PaletteOnlyChangesSelectedMemberAndPreservesReminder()
    {
        var a = new Member { DigestTime = "09:15", DigestEnabled = false };
        var b = new Member();
        Appearance.Apply(a, "sky-orange");
        Assert.Equal("sky-orange", a.PaletteId);
        Assert.Equal("sage", b.PaletteId);
        Assert.Equal("09:15", a.DigestTime);
        Assert.False(a.DigestEnabled);
        Assert.Throws<RuleException>(() => Appearance.Apply(a, "unknown"));
        Assert.Throws<RuleException>(() => Appearance.Apply(a, (string?)null));
        Assert.Equal("sky-orange", a.PaletteId);
    }
    [Theory]
    [InlineData("ember-night")]
    [InlineData("lime-charcoal")]
    [InlineData("ruby-onyx")]
    [InlineData("electric-violet")]
    [InlineData("abyss-cyan")]
    [InlineData("tomato-teal")]
    [InlineData("royal-sun")]
    [InlineData("fuchsia-lemon")]
    [InlineData("ink-coral")]
    public void BoldPalettesAreAccepted(string id)
    {
        var member = new Member();
        Appearance.Apply(member, id);
        Assert.Equal(id, member.PaletteId);
    }
    [Fact]
    public void DesignTokensAreValidatedTogetherAndKeptWhenOmitted()
    {
        var m = new Member();
        Appearance.Apply(m, new AppearanceInput("ember-night", "grotesk", "rows", "compact", "sharp"));
        Assert.Equal(("ember-night", "grotesk", "rows", "compact", "sharp"), (m.PaletteId, m.FontId, m.ListStyle, m.Density, m.Corners));
        Appearance.Apply(m, "sage");
        Assert.Equal(("sage", "grotesk", "rows"), (m.PaletteId, m.FontId, m.ListStyle));
        Assert.Throws<RuleException>(() => Appearance.Apply(m, new AppearanceInput("ink-coral", "comic-sans")));
        Assert.Equal(("sage", "grotesk"), (m.PaletteId, m.FontId));
        Assert.Throws<RuleException>(() => Appearance.Apply(m, new AppearanceInput(null)));
    }
    [Fact]
    public void PreviousMembersGetNeutralTokens()
    {
        var member = System.Text.Json.JsonSerializer.Deserialize<Member>("""{"paletteId":"violet-navy"}""", Defaults.Json)!;
        Assert.Equal(("violet-navy", "system", "cards", "comfortable", "soft"), (member.PaletteId, member.FontId, member.ListStyle, member.Density, member.Corners));
    }
    [Fact]
    public void PreviousDataUsesOriginalPalette()
    {
        var member = System.Text.Json.JsonSerializer.Deserialize<Member>("{}", Defaults.Json)!;
        Assert.Equal("sage", member.PaletteId);
    }
}
