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
    'ink-coral',
    'Encre & corail',
    Color(0xFF2B59C3),
    Color(0xFFC0512F),
    Color(0xFFFBFAF7),
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

/// Couple de polices embarquées : titres ([display]) et texte courant ([body]).
/// Null = police du système. Ajouter l’identifiant à Appearance.FontIds côté serveur.
class FontPair {
  final String id, name;
  final String? display, body;
  const FontPair(this.id, this.name, this.display, this.body);
}

const fontPairs = [
  FontPair('system', 'Système', null, null),
  FontPair('grotesk', 'Grotesk', 'SpaceGrotesk', 'DMSans'),
  FontPair('serif', 'Fraunces', 'Fraunces', 'Atkinson'),
  FontPair('manrope', 'Manrope', 'Manrope', 'Manrope'),
];

FontPair fontById(String? id) =>
    fontPairs.firstWhere((f) => f.id == id, orElse: () => fontPairs.first);

/// Jetons de design choisis par un membre ; tous les écrans les lisent via le thème.
@immutable
class AppAppearance {
  final String paletteId, fontId, listStyle, density, corners;
  const AppAppearance({
    this.paletteId = 'sage',
    this.fontId = 'system',
    this.listStyle = 'cards',
    this.density = 'comfortable',
    this.corners = 'soft',
  });

  /// Valeurs inconnues ou absentes (anciennes données) : réglage neutre.
  factory AppAppearance.fromMember(Map<dynamic, dynamic>? m) => AppAppearance(
    paletteId: paletteById(m?['paletteId']?.toString()).id,
    fontId: fontById(m?['fontId']?.toString()).id,
    listStyle: m?['listStyle'] == 'rows' ? 'rows' : 'cards',
    density: m?['density'] == 'compact' ? 'compact' : 'comfortable',
    corners: m?['corners'] == 'sharp' ? 'sharp' : 'soft',
  );

  AppAppearance copyWith({
    String? paletteId,
    String? fontId,
    String? listStyle,
    String? density,
    String? corners,
  }) => AppAppearance(
    paletteId: paletteId ?? this.paletteId,
    fontId: fontId ?? this.fontId,
    listStyle: listStyle ?? this.listStyle,
    density: density ?? this.density,
    corners: corners ?? this.corners,
  );

  Map<String, String> toJson() => {
    'paletteId': paletteId,
    'fontId': fontId,
    'listStyle': listStyle,
    'density': density,
    'corners': corners,
  };

  @override
  bool operator ==(Object other) =>
      other is AppAppearance &&
      other.paletteId == paletteId &&
      other.fontId == fontId &&
      other.listStyle == listStyle &&
      other.density == density &&
      other.corners == corners;

  @override
  int get hashCode =>
      Object.hash(paletteId, fontId, listStyle, density, corners);
}

/// Styles prêts à l’emploi : un choix règle tous les jetons, affinables ensuite.
class StylePreset {
  final String id, name, description;
  final AppAppearance appearance;
  const StylePreset(this.id, this.name, this.description, this.appearance);
}

const stylePresets = [
  StylePreset(
    'braise',
    'Braise',
    'Sombre · cartes',
    AppAppearance(paletteId: 'ember-night', fontId: 'grotesk'),
  ),
  StylePreset(
    'sauge',
    'Sauge',
    'Clair · cartes',
    AppAppearance(paletteId: 'sage', fontId: 'serif'),
  ),
  StylePreset(
    'liste',
    'Liste',
    'Clair · lignes',
    AppAppearance(
      paletteId: 'ink-coral',
      fontId: 'manrope',
      listStyle: 'rows',
      density: 'compact',
    ),
  ),
];

StylePreset? presetOf(AppAppearance a) =>
    stylePresets.where((p) => p.appearance == a).firstOrNull;

final selectedAppearance = ValueNotifier<AppAppearance>(const AppAppearance());

/// Jetons non couverts par ThemeData, lus par les composants de Foyer.
@immutable
class FoyerTokens extends ThemeExtension<FoyerTokens> {
  final double radius;
  final bool compact;
  final bool rows;
  final String? displayFont;
  const FoyerTokens({
    required this.radius,
    required this.compact,
    required this.rows,
    this.displayFont,
  });

  @override
  FoyerTokens copyWith({
    double? radius,
    bool? compact,
    bool? rows,
    String? displayFont,
  }) => FoyerTokens(
    radius: radius ?? this.radius,
    compact: compact ?? this.compact,
    rows: rows ?? this.rows,
    displayFont: displayFont ?? this.displayFont,
  );

  @override
  FoyerTokens lerp(covariant FoyerTokens? other, double t) =>
      other == null || t < .5 ? this : other;
}

ThemeData buildAppTheme(AppAppearance appearance) {
  final palette = paletteById(appearance.paletteId);
  final font = fontById(appearance.fontId);
  final sharp = appearance.corners == 'sharp';
  final radius = sharp ? 8.0 : 20.0;
  final fieldRadius = sharp ? 6.0 : 14.0;
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
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: font.body,
    visualDensity: appearance.density == 'compact'
        ? VisualDensity.compact
        : VisualDensity.standard,
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
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(fieldRadius),
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
        shape: sharp
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
            : const StadiumBorder(),
      ),
    ),
  );
  // Titres dans la police d’affichage ; le texte courant garde la police de lecture.
  final display = font.display;
  final text = base.textTheme;
  return base.copyWith(
    textTheme: display == null
        ? text
        : text.copyWith(
            displayLarge: text.displayLarge?.copyWith(fontFamily: display),
            displayMedium: text.displayMedium?.copyWith(fontFamily: display),
            displaySmall: text.displaySmall?.copyWith(fontFamily: display),
            headlineLarge: text.headlineLarge?.copyWith(fontFamily: display),
            headlineMedium: text.headlineMedium?.copyWith(fontFamily: display),
            headlineSmall: text.headlineSmall?.copyWith(fontFamily: display),
            titleLarge: text.titleLarge?.copyWith(fontFamily: display),
          ),
    extensions: [
      FoyerTokens(
        radius: radius,
        compact: appearance.density == 'compact',
        rows: appearance.listStyle == 'rows',
        displayFont: display,
      ),
    ],
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
    initialIndex: paletteById(selectedAppearance.value.paletteId).bold ? 1 : 0,
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
                  onPressed: () => Navigator.pop(
                    context,
                    selectedAppearance.value.paletteId,
                  ),
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
    final selected = selectedAppearance.value.paletteId == p.id;
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
          onTap: () => setState(
            () => selectedAppearance.value = selectedAppearance.value.copyWith(
              paletteId: p.id,
            ),
          ),
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

/// Écran Apparence : styles prêts à l’emploi puis réglages fins, prévisualisés en direct.
/// Renvoie l’apparence à enregistrer, ou null si l’utilisateur annule.
class AppearancePage extends StatefulWidget {
  final AppAppearance initial;
  const AppearancePage({super.key, required this.initial});
  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  late AppAppearance current = widget.initial;

  void choose(AppAppearance value) {
    setState(() => current = value);
    selectedAppearance.value = value;
  }

  Future<void> choosePalette() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: const PalettePicker(),
      ),
    );
    choose(id == null ? current : current.copyWith(paletteId: id));
  }

  Widget heading(String label) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: .8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget segmented(
    String label,
    List<(String, String, String?)> options,
    String value,
    AppAppearance Function(String) apply,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            for (final (id, name, family) in options)
              ButtonSegment(
                value: id,
                label: Text(name, style: TextStyle(fontFamily: family)),
              ),
          ],
          selected: {value},
          onSelectionChanged: (v) => choose(apply(v.first)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Annuler',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Apparence'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: () => Navigator.pop(context, current),
              child: const Text('Enregistrer'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          heading('Style'),
          Row(
            children: [
              for (final preset in stylePresets) ...[
                if (preset != stylePresets.first) const SizedBox(width: 10),
                Expanded(child: presetCard(preset, colors)),
              ],
            ],
          ),
          heading('Réglages fins'),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Couleurs'),
              subtitle: Text(paletteById(current.paletteId).name),
              trailing: const Icon(Icons.chevron_right),
              onTap: choosePalette,
            ),
          ),
          const SizedBox(height: 16),
          segmented(
            'Police',
            [for (final f in fontPairs) (f.id, f.name, f.display)],
            current.fontId,
            (v) => current.copyWith(fontId: v),
          ),
          segmented(
            'Densité',
            [('comfortable', 'Aérée', null), ('compact', 'Compacte', null)],
            current.density,
            (v) => current.copyWith(density: v),
          ),
          segmented(
            'Angles',
            [('soft', 'Doux', null), ('sharp', 'Marqués', null)],
            current.corners,
            (v) => current.copyWith(corners: v),
          ),
          const SizedBox(height: 8),
          Text(
            'Vos choix vous suivent sur vos appareils ; l’autre membre garde les siens.',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget presetCard(StylePreset preset, ColorScheme colors) {
    final palette = paletteById(preset.appearance.paletteId);
    final selected = preset.appearance == current;
    return Semantics(
      selected: selected,
      button: true,
      label: '${preset.name}, ${preset.description}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => choose(preset.appearance),
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 52,
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in [palette.primary, palette.accent])
                      Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                preset.name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFamily: fontById(preset.appearance.fontId).display,
                ),
              ),
              Text(
                preset.description,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
