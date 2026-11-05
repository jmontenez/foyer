import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/api.dart';
import 'package:foyer/appearance.dart';
import 'package:foyer/calendar.dart';

void main() {
  // Semaine du jeudi 5 nov. 2026 (toujours dans sa propre semaine).
  final data = <String, dynamic>{
    'today': '2026-11-05',
    'members': [
      {'id': 'a', 'name': 'Camille'},
      {'id': 'b', 'name': 'Alex'},
    ],
    'tickets': [
      {
        'id': 't1',
        'title': 'RDV dentiste',
        'stageId': 'todo',
        'dueDate': '2026-11-05',
        'startMinute': 540, // 09h00
        'durationMinutes': 60,
      },
      {
        'id': 't2',
        'title': 'Courses',
        'stageId': 'todo',
        'dueDate': '2026-11-05',
        'startMinute': null,
        'durationMinutes': null,
      },
      {
        'id': 't3',
        'title': 'Tâche close',
        'stageId': 'done',
        'dueDate': '2026-11-05',
        'startMinute': 600,
        'durationMinutes': 30,
      },
    ],
    'events': [
      // Heures locales (sans offset) pour éviter la dérive de fuseau en CI.
      {
        'id': 'e1',
        'title': 'Anniv Léa',
        'allDay': true,
        'start': '2026-11-05T12:00:00',
        'end': '2026-11-05T12:00:00',
      },
      {
        'id': 'e2',
        'title': 'Visio',
        'allDay': false,
        'start': '2026-11-05T14:00:00',
        'end': '2026-11-05T15:00:00',
      },
    ],
  };

  Future<void> pump(
    WidgetTester tester, {
    void Function(Map<String, dynamic>)? onOpen,
  }) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const AppAppearance()),
        home: Scaffold(
          body: CalendarView(
            data: data,
            api: Api(),
            onOpenTicket: onOpen ?? (_) {},
            onChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Vue Semaine : blocs timés + bande all-day + toggle', (
    tester,
  ) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    // Blocs horaires : tâche timée + événement timé.
    expect(find.text('RDV dentiste'), findsOneWidget);
    expect(find.text('Visio'), findsOneWidget);
    // Bande « toute la journée » : tâche sans heure + anniversaire.
    expect(find.text('Courses'), findsOneWidget);
    expect(find.text('Anniv Léa'), findsOneWidget);
    // Les tâches closes ne polluent pas le calendrier.
    expect(find.text('Tâche close'), findsNothing);
    // Toggle : masque la bande all-day, garde les blocs timés.
    await tester.tap(find.byTooltip('Masquer les tâches sans heure'));
    await tester.pumpAndSettle();
    expect(find.text('Courses'), findsNothing);
    expect(find.text('Anniv Léa'), findsNothing);
    expect(find.text('RDV dentiste'), findsOneWidget);
  });

  testWidgets('Taper une tâche timée l’ouvre', (tester) async {
    Map<String, dynamic>? opened;
    await pump(tester, onOpen: (t) => opened = t);
    await tester.ensureVisible(find.text('RDV dentiste'));
    await tester.tap(find.text('RDV dentiste'));
    await tester.pump();
    expect(opened?['id'], 't1');
  });

  testWidgets('Le « + » ouvre l’éditeur de nouvel événement', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Nouvel événement'));
    await tester.pumpAndSettle();
    expect(find.text('Nouvel événement'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget);
  });

  testWidgets('Taper un événement ouvre son édition pré-remplie', (
    tester,
  ) async {
    await pump(tester);
    await tester.ensureVisible(find.text('Visio'));
    await tester.tap(find.text('Visio'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier l’événement'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Visio'), findsOneWidget);
  });

  // Robustesse : données du vrai serveur (minutes en double, clés manquantes,
  // stage nul, tâche hors semaine) ne doivent jamais donner une page grise.
  testWidgets('Données inattendues : pas de page grise', (tester) async {
    final messy = <String, dynamic>{
      'today': '2026-11-05',
      // ni 'members' ni 'events'
      'tickets': [
        {
          'id': 'x1',
          'title': 'Double minute',
          'stageId': 'todo',
          'dueDate': '2026-11-05',
          'startMinute': 540.0,
          'durationMinutes': 60.0,
        },
        {'id': 'x2', 'title': 'Sans stage', 'dueDate': '2026-11-05'},
        {
          'id': 'x3',
          'title': 'Hors semaine',
          'stageId': 'todo',
          'dueDate': '2027-01-01',
          'startMinute': 600,
          'durationMinutes': 30,
        },
      ],
    };
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const AppAppearance()),
        home: Scaffold(
          body: CalendarView(
            data: messy,
            api: Api(),
            onOpenTicket: (_) {},
            onChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Double minute'), findsOneWidget);
    expect(find.textContaining('indisponible'), findsNothing);
  });
}
