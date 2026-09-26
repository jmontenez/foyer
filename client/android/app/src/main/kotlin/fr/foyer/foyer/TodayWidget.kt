package fr.foyer.foyer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

// Widget « Aujourd’hui » : affiche l’instantané écrit par l’application (lib/widgets.dart).
// Aucun appel réseau ici : s’il est ancien, on demande à Dart de le rafraîchir (WidgetRefresh.kt).
private data class Row(val row: Int, val check: Int, val text: Int, val title: Int, val meta: Int)

class TodayWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val today = widgetData.getString("today", null)?.let { runCatching { JSONObject(it) }.getOrNull() }
        if (widgetDataStale(widgetData)) requestWidgetRefresh(context)
        val notice = widgetData.getString("notice", null)?.takeIf { it.isNotEmpty() }
        val theme = WidgetTheme.of(context, widgetData)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, render(context, theme, today, notice))
    }

    private fun open(context: Context, link: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(link))

    // Rond « fait » : un PendingIntent distinct par tâche (l’URI fait la différence).
    private fun done(context: Context, id: String) = PendingIntent.getBroadcast(
        context, 0, widgetActionIntent(context).setData(Uri.parse("foyer://done?id=$id")),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun render(context: Context, theme: WidgetTheme, today: JSONObject?, notice: String?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today)
        theme.background(views, R.id.widget_root)
        theme.tint(views, R.id.widget_add, theme.accent)
        theme.icon(views, R.id.widget_add, theme.onAccent)
        views.setTextColor(R.id.widget_title, theme.text)
        views.setTextColor(R.id.widget_more, theme.accent)
        views.setTextColor(R.id.widget_empty, theme.muted)
        views.setTextViewText(R.id.widget_title, theme.title("Aujourd’hui"))
        views.setOnClickPendingIntent(R.id.widget_header, open(context, "foyer://today"))
        views.setOnClickPendingIntent(R.id.widget_add, open(context, "foyer://create"))
        ROWS.forEach { views.setViewVisibility(it.row, View.GONE) }
        views.setViewVisibility(R.id.widget_more, View.GONE)
        if (today == null) {
            views.setViewVisibility(R.id.widget_subtitle, View.GONE)
            views.setTextViewText(R.id.widget_empty, "Ouvrez Foyer pour afficher vos tâches du jour.")
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            return views
        }
        val count = today.optInt("count")
        val late = today.optInt("late")
        // Sous-titre : « Action non envoyée » prime ; sinon le nombre de tâches et de retards.
        val summary = listOfNotNull(
            if (count == 0) null else if (count == 1) "1 tâche" else "$count tâches",
            if (late == 0) null else "dont $late en retard",
        ).joinToString(" · ")
        views.setTextViewText(R.id.widget_subtitle, notice ?: summary)
        views.setTextColor(R.id.widget_subtitle, if (notice != null || late > 0) theme.late else theme.muted)
        views.setViewVisibility(R.id.widget_subtitle, if ((notice ?: summary).isEmpty()) View.GONE else View.VISIBLE)
        val tasks = today.optJSONArray("tasks")
        val shown = minOf(tasks?.length() ?: 0, ROWS.size)
        for (i in 0 until shown) {
            val task = tasks!!.getJSONObject(i)
            val row = ROWS[i]
            val id = Uri.encode(task.optString("id"))
            val pending = task.optBoolean("pending")
            views.setViewVisibility(row.row, View.VISIBLE)
            theme.row(views, row.row)
            views.setTextViewText(row.title, task.optString("title"))
            views.setTextColor(row.title, if (pending) theme.muted else theme.text)
            val label = if (pending) "Envoi…" else task.optString("meta")
            views.setTextViewText(row.meta, label)
            views.setViewVisibility(row.meta, if (label.isEmpty()) View.GONE else View.VISIBLE)
            views.setTextColor(row.meta, if (task.optBoolean("late") && !pending) theme.late else theme.muted)
            views.setImageViewResource(row.check, if (pending) R.drawable.widget_check_done else R.drawable.widget_check)
            theme.icon(views, row.check, if (pending) theme.accent else theme.muted)
            views.setOnClickPendingIntent(row.text, open(context, "foyer://ticket/$id"))
            if (!pending) views.setOnClickPendingIntent(row.check, done(context, id))
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
        val ROWS = listOf(
            Row(R.id.row0, R.id.row0_check, R.id.row0_text, R.id.row0_title, R.id.row0_meta),
            Row(R.id.row1, R.id.row1_check, R.id.row1_text, R.id.row1_title, R.id.row1_meta),
            Row(R.id.row2, R.id.row2_check, R.id.row2_text, R.id.row2_title, R.id.row2_meta),
            Row(R.id.row3, R.id.row3_check, R.id.row3_text, R.id.row3_title, R.id.row3_meta),
            Row(R.id.row4, R.id.row4_check, R.id.row4_text, R.id.row4_title, R.id.row4_meta),
            Row(R.id.row5, R.id.row5_check, R.id.row5_text, R.id.row5_title, R.id.row5_meta),
        )
    }
}
