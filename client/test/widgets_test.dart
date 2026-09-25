import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/widgets.dart';

void main() {
  test('Liens des widgets : Aujourd’hui, création rapide, fiche', () {
    expect(WidgetLink.parse(Uri.parse('foyer://today')), isA<OpenToday>());
    expect(WidgetLink.parse(Uri.parse('foyer://create')), isA<QuickCreate>());
    final courses = WidgetLink.parse(Uri.parse('foyer://courses'));
    expect((courses as OpenCourses).add, isFalse);
    expect(
      (WidgetLink.parse(Uri.parse('foyer://courses?add=1')) as OpenCourses).add,
      isTrue,
    );
    final ticket = WidgetLink.parse(Uri.parse('foyer://ticket/abc123'));
    expect(ticket, isA<OpenTicket>());
    expect((ticket as OpenTicket).id, 'abc123');
    for (final other in [
      null,
      'https://foyer.jmops.fr/ticket/abc',
      'foyer://ticket',
      'foyer://ticket/a/b',
      'foyer://refresh',
      'foyer://inconnu',
    ]) {
      expect(WidgetLink.parse(other == null ? null : Uri.parse(other)), isNull);
    }
  });

  test(
    'Instantané : données du jour et heure de récupération, ou tout vide',
    () {
      final at = DateTime.fromMillisecondsSinceEpoch(1790000000000);
      final today = {
        'date': '2026-09-25',
        'count': 1,
        'late': 0,
        'tasks': [
          {'id': 't', 'title': 'Lessive', 'meta': 'Aujourd’hui', 'late': false},
        ],
      };
      final snapshot = widgetSnapshot({'today': today}, at);
      expect(jsonDecode(snapshot['today']!), today);
      expect(snapshot['fetchedAt'], '1790000000000');
      expect(snapshot['notice'], isNull);
      expect(widgetSnapshot(null, at), {
        'today': null,
        'shopping': null,
        'fetchedAt': null,
        'notice': null,
        'shoppingNotice': null,
      });
    },
  );

  test('Tâche touchée : marquée en cours d’envoi, les autres intactes', () {
    final today = jsonEncode({
      'date': '2026-09-25',
      'count': 2,
      'tasks': [
        {'id': 'a', 'title': 'Lessive'},
        {'id': 'b', 'title': 'Courses'},
      ],
    });
    final tasks = jsonDecode(markPending(today, 'b')!)['tasks'] as List;
    expect(tasks[0], {'id': 'a', 'title': 'Lessive'});
    expect(tasks[1], {'id': 'b', 'title': 'Courses', 'pending': true});
    expect(markPending(null, 'b'), isNull);
    final shopping = jsonEncode({
      'rows': [
        {'id': null, 'text': 'Crèmerie & œufs'},
        {'id': 'lait', 'text': 'Lait'},
      ],
    });
    final rows =
        jsonDecode(markPending(shopping, 'lait', list: 'rows')!)['rows']
            as List;
    expect(rows[0], {'id': null, 'text': 'Crèmerie & œufs'});
    expect(rows[1]['pending'], isTrue);
  });
}
