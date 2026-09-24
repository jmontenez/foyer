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
    expect(palettes.where((p) => p.bold).length, 8);
    expect(palettes.map((p) => p.id).toSet().length, palettes.length);
    for (final palette in palettes) {
      final theme = buildAppTheme(palette);
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
      final theme = buildAppTheme(palette);
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
}
