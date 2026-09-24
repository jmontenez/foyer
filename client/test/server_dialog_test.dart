import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/main.dart';

void main() {
  testWidgets(
    'Adresse vide ou invalide : formulaire conservé, puis annulation sans erreur',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => const ServerAddressDialog(initialValue: ''),
                ),
                child: const Text('Configurer'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Configurer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Saisissez l’adresse du serveur ou choisissez Annuler.'),
        findsOneWidget,
      );
      expect(find.byType(ServerAddressDialog), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        'http://invalid.example',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Saisissez une adresse HTTPS'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.byType(ServerAddressDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Adresse valide : résultat renvoyé et champ libéré après fermeture',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => const ServerAddressDialog(initialValue: ''),
                  );
                },
                child: const Text('Configurer'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Configurer'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'https://foyer.example',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(result, 'https://foyer.example');
      expect(find.byType(ServerAddressDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
