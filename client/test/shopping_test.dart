import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/api.dart';
import 'package:foyer/shopping.dart';
import 'package:foyer/ui.dart';

class FakeApi extends Api {
  final Object Function(String method, String path, Object? body) respond;
  FakeApi(this.respond) {
    base = 'https://foyer.test';
  }
  @override
  Future<dynamic> call(String method, String path, [Object? body]) async {
    final value = respond(method, path, body);
    if (value is ApiError) throw value;
    return value;
  }
}

void main() {
  final catalog = [
    {'name': 'Lait', 'aisle': 'dairy', 'uses': 3},
    {'name': 'Œufs', 'aisle': 'dairy', 'uses': 1},
    {'name': 'Pommes de terre', 'aisle': 'produce', 'uses': 0},
    {'name': 'Pommes', 'aisle': 'produce', 'uses': 5},
    {'name': 'Tomates', 'aisle': 'produce', 'uses': 0},
    {'name': 'Crème fraîche', 'aisle': 'dairy', 'uses': 0},
    {'name': 'Papier toilette', 'aisle': 'hygiene', 'uses': 0},
  ];
  List<String> names(List<Map<String, dynamic>> l) => [
    for (final i in l) i['name'].toString(),
  ];

  test('Clé identique au serveur : casse, accents, ligatures, pluriel', () {
    expect(ingredientKey('Œufs'), 'oeuf');
    expect(ingredientKey('  Pommes de terre '), 'pomme de terre');
    expect(ingredientKey('Crème fraîche'), 'creme fraiche');
    expect(ingredientKey('Riz'), 'riz');
  });

  test('Recherche : exact, début, mot, contenu, faute de frappe', () {
    expect(names(searchIngredients(catalog, 'oeuf')), ['Œufs']);
    // « Pommes » (5 utilisations) avant « Pommes de terre ».
    expect(names(searchIngredients(catalog, 'pom')), [
      'Pommes',
      'Pommes de terre',
    ]);
    expect(names(searchIngredients(catalog, 'terre')), ['Pommes de terre']);
    expect(names(searchIngredients(catalog, 'CREME')), ['Crème fraîche']);
    expect(names(searchIngredients(catalog, 'toilete')), ['Papier toilette']);
    expect(names(searchIngredients(catalog, 'tomtes')), ['Tomates']);
    expect(searchIngredients(catalog, 'xyz'), isEmpty);
    expect(searchIngredients(catalog, '  '), isEmpty);
  });

  test('Accès rapide : les plus utilisés, puis l’ordre du catalogue', () {
    expect(names(quickIngredients(catalog, limit: 4)), [
      'Pommes',
      'Lait',
      'Œufs',
      'Pommes de terre',
    ]);
  });

  test('Articles groupés par rayon dans l’ordre du magasin, cochés à part', () {
    final aisles = [
      {'id': 'produce', 'name': 'Fruits & légumes'},
      {'id': 'dairy', 'name': 'Crèmerie & œufs'},
      {'id': 'other', 'name': 'Autre'},
    ];
    final (groups, basket) = groupByAisle([
      {'id': '1', 'text': 'Lait', 'aisle': 'dairy', 'done': false},
      {'id': '2', 'text': 'Pommes', 'aisle': 'produce', 'done': true},
      {'id': '3', 'text': 'Carottes', 'aisle': 'produce', 'done': false},
      {'id': '4', 'text': 'Vis', 'aisle': null, 'done': false},
    ], aisles);
    expect([for (final g in groups) g.$1['id']], ['produce', 'dairy', 'other']);
    expect([for (final i in basket) i['text']], ['Pommes']);
    expect(itemLabel({'text': 'Lait', 'qty': '2 L'}), 'Lait · 2 L');
    expect(itemLabel({'text': 'Pain', 'qty': null}), 'Pain');
  });

  test('Libellés de liste et dates d’API', () {
    final today = DateTime(2026, 9, 25);
    expect(listLabel({'id': 'draft'}, today), 'Non programmée');
    expect(listLabel({'id': 't', 'date': '2026-09-26'}, today), 'Demain');
    expect(apiDate(DateTime(2026, 3, 7)), '2026-03-07');
    expect(
      [ofDay('Aujourd’hui'), ofDay('Samedi'), ofDay('3 oct.')],
      ['d’aujourd’hui', 'de samedi', 'du 3 oct.'],
    );
    expect([dayPhrase('Demain'), dayPhrase('3 oct.')], ['demain', 'le 3 oct.']);
  });

  testWidgets(
    'Une suggestion déjà dans la liste le montre avant de la toucher',
    (tester) async {
      final data = {
        'today': '2026-09-25',
        'tickets': [],
        'members': [],
        'shopping': {
          'lists': [
            {
              'id': 'draft',
              'items': [
                {
                  'id': '1',
                  'text': 'Lait',
                  'qty': '2 L',
                  'aisle': 'dairy',
                  'done': false,
                },
              ],
            },
          ],
          'ingredients': catalog,
          'aisles': [
            {'id': 'dairy', 'name': 'Crèmerie & œufs'},
            {'id': 'produce', 'name': 'Fruits & légumes'},
            {'id': 'other', 'name': 'Autre'},
          ],
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShoppingView(
              data: data,
              api: Api(),
              onChanged: () async {},
              onOpenTicket: (_) {},
            ),
          ),
        ),
      );
      // Accès rapide : la puce du lait est sélectionnée et porte la quantité.
      final milk = tester.widget<CutChip>(
        find.widgetWithText(CutChip, 'Lait · 2 L'),
      );
      expect(milk.selected, isTrue);
      expect(
        tester.widget<CutChip>(find.widgetWithText(CutChip, 'Pommes')).selected,
        isFalse,
      );
      expect(find.text('CRÈMERIE & ŒUFS'), findsOneWidget);
      expect(find.text('Programmer'), findsOneWidget);
      // Recherche : l’état « Dans la liste » et l’ajout d’un nouvel ingrédient.
      await tester.enterText(find.byType(TextField), 'lai');
      await tester.pump();
      expect(find.text('Dans la liste · 2 L'), findsOneWidget);
      expect(find.text('Ajouter « lai »'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Lait');
      await tester.pump();
      expect(find.textContaining('Ajouter « '), findsNothing);
      // Toucher l’ingrédient ouvre sa feuille, en modification.
      await tester.tap(find.text('Dans la liste · 2 L'));
      await tester.pumpAndSettle();
      expect(find.text('Déjà dans la liste'), findsOneWidget);
      expect(find.text('Enregistrer'), findsOneWidget);
    },
  );

  testWidgets('L’éditeur d’ingrédient renvoie nom, quantité et rayon', (
    tester,
  ) async {
    IngredientChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => IngredientSheet(
                  api: Api(),
                  ingredient: const {
                    'name': 'Yaourts',
                    'aisle': 'dairy',
                    'lastQty': '4',
                  },
                  aisles: const [
                    {'id': 'dairy', 'name': 'Crèmerie & œufs'},
                    {'id': 'frozen', 'name': 'Surgelés'},
                  ],
                ),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Yaourts'),
      'Yaourts nature',
    );
    await tester.tap(find.text('Surgelés'));
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(result, (
      name: 'Yaourts nature',
      qty: '4',
      aisle: 'frozen',
      forget: false,
      photo: null,
      removePhoto: false,
    ));
  });

  testWidgets('Import : analyse, inconnus en premier, ajout groupé', (
    tester,
  ) async {
    const aisles = [
      {'id': 'sweet', 'name': 'Épicerie sucrée'},
      {'id': 'other', 'name': 'Autre'},
    ];
    Object? sent;
    final api = FakeApi((method, path, body) {
      if (path.endsWith('/shopping/import/preview')) {
        return [
          {
            'name': 'Farine',
            'qty': '500 g',
            'aisle': 'sweet',
            'known': true,
            'merge': false,
          },
          {
            'name': 'Levure',
            'qty': null,
            'aisle': 'other',
            'known': false,
            'merge': true,
          },
        ];
      }
      sent = body;
      return {'added': 1, 'merged': 1};
    });
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final opened = navigator.push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ImportPage(api: api, listId: 'draft', aisles: aisles),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '500 g de farine\nlevure');
    await tester.pump();
    await tester.tap(find.text('Analyser'));
    await tester.pumpAndSettle();
    // L’inconnu est en tête, à classer ; l’article déjà listé est signalé.
    expect(find.text('RAYON À PRÉCISER'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Levure')).dy,
      lessThan(tester.getTopLeft(find.text('Farine')).dy),
    );
    expect(find.text('Autre · déjà dans la liste'), findsOneWidget);
    expect(find.text('Épicerie sucrée · 500 g'), findsOneWidget);
    await tester.tap(find.text('Ajouter 2 articles'));
    await tester.pumpAndSettle();
    expect(sent, {
      'list': 'draft',
      'items': [
        {'name': 'Farine', 'qty': '500 g', 'aisle': 'sweet'},
        {'name': 'Levure', 'qty': null, 'aisle': 'other'},
      ],
    });
    expect(await opened, {'added': 1, 'merged': 1});
  });

  testWidgets(
    'Clavier ouvert : « Ajouter » reste visible et « retour » ferme le clavier',
    (tester) async {
      // Écran bas (téléphone plié à l’horizontale, grand clavier).
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 560);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<ItemChoice>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ItemSheet(
                    name: 'Lait',
                    aisle: 'dairy',
                    api: Api(),
                    aisles: const [
                      {'id': 'produce', 'name': 'Fruits & légumes'},
                      {'id': 'dairy', 'name': 'Crèmerie & œufs'},
                      {'id': 'bakery', 'name': 'Boulangerie'},
                      {'id': 'meat', 'name': 'Viande & poisson'},
                      {'id': 'savory', 'name': 'Épicerie salée'},
                      {'id': 'sweet', 'name': 'Épicerie sucrée'},
                      {'id': 'drinks', 'name': 'Boissons'},
                      {'id': 'frozen', 'name': 'Surgelés'},
                      {'id': 'hygiene', 'name': 'Hygiène'},
                      {'id': 'cleaning', 'name': 'Entretien'},
                      {'id': 'other', 'name': 'Autre'},
                    ],
                  ),
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final add = tester.getRect(find.text('Ajouter'));
      expect(add.bottom, lessThanOrEqualTo(1000 - 560));
      // Premier retour : la feuille reste (le clavier se ferme).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Ajouter'), findsOneWidget);
      // Clavier fermé : le retour ferme la feuille.
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Ajouter'), findsNothing);
    },
  );
}
