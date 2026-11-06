package fr.foyer.foyer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import androidx.core.widget.RemoteViewsCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

// Widget « Agenda » : les prochains événements et tâches datées (instantané de lib/widgets.dart),
// groupés par jour. Lecture seule ; toucher ouvre l'élément (tâche → fiche, événement → calendrier).
class AgendaWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        if (widgetDataStale(widgetData)) requestWidgetRefresh(context)
        val agenda = widgetData.getString("agenda", null)?.let { runCatching { JSONArray(it) }.getOrNull() }
        val theme = WidgetTheme.of(context, widgetData)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, render(context, theme, id, agenda))
    }

    private fun open(context: Context, link: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(link))

    // Modèle commun aux lignes : chaque élément y ajoute son URI (fill-in), d'où FLAG_MUTABLE.
    private fun openTemplate(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
        val mutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getActivity(context, 12, intent, PendingIntent.FLAG_UPDATE_CURRENT or mutable)
    }

    private fun render(context: Context, theme: WidgetTheme, appWidgetId: Int, agenda: JSONArray?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_agenda)
        theme.background(views, R.id.widget_root)
        theme.tint(views, R.id.widget_add, theme.accent)
        theme.icon(views, R.id.widget_add, theme.onAccent)
        views.setTextColor(R.id.widget_title, theme.text)
        views.setTextColor(R.id.widget_empty, theme.muted)
        views.setTextViewText(R.id.widget_title, theme.title("Agenda"))
        views.setOnClickPendingIntent(R.id.widget_header, open(context, "foyer://calendar"))
        views.setOnClickPendingIntent(R.id.widget_add, open(context, "foyer://calendar"))
        views.setPendingIntentTemplate(R.id.widget_list, openTemplate(context))
        views.setEmptyView(R.id.widget_list, R.id.widget_empty)
        views.setTextViewText(R.id.widget_empty, "Rien de prévu. Touchez pour ouvrir le calendrier.")

        val items = RemoteViewsCompat.RemoteCollectionItems.Builder().setHasStableIds(true).setViewTypeCount(2)
        for (i in 0 until (agenda?.length() ?: 0)) {
            val row = agenda!!.getJSONObject(i)
            val id = if (row.isNull("id")) null else row.optString("id")
            val text = row.optString("text")
            if (id == null) {
                val header = RemoteViews(context.packageName, R.layout.widget_agenda_day)
                header.setTextViewText(R.id.day_text, text)
                header.setTextColor(R.id.day_text, theme.muted)
                items.addItem("day:$text:$i".hashCode().toLong(), header)
                continue
            }
            val isEvent = row.optBoolean("isEvent")
            val item = RemoteViews(context.packageName, R.layout.widget_agenda_item)
            item.setInt(R.id.item_bar, "setBackgroundColor", if (isEvent) theme.accent else theme.muted)
            item.setTextViewText(R.id.item_time, if (row.isNull("time")) "" else row.optString("time"))
            item.setTextColor(R.id.item_time, theme.accent)
            item.setTextViewText(R.id.item_text, text)
            item.setTextColor(R.id.item_text, theme.text)
            val link = if (isEvent) "foyer://calendar" else "foyer://ticket/${Uri.encode(id)}"
            item.setOnClickFillInIntent(R.id.item_root, Intent().setData(Uri.parse(link)))
            items.addItem(id.hashCode().toLong(), item)
        }
        RemoteViewsCompat.setRemoteAdapter(context, views, appWidgetId, R.id.widget_list, items.build())
        return views
    }
}
