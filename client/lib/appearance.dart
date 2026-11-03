import 'package:flutter/material.dart';

/// Un duo personnel « Découpes » : principal (--p, actions & sélection) et accent
/// (--a, marges & tampons). Appliqué **littéralement** — mêmes valeurs en clair et
/// en veillée. Les neutres du contenu ne sont jamais teintés par le duo.
/// Ajouter un duo ici et son ID stable dans Appearance.PaletteIds côté serveur.
class AppPalette {
  final String id, name;
  final Color primary, accent;

  /// Veillée (sombre). Le duo reste identique ; seuls les neutres changent.
  final bool dark;
  const AppPalette(
    this.id,
    this.name,
    this.primary,
    this.accent, {
    this.dark = false,
  });
}

/// Les trois duos du sketch, en clair puis en veillée (mêmes p/a, règle PR #40).
const palettes = [
  AppPalette('sauge', 'Sauge & ambre', Color(0xFF386653), Color(0xFFB58A44)),
  AppPalette('encre', 'Encre & corail', Color(0xFF1F4FE0), Color(0xFFFF3D5E)),
  AppPalette('prune', 'Prune & citron', Color(0xFF7A1FA2), Color(0xFFFACC15)),
  AppPalette(
    'sauge-nuit',
    'Sauge, veillée',
    Color(0xFF386653),
    Color(0xFFB58A44),
    dark: true,
  ),
  AppPalette(
    'encre-nuit',
    'Encre, veillée',
    Color(0xFF1F4FE0),
    Color(0xFFFF3D5E),
    dark: true,
  ),
  AppPalette(
    'prune-nuit',
    'Prune, veillée',
    Color(0xFF7A1FA2),
    Color(0xFFFACC15),
    dark: true,
  ),
];

/// Neutres chauds **fixes** du sketch — jamais teintés par le duo (voir
/// [buildAppTheme]). Deux jeux seulement : papier (clair) et veillée (sombre).
class _Neutrals {
  final Color paper, panel, ink, muted;
  final double lineOpacity;
  const _Neutrals(
    this.paper,
    this.panel,
    this.ink,
    this.muted,
    this.lineOpacity,
  );
}

const _lightNeutrals = _Neutrals(
  Color(0xFFF6EFE3), // --paper
  Color(0xFFFFFDF6), // --panel
  Color(0xFF342650), // --ink
  Color(0xFF6E6386), // --muted
  .16,
);
const _darkNeutrals = _Neutrals(
  Color(0xFF241B31),
  Color(0xFF2D2340),
  Color(0xFFF2EBDF),
  Color(0xFFB6ABC9),
  .17,
);

_Neutrals _neutralsFor(bool dark) => dark ? _darkNeutrals : _lightNeutrals;

/// Fond papier (ou veillée) d’un mode — pour les aperçus du sélecteur.
Color paperFor(bool dark) => _neutralsFor(dark).paper;

/// Mélange sRGB (approxime le color-mix oklab du sketch pour les tons adoucis).
Color _mix(Color base, Color over, double amount) =>
    Color.lerp(base, over, amount)!;

/// Texte noir ou blanc, le plus lisible sur [background] (contraste ≥ 4,5 garanti).
Color readableOn(Color background) {
  final l = background.computeLuminance();
  return (l + .05) / .05 >= 1.05 / (l + .05) ? Colors.black : Colors.white;
}

/// Anciennes palettes sombres (refonte précédente) : on y ramène les données
/// stockées qui ne correspondent plus à aucun duo, pour garder la veillée.
const _legacyDarkIds = {
  'ember-night',
  'lime-charcoal',
  'ruby-onyx',
  'electric-violet',
  'abyss-cyan',
  'd2-sauge-nuit',
  'd2-braise-nuit',
  'd2-prune-nuit',
};

/// Ramène un identifiant stocké (éventuellement d’une ancienne palette) vers un
/// duo connu : inchangé s’il existe, sinon veillée pour un ancien sombre, Sauge sinon.
String _migratePalette(String? id) {
  if (id != null && palettes.any((p) => p.id == id)) return id;
  return _legacyDarkIds.contains(id) ? 'sauge-nuit' : 'sauge';
}

AppPalette paletteById(String? id) =>
    palettes.firstWhere((p) => p.id == id, orElse: () => palettes[0]);

/// Duo personnalisé : l’utilisateur choisit principal + accent et clair/veillée.
/// Les neutres restent ceux du sketch ; seul le duo change.
const customPaletteId = 'custom';

Color? colorFromHex(String? v) =>
    v != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v)
    ? Color(0xFF000000 | int.parse(v.substring(1), radix: 16))
    : null;

String hexOf(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// La palette effective d’une apparence : prédéfinie, ou le duo choisi au curseur.
AppPalette paletteFor(AppAppearance a) {
  if (a.paletteId != customPaletteId) return paletteById(a.paletteId);
  return AppPalette(
    customPaletteId,
    'Sur mesure',
    colorFromHex(a.customPrimary) ?? palettes[0].primary,
    colorFromHex(a.customAccent) ?? palettes[0].accent,
    dark: a.customDark,
  );
}

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
  final String customPrimary, customAccent;
  final bool customDark;
  const AppAppearance({
    this.paletteId = 'sauge',
    this.fontId = 'system',
    this.listStyle = 'cards',
    this.density = 'comfortable',
    this.corners = 'soft',
    this.customPrimary = '#386653',
    this.customAccent = '#B58A44',
    this.customDark = false,
  });

  /// Valeurs inconnues ou absentes (anciennes données) : réglage neutre, et les
  /// anciennes palettes sont ramenées vers un duo connu ([_migratePalette]).
  factory AppAppearance.fromMember(Map<dynamic, dynamic>? m) {
    final raw = m?['paletteId']?.toString();
    return AppAppearance(
      paletteId: raw == customPaletteId
          ? customPaletteId
          : _migratePalette(raw),
      fontId: fontById(m?['fontId']?.toString()).id,
      listStyle: m?['listStyle'] == 'rows' ? 'rows' : 'cards',
      density: m?['density'] == 'compact' ? 'compact' : 'comfortable',
      corners: m?['corners'] == 'sharp' ? 'sharp' : 'soft',
      customPrimary: colorFromHex(m?['customPrimary']?.toString()) == null
          ? '#386653'
          : m!['customPrimary'].toString().toUpperCase(),
      customAccent: colorFromHex(m?['customAccent']?.toString()) == null
          ? '#B58A44'
          : m!['customAccent'].toString().toUpperCase(),
      customDark: m?['customDark'] == true,
    );
  }

  AppAppearance copyWith({
    String? paletteId,
    String? fontId,
    String? listStyle,
    String? density,
    String? corners,
    String? customPrimary,
    String? customAccent,
    bool? customDark,
  }) => AppAppearance(
    paletteId: paletteId ?? this.paletteId,
    fontId: fontId ?? this.fontId,
    listStyle: listStyle ?? this.listStyle,
    density: density ?? this.density,
    corners: corners ?? this.corners,
    customPrimary: customPrimary ?? this.customPrimary,
    customAccent: customAccent ?? this.customAccent,
    customDark: customDark ?? this.customDark,
  );

  Map<String, Object> toJson() => {
    'paletteId': paletteId,
    'fontId': fontId,
    'listStyle': listStyle,
    'density': density,
    'corners': corners,
    'customPrimary': customPrimary,
    'customAccent': customAccent,
    'customDark': customDark,
  };

  @override
  bool operator ==(Object other) =>
      other is AppAppearance &&
      other.paletteId == paletteId &&
      other.fontId == fontId &&
      other.listStyle == listStyle &&
      other.density == density &&
      other.corners == corners &&
      other.customPrimary == customPrimary &&
      other.customAccent == customAccent &&
      other.customDark == customDark;

  @override
  int get hashCode => Object.hash(
    paletteId,
    fontId,
    listStyle,
    density,
    corners,
    customPrimary,
    customAccent,
    customDark,
  );
}

final selectedAppearance = ValueNotifier<AppAppearance>(const AppAppearance());

/// Jetons non couverts par ThemeData, lus par les composants de Foyer.
@immutable
class FoyerTokens extends ThemeExtension<FoyerTokens> {
  final double radius;

  /// Profondeur du coin coupé « Découpes » (voir [cutShape]).
  final double cut;
  final bool compact;
  final bool rows;
  final String? displayFont;
  const FoyerTokens({
    required this.radius,
    this.cut = 16,
    required this.compact,
    required this.rows,
    this.displayFont,
  });

  @override
  FoyerTokens copyWith({
    double? radius,
    double? cut,
    bool? compact,
    bool? rows,
    String? displayFont,
  }) => FoyerTokens(
    radius: radius ?? this.radius,
    cut: cut ?? this.cut,
    compact: compact ?? this.compact,
    rows: rows ?? this.rows,
    displayFont: displayFont ?? this.displayFont,
  );

  @override
  FoyerTokens lerp(covariant FoyerTokens? other, double t) =>
      other == null || t < .5 ? this : other;
}

/// Signature « Découpes » : le coin supérieur droit franchement coupé (asymétrique),
/// les autres à peine — comme une feuille de papier dont on a ciselé un coin.
/// Jamais un arrondi : c'est ce qui rend l'identité reconnaissable sans couleur.
/// [cut] = étendue VERTICALE du biseau (px) ; l'horizontale suit le ratio du
/// sketch (26/18 = 13/9 ≈ 1.444). Gros éléments : cutBig (18). Petits : cutSmall (9).
OutlinedBorder cutShape(double cut, {BorderSide side = BorderSide.none}) =>
    BeveledRectangleBorder(
      side: side,
      borderRadius: BorderRadius.only(
        topRight: Radius.elliptical(cut * 1.444, cut),
      ),
    );

/// Biseaux du sketch : --cut (cartes/panneaux) et --cut-sm (chips/boutons/onglets).
const cutBig = 18.0;
const cutSmall = 9.0;

/// Construit le ColorScheme du sketch : **neutres fixes** (paper/panel/ink/muted
/// selon le mode) et **duo** (p/a) posé seulement sur actions, accents et tampons.
/// On part d’un `fromSeed` pour les rôles résiduels (error, inverse…) puis on
/// écrase tout ce que l’app lit, de sorte que le duo ne teinte jamais les neutres.
ColorScheme _schemeFor(AppPalette palette) {
  final dark = palette.dark;
  final n = _neutralsFor(dark);
  final p = palette.primary, a = palette.accent;
  final pSoft = _mix(n.paper, p, dark ? .26 : .13);
  final aMark = _mix(n.paper, a, dark ? .62 : .72);
  final line = n.ink.withValues(alpha: n.lineOpacity);
  return ColorScheme.fromSeed(
    seedColor: p,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: p,
    onPrimary: readableOn(p),
    primaryContainer: pSoft,
    onPrimaryContainer: readableOn(pSoft),
    secondary: a,
    onSecondary: readableOn(a),
    // Le « mark » accent du sketch (avatars, points, signes) : accent adouci vers
    // le papier, lisible, posé partout où un composant lit secondaryContainer.
    secondaryContainer: aMark,
    onSecondaryContainer: readableOn(aMark),
    tertiary: a,
    onTertiary: readableOn(a),
    surface: n.paper,
    onSurface: n.ink,
    onSurfaceVariant: n.muted,
    surfaceContainerLowest: n.panel,
    surfaceContainerLow: n.panel,
    surfaceContainer: _mix(n.paper, n.ink, .04),
    surfaceContainerHigh: _mix(n.paper, n.ink, .06),
    surfaceContainerHighest: _mix(n.paper, n.ink, .08),
    outline: n.ink.withValues(alpha: dark ? .30 : .28),
    outlineVariant: line,
  );
}

ThemeData buildAppTheme(AppAppearance appearance) {
  final palette = paletteFor(appearance);
  // Typo de la direction « Découpes » : titres Manrope (graisses fortes), texte
  // Atkinson Hyperlegible. Le choix de police n'est plus un réglage public
  // (axes réduits) ; `fontId` reste stocké côté serveur pour compatibilité.
  const bodyFont = 'Atkinson';
  const displayFont = 'Manrope';
  final sharp = appearance.corners == 'sharp';
  final radius = sharp ? 8.0 : 20.0;
  final fieldRadius = sharp ? 6.0 : 14.0;
  // Coin coupé des cartes/panneaux (--cut du sketch) ; les boutons utilisent cutSmall.
  final cut = sharp ? 12.0 : cutBig;
  final colors = _schemeFor(palette);
  // Les cartes et champs reposent sur le panneau (neutre fixe), jamais teinté.
  final card = colors.surfaceContainerLowest;
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: bodyFont,
    visualDensity: appearance.density == 'compact'
        ? VisualDensity.compact
        : VisualDensity.standard,
    scaffoldBackgroundColor: colors.surface,
    colorScheme: colors,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: cutShape(cut, side: BorderSide(color: colors.outlineVariant)),
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
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        // Boutons plats au petit coin coupé (--cut-sm).
        shape: cutShape(cutSmall),
      ),
    ),
  );
  // Titres dans la police d’affichage ; le texte courant garde la police de lecture.
  final text = base.textTheme;
  return base.copyWith(
    textTheme: text.copyWith(
      displayLarge: text.displayLarge?.copyWith(fontFamily: displayFont),
      displayMedium: text.displayMedium?.copyWith(fontFamily: displayFont),
      displaySmall: text.displaySmall?.copyWith(fontFamily: displayFont),
      headlineLarge: text.headlineLarge?.copyWith(fontFamily: displayFont),
      headlineMedium: text.headlineMedium?.copyWith(fontFamily: displayFont),
      headlineSmall: text.headlineSmall?.copyWith(fontFamily: displayFont),
      titleLarge: text.titleLarge?.copyWith(fontFamily: displayFont),
    ),
    extensions: [
      FoyerTokens(
        radius: radius,
        cut: cut,
        compact: appearance.density == 'compact',
        rows: appearance.listStyle == 'rows',
        displayFont: displayFont,
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
  // L’apparence à l’ouverture, pour que « Annuler » la restaure — capturée tout de suite,
  // avant le moindre réglage.
  late final AppAppearance opened;
  // Curseurs tenus en TSL pour éviter la dérive des allers-retours hexadécimaux
  // (teinte perdue quand la saturation ou la luminosité touche une borne).
  late HSLColor primary = HSLColor.fromColor(
    colorFromHex(selectedAppearance.value.customPrimary)!,
  );
  late HSLColor accent = HSLColor.fromColor(
    colorFromHex(selectedAppearance.value.customAccent)!,
  );

  @override
  void initState() {
    super.initState();
    opened = selectedAppearance.value;
  }

  // Tout réglage du duo bascule la palette en « Sur mesure », aperçu immédiat.
  void custom(AppAppearance Function(AppAppearance) change) => setState(
    () => selectedAppearance.value = change(
      selectedAppearance.value.copyWith(paletteId: customPaletteId),
    ),
  );

  Widget customTab() {
    final a = selectedAppearance.value;
    final from = paletteById(a.paletteId);
    return ListView(
      children: [
        if (a.paletteId != customPaletteId)
          TextButton.icon(
            onPressed: () {
              primary = HSLColor.fromColor(from.primary);
              accent = HSLColor.fromColor(from.accent);
              custom(
                (x) => x.copyWith(
                  customPrimary: hexOf(from.primary),
                  customAccent: hexOf(from.accent),
                  customDark: from.dark,
                ),
              );
            },
            icon: const Icon(Icons.colorize_outlined),
            label: Text('Partir de « ${from.name} »'),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Veillée (sombre)'),
          value: a.paletteId == customPaletteId && a.customDark,
          onChanged: (v) => custom((x) => x.copyWith(customDark: v)),
        ),
        ColorSliders(
          label: 'Couleur principale',
          color: primary,
          onChanged: (c) {
            primary = c;
            custom((x) => x.copyWith(customPrimary: hexOf(c.toColor())));
          },
        ),
        const SizedBox(height: 8),
        ColorSliders(
          label: 'Accent',
          color: accent,
          onChanged: (c) {
            accent = c;
            custom((x) => x.copyWith(customAccent: hexOf(c.toColor())));
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: selectedAppearance.value.paletteId == customPaletteId ? 1 : 0,
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
              'Un duo appliqué tel quel, sur un papier qui ne change pas. Vos couleurs vous suivent sur vos appareils.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const TabBar(
              tabs: [
                Tab(text: 'Duos'),
                Tab(text: 'Sur mesure'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                children: [
                  ListView(children: palettes.map(_tile).toList()),
                  customTab(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  // Seul « Annuler » revient en arrière ; toute autre fermeture
                  // (barrière, glissement) garde l’aperçu à l’écran.
                  onPressed: () {
                    selectedAppearance.value = opened;
                    Navigator.pop(context);
                  },
                  child: const Text('Annuler'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, selectedAppearance.value),
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
        // Material propre à la tuile : fond et ripple restent clippés par la liste, au lieu
        // d’être peints sur le Material de la feuille et de déborder au-dessus des onglets.
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: Container(
              width: 72,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: paperFor(p.dark),
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
            subtitle: p.dark ? const Text('Veillée') : null,
            trailing: selected ? const Icon(Icons.check_circle) : null,
            onTap: () => setState(
              () => selectedAppearance.value = selectedAppearance.value
                  .copyWith(paletteId: p.id),
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

/// Une couleur du duo personnalisé : pastille d’aperçu et curseurs teinte/saturation/luminosité.
class ColorSliders extends StatelessWidget {
  final String label;
  final HSLColor color;
  final ValueChanged<HSLColor> onChanged;
  const ColorSliders({
    super.key,
    required this.label,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget slider(
      String name,
      double value,
      double max,
      ValueChanged<double> change,
    ) => Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(name, style: TextStyle(color: muted, fontSize: 13)),
        ),
        Expanded(
          child: Slider(value: value, max: max, onChanged: change),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.toColor(),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(label),
            const Spacer(),
            Text(
              hexOf(color.toColor()),
              style: TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
        slider('Teinte', color.hue, 360, (v) => onChanged(color.withHue(v))),
        slider(
          'Saturation',
          color.saturation,
          1,
          (v) => onChanged(color.withSaturation(v)),
        ),
        // Bornée : un principal quasi noir ou blanc rend le duo illisible.
        slider(
          'Luminosité',
          color.lightness.clamp(.05, .95),
          1,
          (v) => onChanged(color.withLightness(v.clamp(.05, .95))),
        ),
      ],
    );
  }
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
    final picked = await showModalBottomSheet<AppAppearance>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .85,
        child: const PalettePicker(),
      ),
    );
    // Feuille fermée par la barrière ou un glissement (sur grand écran, le bouton
    // Enregistrer de la page passe par la barrière) : on garde ce qui est à l’écran.
    // « Annuler » a déjà restauré l’apparence d’ouverture avant de fermer.
    choose(picked ?? selectedAppearance.value);
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
          // Axes réduits : la direction Découpes fixe police, angles et style de
          // liste ; restent la palette/le duo et la densité.
          heading('Couleurs'),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Couleurs'),
              subtitle: Text(paletteFor(current).name),
              trailing: const Icon(Icons.chevron_right),
              onTap: choosePalette,
            ),
          ),
          heading('Confort'),
          segmented(
            'Densité',
            [('comfortable', 'Aérée', null), ('compact', 'Compacte', null)],
            current.density,
            (v) => current.copyWith(density: v),
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
}
