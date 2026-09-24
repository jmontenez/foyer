import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/appearance.dart';

void main() {
  test('Les onze palettes gardent des contrastes lisibles', () {
    expect(palettes.length, 11);
    expect(palettes.map((p) => p.id).toSet().length, palettes.length);
    for (final palette in palettes) {
      final c = buildAppTheme(palette).colorScheme;
      for (final pair in [
        (c.primary, c.onPrimary),
        (c.secondaryContainer, c.onSecondaryContainer),
        (c.surface, c.onSurface),
      ]) {
        final a = pair.$1.computeLuminance(), b = pair.$2.computeLuminance();
        final contrast = ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
        expect(contrast, greaterThanOrEqualTo(4.5), reason: palette.id);
      }
    }
    expect(paletteById('ancienne-valeur').id, 'sage');
  });
}
