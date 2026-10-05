import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/appearance.dart';

double contrast(Color x, Color y) {
  final a = x.computeLuminance(), b = y.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
}

void main() {
  test('Toutes les palettes gardent des contrastes lisibles', () {
    expect(palettes.where((p) => !p.bold).length, 11);
    expect(palettes.where((p) => p.bold).length, 9);
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

  test('Palette sur mesure : contrastes lisibles, duos difficiles compris', () {
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
    expect(
      (palette.name, palette.dark, palette.bold),
      ('Sur mesure', true, false),
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

  test('Thème : polices, angles et densité appliqués', () {
    final braise = buildAppTheme(stylePresets.first.appearance);
    final tokens = braise.extension<FoyerTokens>()!;
    expect(braise.brightness, Brightness.dark);
    expect(braise.textTheme.headlineLarge?.fontFamily, 'SpaceGrotesk');
    expect(braise.textTheme.bodyMedium?.fontFamily, 'DMSans');
    expect((tokens.radius, tokens.compact, tokens.rows), (20.0, false, false));
    final liste = buildAppTheme(
      stylePresets.last.appearance.copyWith(corners: 'sharp'),
    );
    final t = liste.extension<FoyerTokens>()!;
    expect((t.radius, t.compact, t.rows), (8.0, true, true));
    expect(liste.visualDensity, VisualDensity.compact);
    expect(
      buildAppTheme(const AppAppearance()).textTheme.headlineLarge?.fontFamily,
      isNot('SpaceGrotesk'),
    );
  });

  test('Styles prêts à l’emploi distincts et reconnus', () {
    expect(stylePresets.map((p) => p.appearance).toSet().length, 3);
    for (final p in stylePresets) {
      expect(presetOf(p.appearance), p);
      expect(palettes.any((x) => x.id == p.appearance.paletteId), isTrue);
    }
    expect(
      presetOf(stylePresets.first.appearance.copyWith(corners: 'sharp')),
      isNull,
    );
  });
}
