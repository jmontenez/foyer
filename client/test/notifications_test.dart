import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/main.dart';

void main() {
  final notifications = [
    {
      'id': 'n1',
      'kind': 'comment',
      'title': 'Alex a commenté',
      'body': 'Peindre le portail — « On prend quelle couleur ? »',
      'count': 1,
      'ticketId': 't1',
      'createdAt': '2026-09-27T08:00:00+00:00',
      'unread': true,
    },
    {
      'id': 'n2',
      'kind': 'digest',
      'title': 'Aujourd’hui : 3 tâches',
      'body': null,
      'count': 1,
      'ticketId': null,
      'createdAt': '2026-09-26T06:00:00+00:00',
      'unread': false,
    },
  ];

  testWidgets('L’historique liste les notifications, non-lus en gras', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: NotificationsPage(notifications: notifications)),
    );
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Alex a commenté'), findsOneWidget);
    expect(find.text('Aujourd’hui : 3 tâches'), findsOneWidget);
    final unread = tester.widget<Text>(find.text('Alex a commenté'));
    expect(unread.style?.fontWeight, FontWeight.bold);
    final read = tester.widget<Text>(find.text('Aujourd’hui : 3 tâches'));
    expect(read.style?.fontWeight, isNull);
  });

  testWidgets('Toucher une notification liée renvoie l’id de sa tâche', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              opened = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) =>
                      NotificationsPage(notifications: notifications),
                ),
              );
            },
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex a commenté'));
    await tester.pumpAndSettle();
    expect(opened, 't1');
  });

  testWidgets('Sans historique, un message plutôt qu’une liste vide', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: NotificationsPage(notifications: [])),
    );
    expect(find.text('Aucune notification pour le moment.'), findsOneWidget);
  });
}
