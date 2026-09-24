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
        Assert.Throws<RuleException>(() => Appearance.Apply(a, null));
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
    public void BoldPalettesAreAccepted(string id)
    {
        var member = new Member();
        Appearance.Apply(member, id);
        Assert.Equal(id, member.PaletteId);
    }
    [Fact]
    public void PreviousDataUsesOriginalPalette()
    {
        var member = System.Text.Json.JsonSerializer.Deserialize<Member>("{}", Defaults.Json)!;
        Assert.Equal("sage", member.PaletteId);
    }
}
