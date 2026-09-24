import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/main.dart';

void main() {
  testWidgets(
    'Création rapide accessible sans champs obligatoires supplémentaires',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TicketPage(
            data: {
              'members': [
                {'id': 'a', 'name': 'Camille'},
                {'id': 'b', 'name': 'Alex'},
              ],
              'stages': [
                {
                  'id': 'todo',
                  'name': 'À faire',
                  'category': 'todo',
                  'order': 0,
                },
              ],
              'tags': [],
            },
          ),
        ),
      );
      expect(find.text('Une nouvelle tâche'), findsOneWidget);
      expect(find.text('Enregistrer'), findsOneWidget);
      expect(find.text('Qui l’a réalisé ?'), findsNothing);
      await tester.tap(
        find.text('Ajouter des détails, une date, un responsable…'),
      );
      await tester.pumpAndSettle();
      expect(find.text('L’essentiel'), findsOneWidget);
    },
  );
}
