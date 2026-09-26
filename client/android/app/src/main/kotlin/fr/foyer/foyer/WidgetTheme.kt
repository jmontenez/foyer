package fr.foyer.foyer

import android.content.Context
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.os.Build
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.widget.RemoteViews
import org.json.JSONObject

// Charte de Foyer : la palette et les angles choisis dans l’application (Apparence), exportés
// par lib/widgets.dart. Sans export (première installation), les couleurs de repli des ressources.
internal data class WidgetTheme(
    val bg: Int, val card: Int, val text: Int, val muted: Int,
    val accent: Int, val onAccent: Int, val late: Int, val sharp: Boolean,
) {
    // Fonds arrondis teintés à la couleur de la palette (Android 12+ ; sinon couleurs de repli).
    fun tint(views: RemoteViews, viewId: Int, color: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) views.setColorStateList(viewId, "setBackgroundTintList", ColorStateList.valueOf(color))
    }

    fun background(views: RemoteViews, viewId: Int) {
        views.setInt(viewId, "setBackgroundResource", if (sharp) R.drawable.widget_background_sharp else R.drawable.widget_background)
        tint(views, viewId, bg)
    }

    fun row(views: RemoteViews, viewId: Int) {
        views.setInt(viewId, "setBackgroundResource", if (sharp) R.drawable.widget_row_background_sharp else R.drawable.widget_row_background)
        tint(views, viewId, card)
    }

    fun icon(views: RemoteViews, viewId: Int, color: Int) = views.setInt(viewId, "setColorFilter", color)

    // « Courses. » : le point final dans la couleur d’accent, comme les titres de l’application.
    fun title(text: String): CharSequence = SpannableString("$text.").apply {
        setSpan(ForegroundColorSpan(accent), text.length, text.length + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    }

    companion object {
        fun of(context: Context, data: SharedPreferences): WidgetTheme {
            val json = data.getString("theme", null)?.let { runCatching { JSONObject(it) }.getOrNull() }
            fun color(key: String, fallback: Int) = if (json?.has(key) == true) json.optLong(key).toInt() else context.getColor(fallback)
            return WidgetTheme(
                bg = color("bg", R.color.widget_bg), card = color("card", R.color.widget_row),
                text = color("text", R.color.widget_text), muted = color("muted", R.color.widget_muted),
                accent = color("accent", R.color.widget_accent), onAccent = color("onAccent", R.color.widget_on_accent),
                late = color("late", R.color.widget_late), sharp = json?.optBoolean("sharp") == true,
            )
        }
    }
}

