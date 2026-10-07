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
    // Refonte « Découpes » : ids v2 acceptés en amont, le temps de la beta.
    [Theory]
    [InlineData("d2-sauge")]
    [InlineData("d2-encre")]
    [InlineData("d2-terre")]
    [InlineData("d2-sauge-nuit")]
    [InlineData("d2-braise-nuit")]
    [InlineData("d2-prune-nuit")]
    public void RedesignPalettesAreAccepted(string id)
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
    public void CustomPaletteValidatesColorsAndKeepsThem()
    {
        var m = new Member();
        Appearance.Apply(m, new AppearanceInput("custom", CustomPrimary: "#1F4FE0", CustomAccent: "#facc15", CustomDark: true));
        Assert.Equal(("custom", "#1F4FE0", "#facc15", true), (m.PaletteId, m.CustomPrimary, m.CustomAccent, m.CustomDark));
        // Repasser sur une palette prédéfinie garde le duo mémorisé.
        Appearance.Apply(m, "sage");
        Assert.Equal(("sage", "#1F4FE0", true), (m.PaletteId, m.CustomPrimary, m.CustomDark));
        Assert.Throws<RuleException>(() => Appearance.Apply(m, new AppearanceInput("custom", CustomPrimary: "1F4FE0")));
        Assert.Throws<RuleException>(() => Appearance.Apply(m, new AppearanceInput("custom", CustomAccent: "#GG4FE0")));
        Assert.Throws<RuleException>(() => Appearance.Apply(m, new AppearanceInput("custom", CustomPrimary: "#1F4FE012")));
        // Tout est validé avant d'appliquer : rien n'a bougé.
        Assert.Equal(("sage", "#1F4FE0", "#facc15"), (m.PaletteId, m.CustomPrimary, m.CustomAccent));
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
        Assert.Equal(("#386653", "#B58A44", false), (member.CustomPrimary, member.CustomAccent, member.CustomDark));
    }
}
