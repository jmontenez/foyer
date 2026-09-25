package fr.foyer.foyer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

private class UpdateException(message: String) : Exception(message)

// Un canal par type : chacun peut couper les commentaires et garder les rappels (Réglages Android).
// L’identifiant « foyer_activity » est conservé pour garder les réglages déjà faits.
object Channels {
    const val REMINDERS = "foyer_reminders"
    const val ACTIVITY = "foyer_activity"
    const val UPDATES = "foyer_updates"
    fun ensure(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        context.getSystemService(NotificationManager::class.java).createNotificationChannels(listOf(
            NotificationChannel(REMINDERS, "Rappels", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "Tâches du jour et résumé du matin" },
            NotificationChannel(ACTIVITY, "Activité du foyer", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "Commentaires et tâches confiées" },
            NotificationChannel(UPDATES, "Mises à jour", NotificationManager.IMPORTANCE_LOW).apply { description = "Nouvelles versions de Foyer" },
        ))
    }
}

// Résultat de la session d’installation : confirmation Android si nécessaire, sinon rien
// (en cas de succès l’application est remplacée et son processus arrêté).
class UpdateStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                    else @Suppress("DEPRECATION") intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                confirm?.let { context.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            }
            PackageInstaller.STATUS_SUCCESS -> Unit
            else -> Toast.makeText(context, "Mise à jour refusée par Android : ${intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "erreur inconnue"}", Toast.LENGTH_LONG).show()
        }
    }
}

// Après une mise à jour, Android ne relance pas l’application : une notification permet de la rouvrir.
class UpdatedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        // Première exécution après la mise à jour, avant tout lancement : le canal peut manquer.
        Channels.ensure(context)
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, Channels.UPDATES) else @Suppress("DEPRECATION") Notification.Builder(context)
        manager.notify(UPDATED_NOTIFICATION, builder.setSmallIcon(android.R.drawable.stat_sys_download_done).setContentTitle("Foyer est à jour")
            .setContentText("Touchez pour rouvrir l’application.").setContentIntent(open).setAutoCancel(true).build())
    }
    companion object { const val UPDATED_NOTIFICATION = 4242 }
}

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Channels.ensure(this)
    }

    // Mise à jour hors store : l’APK est téléchargé depuis le serveur Foyer avec la session,
    // vérifié (taille, SHA-256, paquet, version) puis installé par une session PackageInstaller.
    // Android vérifie la signature ; il demande confirmation sauf, à partir d’Android 12, quand
    // Foyer est déjà l’installateur de sa version actuelle (après une première mise à jour).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fr.foyer/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "info" -> result.success(mapOf("versionCode" to installedVersion(), "versionName" to (packageInfo().versionName ?: ""), "canInstall" to canInstall()))
                "notificationSettings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                    startActivity(intent)
                    result.success(null)
                }
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
                                try {
                                    install(file)
                                    main.post { result.success("started") }
                                } catch (e: Exception) {
                                    main.post { result.error("failed", "Impossible de lancer l’installation Android.", null) }
                                } finally {
                                    file.delete()
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

    private fun install(file: File) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(packageName)
            setSize(file.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            // Android 14 : les mises à jour venant d’une autre source redemanderont confirmation.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) setRequestUpdateOwnership(true)
        }
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            file.inputStream().use { input ->
                session.openWrite("foyer.apk", 0, file.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            session.commit(PendingIntent.getBroadcast(this, id, Intent(this, UpdateStatusReceiver::class.java), flags).intentSender)
        }
    }
}
