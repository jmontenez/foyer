package fr.foyer.foyer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

class UpdateFileProvider : FileProvider()

private class UpdateException(message: String) : Exception(message)

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("foyer_activity", "Activité du foyer", NotificationManager.IMPORTANCE_DEFAULT)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    // Mise à jour hors store : l’APK est téléchargé depuis le serveur Foyer avec la session,
    // vérifié (taille, SHA-256, paquet, version) puis confié à l’installateur Android, qui
    // contrôle la signature et demande toujours la confirmation de l’utilisateur.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fr.foyer/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(mapOf("versionCode" to installedVersion(), "versionName" to (packageInfo().versionName ?: ""), "canInstall" to canInstall()))
                "permission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                    result.success(null)
                }
                "install" -> {
                    val url = call.argument<String>("url")
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    val sha = call.argument<String>("sha256")
                    val size = call.argument<Number>("size")?.toLong()
                    val version = call.argument<Number>("versionCode")?.toLong()
                    if (url == null || !url.startsWith("https://") || sha == null || size == null || size <= 0 || version == null) {
                        result.error("invalid", "Mise à jour invalide.", null)
                    } else if (!canInstall()) {
                        result.success("permission")
                    } else {
                        val main = Handler(Looper.getMainLooper())
                        Thread {
                            try {
                                val file = download(url, headers, sha, size, version)
                                main.post {
                                    try {
                                        launchInstaller(file); result.success("started")
                                    } catch (e: Exception) {
                                        result.error("failed", "Impossible d’ouvrir l’installateur Android.", null)
                                    }
                                }
                            } catch (e: UpdateException) {
                                main.post { result.error("failed", e.message, null) }
                            } catch (e: Exception) {
                                main.post { result.error("failed", "Téléchargement interrompu. Réessayez.", null) }
                            }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun packageInfo(): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        else packageManager.getPackageInfo(packageName, 0)

    @Suppress("DEPRECATION")
    private fun versionOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()

    private fun installedVersion(): Long = versionOf(packageInfo())

    private fun canInstall(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    @Suppress("DEPRECATION")
    private fun download(url: String, headers: Map<String, String>, sha: String, size: Long, version: Long): File {
        val dir = File(cacheDir, "updates").apply { mkdirs(); listFiles()?.forEach { it.delete() } }
        val file = File(dir, "foyer-$version.apk")
        try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 20_000
            connection.readTimeout = 60_000
            connection.instanceFollowRedirects = false
            headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            val digest = MessageDigest.getInstance("SHA-256")
            var total = 0L
            try {
                if (connection.responseCode != 200) throw UpdateException("Mise à jour indisponible (${connection.responseCode}).")
                connection.inputStream.use { input ->
                    file.outputStream().use { output ->
                        val buffer = ByteArray(1 shl 16)
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            total += n
                            if (total > size) throw UpdateException("Fichier de mise à jour inattendu : installation annulée.")
                            digest.update(buffer, 0, n)
                            output.write(buffer, 0, n)
                        }
                    }
                }
            } finally {
                connection.disconnect()
            }
            val actual = digest.digest().joinToString("") { "%02x".format(it) }
            if (total != size || actual != sha) throw UpdateException("Empreinte de la mise à jour invalide : installation annulée.")
            val archive = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) packageManager.getPackageArchiveInfo(file.path, PackageManager.PackageInfoFlags.of(0))
                else packageManager.getPackageArchiveInfo(file.path, 0)) ?: throw UpdateException("Fichier de mise à jour illisible.")
            val archiveVersion = versionOf(archive)
            if (archive.packageName != packageName || archiveVersion != version || archiveVersion <= installedVersion()) throw UpdateException("Cette mise à jour ne correspond pas à Foyer.")
            return file
        } catch (e: Exception) {
            file.delete()
            throw e
        }
    }

    private fun launchInstaller(file: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
    }
}
