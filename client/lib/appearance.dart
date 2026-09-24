import 'package:flutter/material.dart';

/// Add a palette here and its stable ID to the server's Appearance.PaletteIds.
class AppPalette {
  final String id, name;
  final Color primary, accent, background;

  /// Marquée : couleurs appliquées telles quelles, sans les tons adoucis de Material 3.
  final bool bold;
  final bool dark;
  const AppPalette(
    this.id,
    this.name,
    this.primary,
    this.accent,
    this.background, {
    this.bold = false,
    this.dark = false,
  });
}

const palettes = [
  AppPalette(
    'sky-orange',
    'Ciel & orange',
    Color(0xFF68BCE8),
    Color(0xFFE87D32),
    Color(0xFFF4F9FC),
  ),
  AppPalette(
    'sage',
    'Sauge & crème',
    Color(0xFF386653),
    Color(0xFFB58A44),
    Color(0xFFF7F5F0),
  ),
  AppPalette(
    'violet-navy',
    'Violet & bleu nuit',
    Color(0xFF9164C8),
    Color(0xFF233C78),
    Color(0xFFF7F5FC),
  ),
  AppPalette(
    'rose-plum',
    'Rose & prune',
    Color(0xFFDA93AF),
    Color(0xFF743F73),
    Color(0xFFFCF5F8),
  ),
  AppPalette(
    'navy-gold',
    'Marine & doré',
    Color(0xFF284C7C),
    Color(0xFFD8A638),
    Color(0xFFF5F7FA),
  ),
  AppPalette(
    'turquoise-coral',
    'Turquoise & corail',
    Color(0xFF39ABA9),
    Color(0xFFE77D70),
    Color(0xFFF2FAF9),
  ),
  AppPalette(
    'forest-mint',
    'Forêt & menthe',
    Color(0xFF31674C),
    Color(0xFF85CDB1),
    Color(0xFFF3F8F3),
  ),
  AppPalette(
    'terracotta-sand',
    'Terracotta & sable',
    Color(0xFFB96749),
    Color(0xFFD7B880),
    Color(0xFFFCF6F0),
  ),
  AppPalette(
    'cherry-cream',
    'Cerise & vanille',
    Color(0xFFB24E69),
    Color(0xFFD6B96E),
    Color(0xFFFCF6F3),
  ),
  AppPalette(
    'indigo-ice',
    'Indigo & glacier',
    Color(0xFF565DB0),
    Color(0xFF72B9D0),
    Color(0xFFF5F6FC),
  ),
  AppPalette(
    'slate-copper',
    'Ardoise & cuivre',
    Color(0xFF596C7F),
    Color(0xFFC2855F),
    Color(0xFFF5F7F8),
  ),
  AppPalette(
    'ember-night',
    'Braise & nuit',
    Color(0xFFFF7A1A),
    Color(0xFFFFC247),
    Color(0xFF0F0F11),
    bold: true,
    dark: true,
  ),
  AppPalette(
    'lime-charcoal',
    'Citron vert & charbon',
    Color(0xFFB8F02B),
    Color(0xFF22D3EE),
    Color(0xFF111412),
    bold: true,
    dark: true,
  ),
  AppPalette(
    'ruby-onyx',
    'Rubis & onyx',
    Color(0xFFFF3D5E),
    Color(0xFFFF9F1C),
    Color(0xFF120D0F),
    bold: true,
    dark: true,
  ),
  AppPalette(
    'electric-violet',
    'Violet électrique',
    Color(0xFFA459F5),
    Color(0xFFF472B6),
    Color(0xFF0E0B15),
    bold: true,
    dark: true,
  ),
  AppPalette(
    'abyss-cyan',
    'Abysses & cyan',
    Color(0xFF16B4F2),
    Color(0xFF2DD4BF),
    Color(0xFF08131B),
    bold: true,
    dark: true,
  ),
  AppPalette(
    'tomato-teal',
    'Tomate & canard',
    Color(0xFFE03A3E),
    Color(0xFF13807A),
    Color(0xFFFFF7F2),
    bold: true,
  ),
  AppPalette(
    'royal-sun',
    'Bleu roi & soleil',
    Color(0xFF1F4FE0),
    Color(0xFFFACC15),
    Color(0xFFF4F7FF),
    bold: true,
  ),
  AppPalette(
    'fuchsia-lemon',
    'Fuchsia & citron',
    Color(0xFFD6207C),
    Color(0xFFF9C80E),
    Color(0xFFFFF5FA),
    bold: true,
  ),
];

/// Onglets du sélecteur : palettes douces d’origine, puis palettes marquées.
const paletteTabs = [('Douces', false), ('Marquées', true)];

/// Texte noir ou blanc, le plus lisible sur [background] (contraste ≥ 4,5 garanti).
Color readableOn(Color background) {
  final l = background.computeLuminance();
  return (l + .05) / .05 >= 1.05 / (l + .05) ? Colors.black : Colors.white;
}

AppPalette paletteById(String? id) =>
    palettes.firstWhere((p) => p.id == id, orElse: () => palettes[1]);
final selectedPalette = ValueNotifier<String>('sage');

ThemeData buildAppTheme(AppPalette palette) {
  final brightness = palette.dark ? Brightness.dark : Brightness.light;
  final accent = ColorScheme.fromSeed(
    seedColor: palette.accent,
    brightness: brightness,
  );
  var colors =
      ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: brightness,
        surface: palette.background,
      ).copyWith(
        secondary: accent.primary,
        onSecondary: accent.onPrimary,
        secondaryContainer: accent.primaryContainer,
        onSecondaryContainer: accent.onPrimaryContainer,
      );
  if (palette.bold) {
    colors = colors.copyWith(
      primary: palette.primary,
      onPrimary: readableOn(palette.primary),
      secondaryContainer: palette.accent,
      onSecondaryContainer: readableOn(palette.accent),
    );
  }
  // Cartes et champs : blancs sur fond clair, légèrement éclaircis sur fond sombre.
  final card = palette.dark
      ? Color.alphaBlend(
          Colors.white.withValues(alpha: .07),
          palette.background,
        )
      : Colors.white;
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: palette.background,
    colorScheme: colors,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: colors.onSurface,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.outlineVariant),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.secondaryContainer,
      foregroundColor: colors.onSecondaryContainer,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
  );
}

class PalettePicker extends StatefulWidget {
  const PalettePicker({super.key});
  @override
  State<PalettePicker> createState() => _PalettePickerState();
}

class _PalettePickerState extends State<PalettePicker> {
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: paletteTabs.length,
    initialIndex: paletteById(selectedPalette.value).bold ? 1 : 0,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          children: [
            Text(
              'Vos couleurs',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Un aperçu immédiat, un choix rien que pour vous. Vos couleurs vous suivent sur vos appareils.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TabBar(
              tabs: [for (final (label, _) in paletteTabs) Tab(text: label)],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                children: [
                  for (final (_, bold) in paletteTabs)
                    ListView(
                      children: palettes
                          .where((p) => p.bold == bold)
                          .map(_tile)
                          .toList(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, selectedPalette.value),
                  child: const Text('Enregistrer mes couleurs'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _tile(AppPalette p) {
    final selected = selectedPalette.value == p.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          tileColor: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).cardTheme.color,
          leading: Container(
            width: 72,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: p.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _swatch(p.primary),
                const SizedBox(width: 6),
                _swatch(p.accent),
              ],
            ),
          ),
          title: Text(p.name),
          subtitle: p.dark ? const Text('Thème sombre') : null,
          trailing: selected ? const Icon(Icons.check_circle) : null,
          onTap: () => setState(() => selectedPalette.value = p.id),
        ),
      ),
    );
  }

  Widget _swatch(Color color) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
