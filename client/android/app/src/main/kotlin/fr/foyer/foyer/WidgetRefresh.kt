package fr.foyer.foyer

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Rafraîchissement commun aux widgets : l’instantané est ancien (plus de 15 min) ou d’un autre jour.
private const val STALE_MS = 15 * 60_000L
private const val RETRY_MS = 5 * 60_000L

internal fun widgetDataStale(data: SharedPreferences): Boolean {
    val fetchedAt = data.getString("fetchedAt", null)?.toLongOrNull() ?: 0L
    val date = data.getString("today", null)?.let { runCatching { JSONObject(it).optString("date") }.getOrNull() }
    return System.currentTimeMillis() - fetchedAt > STALE_MS || date != SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date())
}

// Demande à Dart (foyer://refresh) de relire le serveur ; au plus une fois toutes les 5 minutes,
// pour qu’un échec (hors ligne, déconnecté) ne boucle pas.
internal fun requestWidgetRefresh(context: Context) {
    val prefs = context.getSharedPreferences("foyer_widgets", Context.MODE_PRIVATE)
    val now = System.currentTimeMillis()
    if (now - prefs.getLong("refreshRequestedAt", 0L) < RETRY_MS) return
    prefs.edit().putLong("refreshRequestedAt", now).apply()
    runCatching { enqueueWidgetAction(context, Uri.parse("foyer://refresh"), urgent = false) }
}
