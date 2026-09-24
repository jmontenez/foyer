import 'package:flutter/material.dart';

/// Add a palette here and its stable ID to the server's Appearance.PaletteIds.
class AppPalette {
  final String id, name;
  final Color primary, accent, background;
  const AppPalette(
    this.id,
    this.name,
    this.primary,
    this.accent,
    this.background,
  );
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
];

AppPalette paletteById(String? id) =>
    palettes.firstWhere((p) => p.id == id, orElse: () => palettes[1]);
final selectedPalette = ValueNotifier<String>('sage');

ThemeData buildAppTheme(AppPalette palette) {
  final accent = ColorScheme.fromSeed(seedColor: palette.accent);
  final colors =
      ColorScheme.fromSeed(
        seedColor: palette.primary,
        surface: palette.background,
      ).copyWith(
        secondary: accent.primary,
        onSecondary: accent.onPrimary,
        secondaryContainer: accent.primaryContainer,
        onSecondaryContainer: accent.onPrimaryContainer,
      );
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
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
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
  Widget build(BuildContext context) => SafeArea(
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
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: palettes
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Semantics(
                        selected: selectedPalette.value == p.id,
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          tileColor: selectedPalette.value == p.id
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Colors.white,
                          leading: SizedBox(
                            width: 64,
                            child: Row(
                              children: [
                                _swatch(p.primary),
                                const SizedBox(width: 6),
                                _swatch(p.accent),
                              ],
                            ),
                          ),
                          title: Text(p.name),
                          trailing: selectedPalette.value == p.id
                              ? const Icon(Icons.check_circle)
                              : null,
                          onTap: () =>
                              setState(() => selectedPalette.value = p.id),
                        ),
                      ),
                    ),
                  )
                  .toList(),
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
                onPressed: () => Navigator.pop(context, selectedPalette.value),
                child: const Text('Enregistrer mes couleurs'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget _swatch(Color color) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
