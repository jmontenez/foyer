import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'api.dart';
import 'appearance.dart';

// Widgets Android : l’app écrit un instantané (GET /api/v1/widget) que le code natif affiche.
// Les actions des widgets s’exécutent ici, en Dart, dans un isolat d’arrière-plan.
const todayWidget = 'fr.foyer.foyer.TodayWidget';
const shoppingWidget = 'fr.foyer.foyer.ShoppingWidget';

bool get widgetsSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Destination d’un toucher sur un widget.
sealed class WidgetLink {
  const WidgetLink();

  /// `foyer://today`, `foyer://create`, `foyer://ticket/ID`, `foyer://courses` (`?add=1` pour
  /// ajouter un article) ; null pour tout le reste.
  static WidgetLink? parse(Uri? uri) {
    if (uri == null || uri.scheme != 'foyer') return null;
    return switch (uri.host) {
      'today' => const OpenToday(),
      'create' => const QuickCreate(),
      'courses' => OpenCourses(add: uri.queryParameters['add'] == '1'),
      'ticket' when uri.pathSegments.length == 1 => OpenTicket(
        uri.pathSegments.single,
      ),
      _ => null,
    };
  }
}

class OpenToday extends WidgetLink {
  const OpenToday();
}

class QuickCreate extends WidgetLink {
  const QuickCreate();
}

class OpenCourses extends WidgetLink {
  final bool add;
  const OpenCourses({this.add = false});
}

class OpenTicket extends WidgetLink {
  final String id;
  const OpenTicket(this.id);
}

/// Instantané enregistré pour les widgets : les données du serveur, telles quelles.
/// Un rafraîchissement réussi efface aussi l’éventuel « Action non envoyée ».
Map<String, String?> widgetSnapshot(Map<String, dynamic>? data, DateTime at) =>
    {
      'today': data == null ? null : jsonEncode(data['today']),
      'shopping': data == null ? null : jsonEncode(data['shopping']),
      'fetchedAt': data == null ? null : at.millisecondsSinceEpoch.toString(),
      'notice': null,
      'shoppingNotice': null,
    };

/// Ligne touchée dans un widget (tâche de `tasks`, article de `rows`) : affichée « en cours
/// d’envoi » jusqu’au rafraîchissement.
String? markPending(String? snapshot, String id, {String list = 'tasks'}) {
  if (snapshot == null) return null;
  final data = Map<String, dynamic>.from(jsonDecode(snapshot) as Map);
  data[list] = [
    for (final t in (data[list] as List? ?? []))
      t is Map && t['id'] == id ? {...t, 'pending': true} : t,
  ];
  return jsonEncode(data);
}

Future<void> _updateAll() async {
  await HomeWidget.updateWidget(qualifiedAndroidName: todayWidget);
  await HomeWidget.updateWidget(qualifiedAndroidName: shoppingWidget);
}

Future<void> _save(Map<String, String?> snapshot) async {
  for (final entry in snapshot.entries) {
    await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
  }
  await _updateAll();
}

/// Charte de Foyer pour les widgets : couleurs de la palette choisie (ARGB) et angles.
Map<String, Object> widgetTheme(ThemeData t) {
  final c = t.colorScheme;
  int argb(Color x) => x.toARGB32();
  return {
    'bg': argb(t.scaffoldBackgroundColor),
    'card': argb(t.cardTheme.color ?? c.surface),
    'text': argb(c.onSurface),
    'muted': argb(c.onSurfaceVariant),
    'accent': argb(c.primary),
    'onAccent': argb(c.onPrimary),
    'late': argb(c.error),
    'sharp': (t.extension<FoyerTokens>()?.radius ?? 20) < 12,
  };
}

/// Récupère les données du jour et met les widgets à jour. Silencieux en cas d’échec
/// (hors ligne) ; une session expirée vide les widgets.
/// [theme] (application ouverte) : la charte est aussi mise à jour.
Future<void> refreshWidgets(Api api, {ThemeData? theme}) async {
  if (!widgetsSupported) return;
  try {
    if (theme != null) {
      await HomeWidget.saveWidgetData<String>(
        'theme',
        jsonEncode(widgetTheme(theme)),
      );
    }
    final data = Map<String, dynamic>.from(
      await api.call('GET', '/api/v1/widget'),
    );
    await _save(widgetSnapshot(data, DateTime.now()));
  } on ApiError catch (e) {
    if (e.status == 401) await clearWidgets();
  } catch (_) {}
}

/// Déconnexion : plus aucune tâche sur l’écran d’accueil.
Future<void> clearWidgets() async {
  if (!widgetsSupported) return;
  try {
    await _save(widgetSnapshot(null, DateTime.now()));
  } catch (_) {}
}

/// Actions des widgets (isolat d’arrière-plan) : `foyer://refresh`, `foyer://done?id=ID`.
@pragma('vm:entry-point')
Future<void> widgetCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = Api();
  await api.initialize();
  final id = uri?.queryParameters['id'];
  final list = uri?.queryParameters['list'],
      item = uri?.queryParameters['item'];
  switch (uri?.host) {
    case 'refresh':
      await refreshWidgets(api);
    case 'done' when id != null && id.isNotEmpty:
      await markDone(api, id);
    case 'check' when list != null && item != null:
      await markChecked(api, list, item);
  }
}

/// « C’est fait » depuis le widget : réalisée par moi. La ligne passe tout de suite en « envoi »,
/// puis le widget se rafraîchit ; en cas d’échec, « Action non envoyée » jusqu’au prochain succès.
Future<void> markDone(Api api, String id) async {
  final today = await HomeWidget.getWidgetData<String>('today');
  await HomeWidget.saveWidgetData<String>('today', markPending(today, id));
  await _updateAll();
  try {
    await api.call('POST', '/api/v1/tickets/${Uri.encodeComponent(id)}/done');
  } catch (e) {
    // Déjà close ailleurs (409) : le rafraîchissement suffit.
    if (e is! ApiError || e.status != 409) {
      // Hors ligne : la tâche réapparaît telle quelle, avec le message.
      await HomeWidget.saveWidgetData<String>('today', today);
      await refreshWidgets(api);
      await HomeWidget.saveWidgetData<String>('notice', 'Action non envoyée');
      await _updateAll();
      return;
    }
  }
  await refreshWidgets(api);
}

/// Article coché depuis le widget Courses : même principe que « C’est fait ».
Future<void> markChecked(Api api, String list, String item) async {
  final shopping = await HomeWidget.getWidgetData<String>('shopping');
  await HomeWidget.saveWidgetData<String>(
    'shopping',
    markPending(shopping, item, list: 'rows'),
  );
  await _updateAll();
  try {
    await api.call(
      'PATCH',
      '/api/v1/shopping/items/${Uri.encodeComponent(list)}/${Uri.encodeComponent(item)}',
      {'done': true, 'qty': null, 'aisle': null},
    );
  } catch (e) {
    // Article déjà retiré ou liste close (404) : le rafraîchissement suffit.
    if (e is! ApiError || e.status != 404) {
      await HomeWidget.saveWidgetData<String>('shopping', shopping);
      await refreshWidgets(api);
      await HomeWidget.saveWidgetData<String>(
        'shoppingNotice',
        'Article non coché',
      );
      await _updateAll();
      return;
    }
  }
  await refreshWidgets(api);
}

Future<void> registerWidgetActions() async {
  if (!widgetsSupported) return;
  try {
    await HomeWidget.registerInteractivityCallback(widgetCallback);
  } catch (_) {}
}

/// Lien du widget qui a lancé l’application, puis ceux reçus pendant qu’elle tourne.
Future<Uri?> initialWidgetUri() async {
  if (!widgetsSupported) return null;
  try {
    return await HomeWidget.initiallyLaunchedFromHomeWidget();
  } catch (_) {
    return null;
  }
}

Stream<Uri?> get widgetClicks =>
    widgetsSupported ? HomeWidget.widgetClicked : const Stream.empty();
