using System.Text.Json;
using System.Text.RegularExpressions;
namespace Foyer;

public sealed record AndroidRelease(long VersionCode, string VersionName, string Sha256, long Size);

// Les releases GitHub sont privées et aucun jeton ne doit être intégré à l’APK : le serveur
// distribue lui-même la dernière version, aux seuls membres connectés. Le déploiement dépose
// l’APK signé et son manifeste (produit par la CI) dans un répertoire monté en lecture seule.
public static partial class Updates
{
    public const string Apk = "foyer-arm64.apk";
    public const string Manifest = "foyer-android.json";

    // Manifeste absent, illisible ou incohérent avec l’APK présent : aucune mise à jour proposée.
    // L’empreinte est vérifiée par l’application avant installation, Android vérifie la signature.
    public static AndroidRelease? Android(string directory)
    {
        var manifest = Path.Combine(directory, Manifest);
        var apk = new FileInfo(Path.Combine(directory, Apk));
        if (!File.Exists(manifest) || !apk.Exists) return null;
        AndroidRelease? release;
        try { release = JsonSerializer.Deserialize<AndroidRelease>(File.ReadAllText(manifest), new JsonSerializerOptions(JsonSerializerDefaults.Web)); }
        catch (JsonException) { return null; }
        if (release is null || release.VersionCode <= 0 || string.IsNullOrWhiteSpace(release.VersionName) || release.VersionName.Length > 64) return null;
        if (release.Sha256 is null || !Sha256Pattern().IsMatch(release.Sha256) || release.Size != apk.Length) return null;
        return release;
    }

    [GeneratedRegex("^[0-9a-f]{64}$")]
    private static partial Regex Sha256Pattern();
}
