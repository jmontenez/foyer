package fr.foyer.foyer

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import es.antonborri.home_widget.HomeWidgetBackgroundWorker
import io.flutter.FlutterInjector
import org.json.JSONObject

internal const val WIDGET_ACTION = "fr.foyer.foyer.WIDGET_ACTION"
private const val WIDGET_DATA = "HomeWidgetPreferences"

// Toucher sur un widget (rond « fait », article à cocher) : la ligne passe tout de suite en
// « envoi » ici, en natif, puis l’action part en Dart (lib/widgets.dart) via WorkManager.
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val uri = intent.data ?: return
        markPending(context, uri)
        updateWidgets(context)
        enqueueWidgetAction(context, uri, urgent = true)
    }

    private fun markPending(context: Context, uri: Uri) {
        val (key, list, id) = when (uri.host) {
            "done" -> Triple("today", "tasks", uri.getQueryParameter("id"))
            "check" -> Triple("shopping", "rows", uri.getQueryParameter("item"))
            else -> return
        }
        if (id == null) return
        val prefs = context.getSharedPreferences(WIDGET_DATA, Context.MODE_PRIVATE)
        val json = prefs.getString(key, null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return
        val rows = json.optJSONArray(list) ?: return
        for (i in 0 until rows.length()) {
            val row = rows.optJSONObject(i) ?: continue
            if (!row.isNull("id") && row.optString("id") == id) row.put("pending", true)
        }
        prefs.edit().putString(key, json.toString()).apply()
    }
}

// Redessine les deux widgets à partir de l’instantané.
internal fun updateWidgets(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    for (provider in listOf(TodayWidget::class.java, ShoppingWidget::class.java)) {
        val ids = manager.getAppWidgetIds(ComponentName(context, provider))
        if (ids.isEmpty()) continue
        context.sendBroadcast(Intent(context, provider).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE).putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids))
    }
}

// Exécute [uri] dans le callback Dart de home_widget. Notre propre file, en APPEND_OR_REPLACE :
// un échec passé (par exemple avant la première ouverture de l’app) ne bloque pas les suivantes,
// contrairement à la file APPEND du plugin. Les touchers sont accélérés (Android 12+).
internal fun enqueueWidgetAction(context: Context, uri: Uri, urgent: Boolean) {
    val loader = FlutterInjector.instance().flutterLoader()
    loader.startInitialization(context)
    loader.ensureInitializationComplete(context, null)
    val request = OneTimeWorkRequestBuilder<HomeWidgetBackgroundWorker>()
        .setInputData(Data.Builder().putString("uri_data", uri.toString()).build())
    if (urgent && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) request.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
    WorkManager.getInstance(context).enqueueUniqueWork("foyer_widget_actions", ExistingWorkPolicy.APPEND_OR_REPLACE, request.build())
}

// Intent de toucher, vers notre récepteur (non exporté).
internal fun widgetActionIntent(context: Context): Intent =
    Intent(context, WidgetActionReceiver::class.java).setAction(WIDGET_ACTION)
