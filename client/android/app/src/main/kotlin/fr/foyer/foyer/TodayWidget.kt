package fr.foyer.foyer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Widget « Aujourd’hui » : affiche l’instantané écrit par l’application (lib/widgets.dart).
// Aucun appel réseau ici : s’il est ancien, on demande à Dart de le rafraîchir (foyer://refresh).
class TodayWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val raw = widgetData.getString("today", null)
        val today = raw?.let { runCatching { JSONObject(it) }.getOrNull() }
        val fetchedAt = widgetData.getString("fetchedAt", null)?.toLongOrNull() ?: 0L
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date())
        if (System.currentTimeMillis() - fetchedAt > STALE_MS || today?.optString("date") != date) requestRefresh(context)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, render(context, today))
    }

    // Au plus une demande toutes les 5 minutes : un échec (hors ligne, déconnecté) ne boucle pas.
    private fun requestRefresh(context: Context) {
        val prefs = context.getSharedPreferences("foyer_widgets", Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        if (now - prefs.getLong("refreshRequestedAt", 0L) < RETRY_MS) return
        prefs.edit().putLong("refreshRequestedAt", now).apply()
        runCatching { HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("foyer://refresh")).send() }
    }

    private fun open(context: Context, link: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(link))

    private fun render(context: Context, today: JSONObject?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today)
        views.setOnClickPendingIntent(R.id.widget_header, open(context, "foyer://today"))
        views.setOnClickPendingIntent(R.id.widget_add, open(context, "foyer://create"))
        ROWS.forEach { views.setViewVisibility(it.first, View.GONE) }
        views.setViewVisibility(R.id.widget_more, View.GONE)
        if (today == null) {
            views.setTextViewText(R.id.widget_title, "Foyer")
            views.setViewVisibility(R.id.widget_subtitle, View.GONE)
            views.setTextViewText(R.id.widget_empty, "Ouvrez Foyer pour afficher vos tâches du jour.")
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            return views
        }
        val count = today.optInt("count")
        val late = today.optInt("late")
        views.setTextViewText(R.id.widget_title, if (count == 0) "Aujourd’hui" else "Aujourd’hui · $count")
        views.setTextViewText(R.id.widget_subtitle, "dont $late en retard")
        views.setViewVisibility(R.id.widget_subtitle, if (late > 0) View.VISIBLE else View.GONE)
        val tasks = today.optJSONArray("tasks")
        val shown = minOf(tasks?.length() ?: 0, ROWS.size)
        for (i in 0 until shown) {
            val task = tasks!!.getJSONObject(i)
            val (row, title, meta) = ROWS[i]
            views.setViewVisibility(row, View.VISIBLE)
            views.setTextViewText(title, task.optString("title"))
            val label = task.optString("meta")
            views.setTextViewText(meta, label)
            views.setViewVisibility(meta, if (label.isEmpty()) View.GONE else View.VISIBLE)
            views.setTextColor(meta, context.getColor(if (task.optBoolean("late")) R.color.widget_late else R.color.widget_muted))
            views.setOnClickPendingIntent(row, open(context, "foyer://ticket/${Uri.encode(task.optString("id"))}"))
        }
        if (count > shown) {
            views.setTextViewText(R.id.widget_more, if (count - shown == 1) "+ 1 autre tâche" else "+ ${count - shown} autres tâches")
            views.setViewVisibility(R.id.widget_more, View.VISIBLE)
            views.setOnClickPendingIntent(R.id.widget_more, open(context, "foyer://today"))
        }
        views.setTextViewText(R.id.widget_empty, "Rien d’autre aujourd’hui 🎉")
        views.setViewVisibility(R.id.widget_empty, if (count == 0) View.VISIBLE else View.GONE)
        return views
    }

    private companion object {
        const val STALE_MS = 15 * 60_000L
        const val RETRY_MS = 5 * 60_000L
        val ROWS = listOf(
            Triple(R.id.row0, R.id.row0_title, R.id.row0_meta),
            Triple(R.id.row1, R.id.row1_title, R.id.row1_meta),
            Triple(R.id.row2, R.id.row2_title, R.id.row2_meta),
            Triple(R.id.row3, R.id.row3_title, R.id.row3_meta),
            Triple(R.id.row4, R.id.row4_title, R.id.row4_meta),
            Triple(R.id.row5, R.id.row5_title, R.id.row5_meta),
        )
    }
}
