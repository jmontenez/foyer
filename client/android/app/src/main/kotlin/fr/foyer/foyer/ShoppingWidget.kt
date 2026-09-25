package fr.foyer.foyer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import androidx.core.widget.RemoteViewsCompat
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

// Widget « Courses » : la liste en cours par rayon (instantané de lib/widgets.dart). Toucher un
// article envoie foyer://check?list=…&item=… à Dart, qui le coche sur le serveur.
class ShoppingWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        if (widgetDataStale(widgetData)) requestWidgetRefresh(context)
        val shopping = widgetData.getString("shopping", null)?.let { runCatching { JSONObject(it) }.getOrNull() }
        val notice = widgetData.getString("shoppingNotice", null)?.takeIf { it.isNotEmpty() }
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, render(context, id, shopping, notice))
    }

    private fun open(context: Context, link: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(link))

    // Modèle commun aux lignes de la liste : chaque article y ajoute son URI (fill-in), d’où FLAG_MUTABLE.
    private fun checkTemplate(context: Context): PendingIntent {
        val intent = Intent(context, HomeWidgetBackgroundReceiver::class.java).setAction("es.antonborri.home_widget.action.BACKGROUND")
        val mutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getBroadcast(context, 7, intent, PendingIntent.FLAG_UPDATE_CURRENT or mutable)
    }

    private fun render(context: Context, appWidgetId: Int, shopping: JSONObject?, notice: String?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_shopping)
        views.setOnClickPendingIntent(R.id.widget_header, open(context, "foyer://courses"))
        views.setOnClickPendingIntent(R.id.widget_add, open(context, "foyer://courses?add=1"))
        views.setPendingIntentTemplate(R.id.widget_list, checkTemplate(context))
        views.setEmptyView(R.id.widget_list, R.id.widget_empty)
        val items = RemoteViewsCompat.RemoteCollectionItems.Builder().setHasStableIds(true).setViewTypeCount(2)
        if (shopping == null) {
            views.setTextViewText(R.id.widget_title, "Courses")
            views.setTextViewText(R.id.widget_subtitle, "")
            views.setTextViewText(R.id.widget_empty, "Ouvrez Foyer pour afficher la liste de courses.")
        } else {
            val list = shopping.optString("list")
            val left = shopping.optInt("left")
            val done = shopping.optInt("done")
            views.setTextViewText(R.id.widget_title, "Courses · ${shopping.optString("when")}")
            views.setTextViewText(R.id.widget_subtitle, notice ?: listOfNotNull(
                if (left == 0) null else if (left == 1) "1 article à acheter" else "$left articles à acheter",
                if (done == 0) null else "$done dans le panier",
            ).joinToString(" · "))
            views.setTextColor(R.id.widget_subtitle, context.getColor(if (notice != null) R.color.widget_late else R.color.widget_muted))
            views.setTextViewText(R.id.widget_empty, if (done > 0) "Tout est dans le panier 🎉" else "Liste vide. Touchez + pour ajouter un article.")
            val rows = shopping.optJSONArray("rows")
            for (i in 0 until (rows?.length() ?: 0)) {
                val row = rows!!.getJSONObject(i)
                val id = if (row.isNull("id")) null else row.optString("id")
                val text = row.optString("text")
                if (id == null) {
                    val aisle = RemoteViews(context.packageName, R.layout.widget_shopping_aisle)
                    aisle.setTextViewText(R.id.aisle_text, text)
                    items.addItem("aisle:$text".hashCode().toLong(), aisle)
                    continue
                }
                val pending = row.optBoolean("pending")
                val item = RemoteViews(context.packageName, R.layout.widget_shopping_item)
                item.setTextViewText(R.id.item_text, text)
                item.setTextViewText(R.id.item_qty, if (row.isNull("qty")) "" else row.optString("qty"))
                item.setImageViewResource(R.id.item_check, if (pending) R.drawable.widget_check_done else R.drawable.widget_check)
                if (!pending) item.setOnClickFillInIntent(R.id.item_root, Intent().setData(Uri.parse("foyer://check?list=${Uri.encode(list)}&item=${Uri.encode(id)}")))
                items.addItem(id.hashCode().toLong(), item)
            }
        }
        RemoteViewsCompat.setRemoteAdapter(context, views, appWidgetId, R.id.widget_list, items.build())
        return views
    }
}
