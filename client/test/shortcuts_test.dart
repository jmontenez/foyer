import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/appearance.dart';
import 'package:foyer/shortcuts.dart';

void main() {
  final today = DateTime(2026, 9, 25);

  test('Dernière fois, occurrence ouverte ou jamais fait', () {
    expect(shortcutLast({'lastDoneAt': null}, today), 'Jamais fait');
    expect(
      shortcutLast({'lastDoneAt': '2026-09-22T09:00:00Z'}, today),
      'Il y a 3 jours',
    );
    expect(
      shortcutLast({
        'lastDoneAt': '2026-09-22T09:00:00Z',
        'openTicketId': 'x',
      }, today),
      'À faire',
    );
  });

  test('Libellés d’échéance et d’attribution', () {
    expect(
      [dueLabel(null), dueLabel(0), dueLabel(1), dueLabel(7), dueLabel(3)],
      [
        'Sans date',
        'Aujourd’hui',
        'Demain',
        'Dans une semaine',
        'Dans 3 jours',
      ],
    );
    final members = [
      {'id': 'a', 'name': 'Camille'},
    ];
    expect(
      assignLabel({'assign': 'member', 'assigneeId': 'a'}, members),
      'Camille',
    );
    expect(assignLabel({'assign': 'rotation'}, members), 'À tour de rôle');
    expect(assignLabel({'assign': 'launcher'}, members), 'Qui le lance');
  });

  test('Les plus utilisés d’abord, puis l’ordre choisi', () {
    final sorted = byUse([
      {'id': 'a', 'uses': 1, 'order': 0},
      {'id': 'b', 'uses': 5, 'order': 1},
      {'id': 'c', 'uses': 1, 'order': 2},
    ]);
    expect(sorted.map((s) => s['id']), ['b', 'a', 'c']);
  });

  testWidgets('Puce : toucher lance, appui long préremplit', (tester) async {
    var taps = 0, longs = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const AppAppearance()),
        home: Scaffold(
          body: ShortcutChip(
            shortcut: const {
              'id': 'x',
              'title': 'Faire une lessive',
              'lastDoneAt': null,
            },
            today: today,
            onTap: () => taps++,
            onLongPress: () => longs++,
          ),
        ),
      ),
    );
    expect(find.text('Jamais fait'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Faire une lessive, Jamais fait'),
      findsOneWidget,
    );
    await tester.tap(find.text('Faire une lessive'));
    await tester.longPress(find.text('Faire une lessive'));
    expect((taps, longs), (1, 1));
  });
}
