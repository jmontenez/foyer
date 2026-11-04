import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/ui.dart';

void main() {
  testWidgets(
    'BinderSheets : les deux feuilles sont rendues ; taper le bout qui dépasse ramène le fond devant',
    (tester) async {
      var shown = '';
      Widget harness(bool detailFront) => MaterialApp(
        home: Scaffold(
          body: BinderSheets(
            list: const Text('LISTE'),
            detail: const Text('FICHE'),
            listColor: Colors.green,
            detailColor: Colors.blue,
            detailFront: detailFront,
            onShowList: () => shown = 'list',
            onShowDetail: () => shown = 'detail',
          ),
        ),
      );

      // Fiche devant : les deux contenus coexistent, la liste dépasse à gauche.
      await tester.pumpWidget(harness(true));
      expect(find.text('LISTE'), findsOneWidget);
      expect(find.text('FICHE'), findsOneWidget);

      // Un tap sur le bout gauche (liste qui dépasse) ramène la liste devant.
      final size = tester.getSize(find.byType(BinderSheets));
      await tester.tapAt(Offset(size.width * 0.1, size.height * 0.5));
      expect(shown, 'list');

      // Liste devant : la fiche dépasse à droite ; un tap sur ce bout la ramène.
      shown = '';
      await tester.pumpWidget(harness(false));
      await tester.tapAt(Offset(size.width * 0.9, size.height * 0.5));
      expect(shown, 'detail');
    },
  );
}
