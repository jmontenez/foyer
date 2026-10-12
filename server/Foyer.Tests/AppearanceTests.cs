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
        Appearance.Apply(a, "encre");
        Assert.Equal("encre", a.PaletteId);
        Assert.Equal("sauge", b.PaletteId);
        Assert.Equal("09:15", a.DigestTime);
        Assert.False(a.DigestEnabled);
        Assert.Throws<RuleException>(() => Appearance.Apply(a, "unknown"));
        Assert.Throws<RuleException>(() => Appearance.Apply(a, (string?)null));
        Assert.Equal("encre", a.PaletteId);
    }
    // Modèle « Découpes » : trois duos, chacun en clair et en veillée.
    [Theory]
    [InlineData("sauge")]
    [InlineData("encre")]
    [InlineData("prune")]
    [InlineData("sauge-nuit")]
    [InlineData("encre-nuit")]
    [InlineData("prune-nuit")]
    public void DuosAreAccepted(string id)
    {
        var member = new Member();
        Appearance.Apply(member, id);
        Assert.Equal(id, member.PaletteId);
    }
    [Fact]
    public void DesignTokensAreValidatedTogetherAndKeptWhenOmitted()
    {
        var m = new Member();
        Appearance.Apply(m, new AppearanceInput("encre", "grotesk", "rows", "compact", "sharp"));
        Assert.Equal(("encre", "grotesk", "rows", "compact", "sharp"), (m.PaletteId, m.FontId, m.ListStyle, m.Density, m.Corners));
        Appearance.Apply(m, "sauge");
        Assert.Equal(("sauge", "grotesk", "rows"), (m.PaletteId, m.FontId, m.ListStyle));
        Assert.Throws<RuleException>(() => Appearance.Apply(m, new AppearanceInput("encre", "comic-sans")));
        Assert.Equal(("sauge", "grotesk"), (m.PaletteId, m.FontId));
        Assert.Throws<RuleException>(() => Appearance.Apply(m, new AppearanceInput(null)));
    }
    [Fact]
    public void CustomPaletteValidatesColorsAndKeepsThem()
    {
        var m = new Member();
        Appearance.Apply(m, new AppearanceInput("custom", CustomPrimary: "#1F4FE0", CustomAccent: "#facc15", CustomDark: true));
        Assert.Equal(("custom", "#1F4FE0", "#facc15", true), (m.PaletteId, m.CustomPrimary, m.CustomAccent, m.CustomDark));
        // Repasser sur une palette prédéfinie garde le duo mémorisé.
        Appearance.Apply(m, "sauge");
        Assert.Equal(("sauge", "#1F4FE0", true), (m.PaletteId, m.CustomPrimary, m.CustomDark));
        Assert.Throws<RuleException>(() => Appearance.Apply(m, new AppearanceInput("custom", CustomPrimary: "1F4FE0")));
        Assert.Throws<RuleException>(() => Appearance.Apply(m, new AppearanceInput("custom", CustomAccent: "#GG4FE0")));
        Assert.Throws<RuleException>(() => Appearance.Apply(m, new AppearanceInput("custom", CustomPrimary: "#1F4FE012")));
        // Tout est validé avant d'appliquer : rien n'a bougé.
        Assert.Equal(("sauge", "#1F4FE0", "#facc15"), (m.PaletteId, m.CustomPrimary, m.CustomAccent));
    }
    [Fact]
    public void PreviousMembersGetNeutralTokens()
    {
        // Le serveur ne valide pas à la lecture : une ancienne palette stockée est
        // conservée telle quelle (le client la ramène vers un duo connu à l'affichage).
        var member = System.Text.Json.JsonSerializer.Deserialize<Member>("""{"paletteId":"violet-navy"}""", Defaults.Json)!;
        Assert.Equal(("violet-navy", "system", "cards", "comfortable", "soft"), (member.PaletteId, member.FontId, member.ListStyle, member.Density, member.Corners));
    }
    [Fact]
    public void PreviousDataUsesOriginalPalette()
    {
        var member = System.Text.Json.JsonSerializer.Deserialize<Member>("{}", Defaults.Json)!;
        Assert.Equal("sauge", member.PaletteId);
        Assert.Equal(("#386653", "#B58A44", false), (member.CustomPrimary, member.CustomAccent, member.CustomDark));
    }
}
