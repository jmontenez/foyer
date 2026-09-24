import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/appearance.dart';
import 'package:foyer/ui.dart';

double contrast(Color x, Color y) {
  final a = x.computeLuminance(), b = y.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  final today = DateTime(2026, 9, 24); // jeudi

  test('Dates relatives en français', () {
    expect(relativeDay(today, today), 'Aujourd’hui');
    expect(relativeDay(DateTime(2026, 9, 25), today), 'Demain');
    expect(relativeDay(DateTime(2026, 9, 23), today), 'Hier');
    expect(relativeDay(DateTime(2026, 9, 26), today), 'Samedi');
    expect(relativeDay(DateTime(2026, 9, 21), today), 'Il y a 3 jours');
    expect(relativeDay(DateTime(2026, 10, 14), today), '14 oct.');
    expect(relativeDay(DateTime(2027, 1, 3), today), '3 janv. 2027');
    expect(relativeDay(DateTime(2026, 9, 24, 23, 59), today), 'Aujourd’hui');
    expect(headerDay(today), 'Jeudi 24 sept.');
  });

  test('Pluriels', () {
    expect(plural(1, 'commentaire'), '1 commentaire');
    expect(plural(2, 'commentaire'), '2 commentaires');
    expect(plural(0, 'étape'), '0 étape');
  });

  test(
    'Couleurs des membres distinctes et lisibles sur toutes les palettes',
    () {
      for (final p in palettes) {
        final c = buildAppTheme(AppAppearance(paletteId: p.id)).colorScheme;
        final (a, onA) = memberColors(c, 0);
        final (b, onB) = memberColors(c, 1);
        expect(contrast(a, onA), greaterThanOrEqualTo(4.5), reason: p.id);
        expect(contrast(b, onB), greaterThanOrEqualTo(4.5), reason: p.id);
        final hueGap = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue)
            .abs();
        expect(hueGap, greaterThan(90), reason: p.id);
      }
    },
  );

  Future<void> pump(WidgetTester tester, AppAppearance a) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(a),
      home: Scaffold(
        body: TaskTile(
          onTap: () {},
          task: const TaskView(
            title: 'Réparer la fuite',
            meta: 'Aujourd’hui · En cours',
            badge: TaskBadge.urgent,
            done: 2,
            total: 3,
            comments: 1,
            people: [('Camille', 0)],
          ),
        ),
      ),
    ),
  );

  testWidgets('Tâche en carte : badge, progression, commentaire au singulier', (
    tester,
  ) async {
    await pump(tester, stylePresets.first.appearance);
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('URGENT'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('2/3 · 1 commentaire'), findsOneWidget);
  });

  testWidgets('Tâche en ligne selon le jeton d’affichage', (tester) async {
    await pump(tester, stylePresets.last.appearance);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.text('Aujourd’hui · En cours · 2/3 · 1 commentaire'),
      findsOneWidget,
    );
  });
}
