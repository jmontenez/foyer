using Foyer;
using Xunit;
namespace Foyer.Tests;

public sealed class UpdatesTests : IDisposable
{
    private readonly string dir = Directory.CreateTempSubdirectory("foyer-updates-").FullName;
    private static readonly string Sha = new('a', 64);
    public void Dispose() => Directory.Delete(dir, true);

    private void Publish(string manifest, int apkBytes = 10)
    {
        File.WriteAllBytes(Path.Combine(dir, Updates.Apk), new byte[apkBytes]);
        File.WriteAllText(Path.Combine(dir, Updates.Manifest), manifest);
    }

    [Fact]
    public void ValidManifestIsExposed()
    {
        Publish($$"""{"versionCode":2108,"versionName":"1.0.0","sha256":"{{Sha}}","size":10}""");
        var release = Updates.Android(dir);
        Assert.NotNull(release);
        Assert.Equal(2108, release.VersionCode);
        Assert.Equal("1.0.0", release.VersionName);
    }

    [Fact]
    public void NothingPublishedMeansNoUpdate() => Assert.Null(Updates.Android(dir));

    [Fact]
    public void MissingApkMeansNoUpdate()
    {
        File.WriteAllText(Path.Combine(dir, Updates.Manifest), $$"""{"versionCode":2108,"versionName":"1.0.0","sha256":"{{Sha}}","size":10}""");
        Assert.Null(Updates.Android(dir));
    }

    [Theory]
    [InlineData("""{"versionCode":2108,"versionName":"1.0.0","sha256":"SHA","size":11}""")] // copie partielle
    [InlineData("""{"versionCode":0,"versionName":"1.0.0","sha256":"SHA","size":10}""")]
    [InlineData("""{"versionCode":2108,"versionName":"","sha256":"SHA","size":10}""")]
    [InlineData("""{"versionCode":2108,"versionName":"1.0.0","sha256":"ABC","size":10}""")]
    [InlineData("""{"versionCode":2108,"versionName":"1.0.0","size":10}""")]
    [InlineData("""pas du json""")]
    public void InconsistentManifestIsIgnored(string manifest)
    {
        Publish(manifest.Replace("SHA", Sha));
        Assert.Null(Updates.Android(dir));
    }

    [Fact]
    public void UppercaseDigestIsRejected()
    {
        Publish($$"""{"versionCode":2108,"versionName":"1.0.0","sha256":"{{Sha.ToUpperInvariant()}}","size":10}""");
        Assert.Null(Updates.Android(dir));
    }
}
