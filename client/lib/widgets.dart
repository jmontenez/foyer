import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import 'api.dart';

// Widgets Android : l’app écrit un instantané (GET /api/v1/widget) que le code natif affiche.
// Les actions des widgets s’exécutent ici, en Dart, dans un isolat d’arrière-plan.
const todayWidget = 'fr.foyer.foyer.TodayWidget';

bool get widgetsSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Destination d’un toucher sur un widget.
sealed class WidgetLink {
  const WidgetLink();

  /// `foyer://today`, `foyer://create`, `foyer://ticket/ID` ; null pour tout le reste.
  static WidgetLink? parse(Uri? uri) {
    if (uri == null || uri.scheme != 'foyer') return null;
    return switch (uri.host) {
      'today' => const OpenToday(),
      'create' => const QuickCreate(),
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

class OpenTicket extends WidgetLink {
  final String id;
  const OpenTicket(this.id);
}

/// Instantané enregistré pour les widgets : les données du serveur, telles quelles.
Map<String, String?> widgetSnapshot(Map<String, dynamic>? data, DateTime at) =>
    {
      'today': data == null ? null : jsonEncode(data['today']),
      'fetchedAt': data == null ? null : at.millisecondsSinceEpoch.toString(),
    };

Future<void> _save(Map<String, String?> snapshot) async {
  for (final entry in snapshot.entries) {
    await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
  }
  await HomeWidget.updateWidget(qualifiedAndroidName: todayWidget);
}

/// Récupère les données du jour et met les widgets à jour. Silencieux en cas d’échec
/// (hors ligne) ; une session expirée vide les widgets.
Future<void> refreshWidgets(Api api) async {
  if (!widgetsSupported) return;
  try {
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

/// Actions des widgets (isolat d’arrière-plan) : foyer://refresh pour l’instant.
@pragma('vm:entry-point')
Future<void> widgetCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = Api();
  await api.initialize();
  if (uri?.host == 'refresh') await refreshWidgets(api);
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
