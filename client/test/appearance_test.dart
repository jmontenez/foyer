import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/appearance.dart';
import 'package:foyer/ui.dart';

double contrast(Color x, Color y) {
  final a = x.computeLuminance(), b = y.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  test('Toutes les palettes gardent des contrastes lisibles', () {
    expect(palettes.where((p) => !p.bold).length, 11);
    expect(palettes.where((p) => p.bold && !p.v2).length, 9);
    // Refonte « Découpes » : six duos littéraux (3 papiers clairs, 3 veillées).
    expect(palettes.where((p) => p.v2).length, 6);
    expect(palettes.where((p) => p.v2 && p.dark).length, 3);
    expect(palettes.where((p) => p.v2 && !p.bold).length, 0);
    expect(palettes.map((p) => p.id).toSet().length, palettes.length);
    for (final palette in palettes) {
      final theme = buildAppTheme(AppAppearance(paletteId: palette.id));
      final c = theme.colorScheme;
      for (final pair in [
        (c.primary, c.onPrimary),
        (c.secondaryContainer, c.onSecondaryContainer),
        (c.surface, c.onSurface),
        (theme.cardTheme.color!, c.onSurface),
        (theme.cardTheme.color!, c.onSurfaceVariant),
      ]) {
        expect(
          contrast(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason: palette.id,
        );
      }
    }
    expect(paletteById('ancienne-valeur').id, 'sage');
  });

  test('Palettes marquées : couleurs exactes et thème sombre effectif', () {
    for (final palette in palettes.where((p) => p.bold)) {
      final theme = buildAppTheme(AppAppearance(paletteId: palette.id));
      expect(theme.colorScheme.primary, palette.primary, reason: palette.id);
      expect(
        theme.colorScheme.secondaryContainer,
        palette.accent,
        reason: palette.id,
      );
      expect(
        theme.brightness,
        palette.dark ? Brightness.dark : Brightness.light,
        reason: palette.id,
      );
      expect(theme.scaffoldBackgroundColor, palette.background);
    }
    expect(paletteById('ember-night').dark, isTrue);
  });

  test('Texte lisible choisi automatiquement', () {
    expect(readableOn(const Color(0xFFFF7A1A)), Colors.black);
    expect(readableOn(const Color(0xFF1F4FE0)), Colors.white);
  });

  test('Palette sur mesure : couleurs exactes et contrastes lisibles', () {
    for (final (p, acc, dark) in [
      ('#FACC15', '#B8F02B', false), // jaune et citron vert sur fond clair
      ('#0A0A5E', '#FF3D5E', false),
      ('#FACC15', '#22D3EE', true),
      ('#7A1FA2', '#E87D32', true),
      ('#386653', '#B58A44', false),
    ]) {
      final appearance = AppAppearance(
        paletteId: customPaletteId,
        customPrimary: p,
        customAccent: acc,
        customDark: dark,
      );
      final theme = buildAppTheme(appearance);
      final c = theme.colorScheme;
      expect(
        theme.brightness,
        dark ? Brightness.dark : Brightness.light,
        reason: p,
      );
      // Ce qu’on règle au curseur est ce qu’on voit, en clair comme en sombre.
      expect(c.primary, colorFromHex(p), reason: p);
      expect(c.secondaryContainer, colorFromHex(acc), reason: acc);
      expect(theme.scaffoldBackgroundColor, paletteFor(appearance).background);
      for (final pair in [
        (c.primary, c.onPrimary),
        (c.secondaryContainer, c.onSecondaryContainer),
        (c.surface, c.onSurface),
        (theme.cardTheme.color!, c.onSurface),
        (theme.cardTheme.color!, c.onSurfaceVariant),
      ]) {
        expect(
          contrast(pair.$1, pair.$2),
          greaterThanOrEqualTo(4.5),
          reason: p,
        );
      }
    }
  });

  test('Hex : lecture stricte, écriture canonique', () {
    expect(hexOf(const Color(0xFF386653)), '#386653');
    expect(colorFromHex('#386653'), const Color(0xFF386653));
    expect(colorFromHex('#facc15'), const Color(0xFFFACC15));
    expect(colorFromHex('386653'), isNull);
    expect(colorFromHex('#38665'), isNull);
    expect(colorFromHex('#GG6653'), isNull);
    expect(colorFromHex(null), isNull);
  });

  test('Duo invalide ou absent ramené aux couleurs d’origine', () {
    final a = AppAppearance.fromMember({
      'paletteId': 'custom',
      'customPrimary': 'zz',
      'customAccent': '#ff0000',
      'customDark': true,
    });
    expect(a.paletteId, customPaletteId);
    expect((a.customPrimary, a.customAccent), ('#386653', '#FF0000'));
    expect(a.customDark, isTrue);
    final palette = paletteFor(a);
    // `bold` : les couleurs du duo sont appliquées telles quelles, jamais adoucies.
    expect(
      (palette.name, palette.dark, palette.bold),
      ('Sur mesure', true, true),
    );
    expect(paletteFor(const AppAppearance()).id, 'sage');
  });

  test('Jetons : valeurs inconnues ou absentes ramenées au réglage neutre', () {
    expect(AppAppearance.fromMember(null), const AppAppearance());
    final a = AppAppearance.fromMember({
      'paletteId': 'ember-night',
      'fontId': 'comic-sans',
      'listStyle': 'rows',
      'density': 'compact',
      'corners': 'sharp',
    });
    expect(a.paletteId, 'ember-night');
    expect(a.fontId, 'system');
    expect((a.listStyle, a.density, a.corners), ('rows', 'compact', 'sharp'));
    expect(a.toJson()['fontId'], 'system');
  });

  test('Thème : typo Découpes fixe, coin coupé, angles et densité', () {
    final theme = buildAppTheme(const AppAppearance());
    final tokens = theme.extension<FoyerTokens>()!;
    // Axes réduits : la police n'est plus un réglage — titres Manrope, texte Atkinson.
    expect(theme.textTheme.headlineLarge?.fontFamily, 'Manrope');
    expect(theme.textTheme.titleLarge?.fontFamily, 'Manrope');
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Atkinson');
    expect(
      (tokens.radius, tokens.cut, tokens.compact, tokens.rows),
      (20.0, 18.0, false, false),
    );
    expect(tokens.displayFont, 'Manrope');
    final compact = buildAppTheme(
      const AppAppearance(
        corners: 'sharp',
        density: 'compact',
        listStyle: 'rows',
      ),
    );
    final t = compact.extension<FoyerTokens>()!;
    expect((t.radius, t.cut, t.compact, t.rows), (8.0, 12.0, true, true));
    expect(compact.visualDensity, VisualDensity.compact);
    // Même typo quel que soit l'ancien réglage de police stocké.
    expect(
      buildAppTheme(const AppAppearance(fontId: 'serif'))
          .textTheme
          .headlineLarge
          ?.fontFamily,
      'Manrope',
    );
  });

  // Reproduit le bug du grand écran : la feuille fermée autrement que par « Annuler »
  // (barrière touchée en visant l’Enregistrer de la page) perdait les réglages,
  // et le second Enregistrer ne voyait plus de changement à envoyer.
  testWidgets('Sur mesure : réglage conservé à la fermeture, Annuler restaure', (
    tester,
  ) async {
    const saved = AppAppearance(
      paletteId: customPaletteId,
      customPrimary: '#1F4FE0',
      customAccent: '#FACC15',
    );
    selectedAppearance.value = saved;
    AppAppearance? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await Navigator.push(
                context,
                MaterialPageRoute<AppAppearance>(
                  builder: (_) => const AppearancePage(initial: saved),
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
    // Palette déjà « Sur mesure » : le sélecteur s’ouvre sur l’onglet des curseurs.
    await tester.tap(find.text('Couleurs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(selectedAppearance.value.customDark, isTrue);
    // Fermeture par la barrière (toucher hors de la feuille) : l’aperçu reste.
    await tester.tapAt(const Offset(400, 10));
    await tester.pumpAndSettle();
    expect(selectedAppearance.value.customDark, isTrue);
    // L’Enregistrer de la page envoie bien le réglage conservé.
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(result, saved.copyWith(customDark: true));
    // Même parcours avec « Annuler » : retour à l’apparence d’ouverture.
    selectedAppearance.value = saved;
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Couleurs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(selectedAppearance.value, saved);
  });

  testWidgets('Le sélecteur valide le duo via « Enregistrer mes couleurs »', (
    tester,
  ) async {
    const saved = AppAppearance(
      paletteId: customPaletteId,
      customPrimary: '#1F4FE0',
      customAccent: '#FACC15',
    );
    selectedAppearance.value = saved;
    AppAppearance? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await Navigator.push(
                context,
                MaterialPageRoute<AppAppearance>(
                  builder: (_) => const AppearancePage(initial: saved),
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
    await tester.tap(find.text('Couleurs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Enregistrer mes couleurs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(result, saved.copyWith(customDark: true));
  });

  testWidgets('CutCheck : coche au toucher, retour haptique, sémantique', (
    tester,
  ) async {
    var value = false;
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(const AppAppearance()),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CutCheck(
              value: value,
              semanticLabel: 'Tomates',
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Tomates'));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(haptics, isNotEmpty);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
}
