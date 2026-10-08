import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'appearance.dart';

const _weekdays = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];
const _months = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Date lisible relative à [today] : « Aujourd’hui », « Demain », « Samedi », « Il y a 3 jours »…
String relativeDay(DateTime date, DateTime today) {
  final diff = _day(date).difference(_day(today)).inDays;
  return switch (diff) {
    0 => 'Aujourd’hui',
    1 => 'Demain',
    -1 => 'Hier',
    > 1 && < 7 => _weekdays[date.weekday - 1],
    < -1 && > -7 => 'Il y a ${-diff} jours',
    _ =>
      '${date.day} ${_months[date.month - 1]}${date.year == today.year ? '' : ' ${date.year}'}',
  };
}

/// Date courte de l’en-tête : « Jeudi 24 sept. ».
String headerDay(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// « 1 commentaire », « 2 commentaires ».
String plural(int n, String one, [String? many]) =>
    '$n ${n > 1 ? (many ?? '${one}s') : one}';

FoyerTokens tokensOf(BuildContext context) =>
    Theme.of(context).extension<FoyerTokens>() ??
    const FoyerTokens(radius: 20, compact: false, rows: false);

/// Couleur propre à chaque membre : principale pour le premier, teinte opposée pour l’autre.
(Color, Color) memberColors(ColorScheme c, int index) {
  if (index == 0) return (c.primary, c.onPrimary);
  final hsl = HSLColor.fromColor(c.primary);
  final dark = c.brightness == Brightness.dark;
  final color = hsl
      .withHue((hsl.hue + 180) % 360)
      .withSaturation(hsl.saturation < .55 ? .55 : hsl.saturation)
      .withLightness(dark ? .62 : .36)
      .toColor();
  return (color, readableOn(color));
}

class MemberAvatar extends StatelessWidget {
  final String name;
  final int index;
  final double size;
  const MemberAvatar({
    super.key,
    required this.name,
    required this.index,
    this.size = 28,
  });
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = memberColors(Theme.of(context).colorScheme, index);
    return Tooltip(
      message: name,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(
          name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: TextStyle(
            color: fg,
            fontSize: size * .45,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Emplacement vide en pointillés : tâche sans responsable.
class UnassignedAvatar extends StatelessWidget {
  final double size;
  const UnassignedAvatar({super.key, this.size = 28});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Sans responsable',
    child: CustomPaint(
      size: Size.square(size),
      painter: _DashedCircle(Theme.of(context).colorScheme.outline),
    ),
  );
}

class _DashedCircle extends CustomPainter {
  final Color color;
  _DashedCircle(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Offset.zero & size;
    for (var i = 0; i < 12; i++) {
      canvas.drawArc(rect.deflate(1), i * 0.5236, 0.3, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

/// Case « coupée au ciseau » : l’hexagone irrégulier de la famille Découpes.
/// Enfoncement au toucher (emprunt « Objet ») et retour haptique léger.
class CutCheck extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;
  final String? semanticLabel;
  const CutCheck({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 26,
    this.semanticLabel,
  });
  @override
  State<CutCheck> createState() => _CutCheckState();
}

class _CutCheckState extends State<CutCheck> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final enabled = widget.onChanged != null;
    return Semantics(
      checked: widget.value,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => pressed = true) : null,
        onTapCancel: () => setState(() => pressed = false),
        onTap: enabled
            ? () {
                setState(() => pressed = false);
                HapticFeedback.selectionClick();
                widget.onChanged!(!widget.value);
              }
            : null,
        // Marge interne : zone tactile confortable sans grossir le dessin.
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: AnimatedScale(
            scale: pressed ? .86 : 1,
            duration: Duration(
              milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 90,
            ),
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _CutCheckPainter(
                value: widget.value,
                border: enabled ? c.onSurface : c.outline,
                fill: c.primary,
                mark: c.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CutCheckPainter extends CustomPainter {
  final bool value;
  final Color border, fill, mark;
  _CutCheckPainter({
    required this.value,
    required this.border,
    required this.fill,
    required this.mark,
  });

  // Le « rond coupé au ciseau » : volontairement irrégulier, jamais un cercle.
  static Path shape(Size s) => Path()
    ..moveTo(s.width * .50, 0)
    ..lineTo(s.width * .96, s.height * .18)
    ..lineTo(s.width, s.height * .62)
    ..lineTo(s.width * .72, s.height)
    ..lineTo(s.width * .14, s.height * .92)
    ..lineTo(0, s.height * .38)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape(size);
    if (value) {
      canvas.drawPath(path, Paint()..color = fill);
      final check = Path()
        ..moveTo(size.width * .26, size.height * .52)
        ..lineTo(size.width * .44, size.height * .70)
        ..lineTo(size.width * .76, size.height * .32);
      canvas.drawPath(
        check,
        Paint()
          ..color = mark
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .11
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..color = border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_CutCheckPainter old) =>
      old.value != value ||
      old.border != border ||
      old.fill != fill ||
      old.mark != mark;
}

/// Famille de signes « Découpes » : formes pleines, asymétriques, une par usage.
/// Elles vivent en marge (rayons, sections, états), jamais sous le texte.
enum FoyerSign {
  leaf,
  drop,
  jar,
  epi,
  flake,
  fish,
  cup,
  bubbles,
  star,
  house,
  bag,
  sun,
  cal,
  book,
}

/// Signe d’un rayon de courses (ids du serveur, repli : cabas).
FoyerSign aisleSign(String? id) => switch (id) {
  'produce' => FoyerSign.leaf,
  'bakery' => FoyerSign.epi,
  'dairy' => FoyerSign.drop,
  'meat' => FoyerSign.fish,
  'savory' => FoyerSign.jar,
  'sweet' => FoyerSign.star,
  'drinks' => FoyerSign.cup,
  'frozen' => FoyerSign.flake,
  'hygiene' => FoyerSign.bubbles,
  'cleaning' => FoyerSign.house,
  _ => FoyerSign.bag,
};

class SignIcon extends StatelessWidget {
  final FoyerSign sign;
  final double size;
  final Color? color;
  const SignIcon(this.sign, {super.key, this.size = 18, this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _SignPainter(
      sign,
      color ?? Theme.of(context).colorScheme.secondaryContainer,
    ),
  );
}

class _SignPainter extends CustomPainter {
  final FoyerSign sign;
  final Color color;
  _SignPainter(this.sign, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Dessins dans un repère 24×24, remis à l'échelle.
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;
    Path poly(List<(double, double)> pts) {
      final p = Path()..moveTo(pts.first.$1, pts.first.$2);
      for (final (x, y) in pts.skip(1)) {
        p.lineTo(x, y);
      }
      return p..close();
    }

    switch (sign) {
      case FoyerSign.leaf:
        canvas.drawPath(
          Path()
            ..moveTo(4, 20)
            ..cubicTo(3, 10, 9, 3, 20, 2)
            ..cubicTo(21, 10, 18, 18, 10, 20)
            ..cubicTo(8, 20.5, 5, 20.5, 4, 20)
            ..close(),
          fill,
        );
      case FoyerSign.drop:
        canvas.drawPath(
          Path()
            ..moveTo(12, 2)
            ..cubicTo(17, 8, 21, 12, 20, 17)
            ..cubicTo(19.3, 21, 16, 23, 12, 23)
            ..cubicTo(8, 23, 4.4, 21, 4, 17)
            ..cubicTo(3, 12, 8, 8, 12, 2)
            ..close(),
          fill,
        );
      case FoyerSign.jar:
        canvas.drawRRect(
          RRect.fromLTRBR(7, 3, 17, 6.5, const Radius.circular(1.5)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(5.5, 8, 18.5, 22, const Radius.circular(4)),
          fill,
        );
      case FoyerSign.epi:
        canvas.drawPath(
          poly([
            (12, 2),
            (17, 8),
            (13, 8),
            (13, 11),
            (18, 11),
            (22, 17),
            (14, 17),
            (14, 22),
            (10, 22),
            (10, 17),
            (3, 17),
            (7, 11),
            (11, 11),
            (11, 8),
            (8, 8),
          ]),
          fill,
        );
      case FoyerSign.flake:
        canvas.drawPath(
          poly([
            (12, 1),
            (14, 7),
            (20, 4),
            (17, 10),
            (23, 12),
            (17, 14),
            (20, 20),
            (14, 17),
            (12, 23),
            (10, 17),
            (4, 20),
            (7, 14),
            (1, 12),
            (7, 10),
            (4, 4),
            (10, 7),
          ]),
          fill,
        );
      case FoyerSign.fish:
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(10, 12), width: 15, height: 10),
          fill,
        );
        canvas.drawPath(poly([(16, 12), (22.5, 6.5), (22.5, 17.5)]), fill);
      case FoyerSign.cup:
        canvas.drawPath(
          poly([(6, 4), (18, 4), (16.5, 21.5), (7.5, 21.5)]),
          fill,
        );
      case FoyerSign.bubbles:
        canvas.drawCircle(const Offset(9, 9), 6, fill);
        canvas.drawCircle(const Offset(17, 14), 4.2, fill);
        canvas.drawCircle(const Offset(10.5, 19), 2.8, fill);
      case FoyerSign.star:
        canvas.drawPath(
          poly([
            (12, 2),
            (14.6, 8.8),
            (22, 9),
            (16.6, 13.8),
            (18.5, 21),
            (12, 17.2),
            (5.5, 21),
            (7.4, 13.8),
            (2, 9),
            (9.4, 8.8),
          ]),
          fill,
        );
      case FoyerSign.house:
        canvas.drawPath(
          poly([
            (3, 11),
            (12, 3),
            (21, 11),
            (18, 11),
            (18, 21),
            (14, 21),
            (14, 15),
            (10, 15),
            (10, 21),
            (6, 21),
            (6, 11),
          ]),
          fill,
        );
      case FoyerSign.bag:
        canvas.drawPath(
          poly([(5, 8), (19, 8), (17.5, 21.5), (6.5, 21.5)]),
          fill,
        );
        canvas.drawPath(
          Path()
            ..moveTo(9, 8)
            ..cubicTo(9, 3.5, 15, 3.5, 15, 8),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      case FoyerSign.sun:
        canvas.drawCircle(const Offset(12, 12), 5.2, fill);
        for (var i = 0; i < 8; i++) {
          canvas.save();
          canvas.translate(12, 12);
          canvas.rotate(i * 0.7854 + (i.isEven ? 0 : .12)); // rayons inégaux
          canvas.drawRRect(
            RRect.fromLTRBR(-1.1, -11, 1.1, -7.2, const Radius.circular(1)),
            fill,
          );
          canvas.restore();
        }
      case FoyerSign.cal:
        canvas.drawRRect(
          RRect.fromLTRBR(4, 5, 20, 21, const Radius.circular(2.5)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(7, 2, 9.2, 7, const Radius.circular(1)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(14.8, 2, 17, 7, const Radius.circular(1)),
          fill,
        );
      case FoyerSign.book:
        canvas.drawPath(
          Path()
            ..moveTo(12, 5)
            ..cubicTo(9, 3.5, 6, 3.5, 4, 4.5)
            ..lineTo(4, 19)
            ..cubicTo(7, 18, 10, 18.5, 12, 20)
            ..cubicTo(14, 18.5, 17, 18, 20, 19)
            ..lineTo(20, 4.5)
            ..cubicTo(18, 3.5, 15, 3.5, 12, 5)
            ..close(),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(_SignPainter old) =>
      old.sign != sign || old.color != color;
}

// ======================================================================
// Kit « Découpes » : formes portées 1:1 depuis le CSS du sketch (étude 03).
// Couleurs via le thème courant (le modèle couleur viendra plus tard).
// ======================================================================

/// Onglet biseauté (`.tabs .tab`) : bord encre 1.5 px, actif = plein principal.
class CutTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const CutTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.fromLTRB(14, 8, 16, 9),
          decoration: ShapeDecoration(
            color: selected ? c.primary : Colors.transparent,
            shape: cutShape(
              cutSmall,
              side: selected
                  ? BorderSide.none
                  : BorderSide(color: c.onSurface, width: 1.5),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: selected ? c.onPrimary : c.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Puce biseautée (`.habit.chip`) : bord fin, un toucher. Coche optionnelle à gauche.
class CutChip extends StatelessWidget {
  final String label;
  final String? trailing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const CutChip({
    super.key,
    required this.label,
    required this.onTap,
    this.trailing,
    this.selected = false,
    this.onLongPress,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 7, 11, 8),
          decoration: ShapeDecoration(
            color: selected
                ? c.primary.withValues(alpha: .13)
                : Colors.transparent,
            shape: cutShape(
              cutSmall,
              side: BorderSide(color: c.outlineVariant, width: 1.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 16, color: c.primary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 7),
                Text(
                  trailing!,
                  style: TextStyle(fontSize: 13, color: c.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton plat biseauté (`.cta` / `.cta.quiet`). `primary` = plein principal.
class CutButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  const CutButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.primary = true,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final fg = primary ? c.onPrimary : c.onSurface;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? .45 : 1,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
            decoration: ShapeDecoration(
              color: primary ? c.primary : Colors.transparent,
              shape: cutShape(
                cutSmall,
                side: primary
                    ? BorderSide.none
                    : BorderSide(color: c.onSurface, width: 2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: fg,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, size: 18, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Champ carré bordé encre + bouton d'envoi accolé (`.entry`).
class EntryRow extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final IconData submitIcon;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmit;
  const EntryRow({
    super.key,
    this.controller,
    required this.hint,
    this.submitIcon = Icons.add,
    this.focusNode,
    this.onSubmitted,
    this.onChanged,
    this.onSubmit,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.onSurface, width: 2),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: onSubmit ?? () => onSubmitted?.call(controller?.text ?? ''),
            child: Container(
              width: 50,
              height: 46,
              alignment: Alignment.center,
              color: c.onSurface,
              child: Icon(submitIcon, color: c.surface, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartouche de date biseauté (`.stamp`) : « MER / 07 / OCT ».
class DateStamp extends StatelessWidget {
  final String top, big, bottom;
  const DateStamp({
    super.key,
    required this.top,
    required this.big,
    required this.bottom,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final label = TextStyle(
      fontFamily: 'Manrope',
      fontWeight: FontWeight.w700,
      fontSize: 11,
      letterSpacing: .8,
      height: 1.1,
      color: c.onSurface,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 7, 14, 8),
      decoration: ShapeDecoration(
        color: c.secondaryContainer.withValues(alpha: .35),
        shape: cutShape(cutSmall),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(top.toUpperCase(), style: label),
          Text(
            big,
            style: label.copyWith(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          Text(bottom.toUpperCase(), style: label),
        ],
      ),
    );
  }
}

/// Lien souligné discret (`.linkish`).
class LinkText extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool strong;
  const LinkText({
    super.key,
    required this.label,
    this.onTap,
    this.strong = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      // onTap sur le Semantics : les actions sémantiques (tests, lecteur d'écran)
      // déclenchent le callback — le GestureDetector seul n'y répond pas.
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            color: onTap == null
                ? c.onSurfaceVariant.withValues(alpha: .4)
                : c.onSurfaceVariant,
            decoration: TextDecoration.underline,
            decorationColor: c.onSurfaceVariant,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

enum TaskBadge { late, urgent, high }

class PriorityBadge extends StatelessWidget {
  final TaskBadge kind;
  const PriorityBadge(this.kind, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final (label, fill) = switch (kind) {
      TaskBadge.late => ('EN RETARD', c.error),
      TaskBadge.urgent => ('URGENT', c.primary),
      TaskBadge.high => ('HAUTE', c.secondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: readableOn(fill),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

/// Repère discret des envies (l’obligation est le cas par défaut, sans marque).
class WishBadge extends StatelessWidget {
  const WishBadge({super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.outline),
      ),
      child: Text(
        'ENVIE',
        style: TextStyle(
          color: c.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

/// Données d’affichage d’une tâche, calculées par l’écran à partir du ticket.
class TaskView {
  final String title;
  final String meta;
  final TaskBadge? badge;
  final int done, total, comments;
  final List<(String, int)> people;
  final bool wish, repeat;
  const TaskView({
    this.wish = false,
    this.repeat = false,
    required this.title,
    required this.meta,
    this.badge,
    this.done = 0,
    this.total = 0,
    this.comments = 0,
    this.people = const [],
  });
}

/// Tâche en carte ou en ligne selon le jeton « affichage » du membre.
class TaskTile extends StatelessWidget {
  final TaskView task;
  final VoidCallback onTap;
  final bool selected;
  const TaskTile({
    super.key,
    required this.task,
    required this.onTap,
    this.selected = false,
  });

  Widget people(double size) => task.people.isEmpty
      ? UnassignedAvatar(size: size)
      : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, (name, index)) in task.people.indexed)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                child: MemberAvatar(name: name, index: index, size: size),
              ),
          ],
        );

  /// Lecture d’écran : le titre d’abord, puis l’essentiel, sans initiales ni pourcentages.
  String get semanticLabel => [
    task.title,
    if (task.badge != null)
      switch (task.badge!) {
        TaskBadge.late => 'en retard',
        TaskBadge.urgent => 'urgent',
        TaskBadge.high => 'priorité haute',
      },
    if (task.wish) 'envie',
    if (task.repeat) 'répétée',
    if (task.meta.isNotEmpty) task.meta,
    task.people.isEmpty
        ? 'sans responsable'
        : task.people.map((p) => p.$1).join(' et '),
    if (task.total > 0) '${task.done} sur ${plural(task.total, 'étape')}',
    if (task.comments > 0) plural(task.comments, 'commentaire'),
  ].join(', ');

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    onTap: onTap,
    excludeSemantics: true,
    child: _build(context),
  );

  Widget _build(BuildContext context) {
    final t = tokensOf(context);
    final c = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: c.onSurfaceVariant);
    final title = TextStyle(
      fontFamily: t.displayFont,
      fontSize: 16.5,
      fontWeight: FontWeight.w800,
      height: 1.2,
      color: c.onSurface,
    );
    // Rangée plate « Découpes » : signe du type en marge (couleur = état),
    // titre, puis ligne personne · méta. Filet 1 px ; sélection = teinte biseautée.
    final late = task.badge == TaskBadge.late;
    final mark = switch (task.badge) {
      TaskBadge.late || TaskBadge.urgent => c.error,
      TaskBadge.high => c.secondaryContainer,
      null => c.secondaryContainer,
    };
    final person = task.people.isEmpty
        ? 'Personne'
        : task.people.map((p) => p.$1).join(' + ');
    final metaExtras = [
      task.meta,
      if (task.total > 0) '${task.done}/${task.total}',
      if (task.comments > 0) plural(task.comments, 'commentaire'),
    ].where((s) => s.isNotEmpty).join(' · ');
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          selected ? 10 : 2,
          t.compact ? 10 : 13,
          10,
          t.compact ? 10 : 13,
        ),
        decoration: selected
            ? ShapeDecoration(
                color: c.primary.withValues(alpha: .13),
                shape: cutShape(cutSmall),
              )
            : const BoxDecoration(),
        foregroundDecoration: selected
            ? null
            : BoxDecoration(
                border: Border(bottom: BorderSide(color: c.outlineVariant)),
              ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SignIcon(
                task.wish ? FoyerSign.star : FoyerSign.house,
                size: 18,
                color: mark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title, style: title),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (task.people.isEmpty)
                        const UnassignedAvatar(size: 18)
                      else
                        MemberAvatar(
                          name: task.people.first.$1,
                          index: task.people.first.$2,
                          size: 18,
                        ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: person),
                              if (task.wish) const TextSpan(text: ' · Envie'),
                              if (task.repeat) const TextSpan(text: ' · ↻'),
                              if (metaExtras.isNotEmpty)
                                TextSpan(
                                  text: ' · $metaExtras',
                                  style: late
                                      ? TextStyle(
                                          color: c.error,
                                          fontWeight: FontWeight.w700,
                                        )
                                      : null,
                                ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// En-tête compact : date ou sous-titre, titre de la vue, recherche et profil.
/// En-tête « carnet » : kicker (petites capitales) + grand titre à point, et à
/// droite le cartouche de date + « Liste partagée ». Les utilitaires (recherche,
/// notifications, profil) vivent dans le rail (ouvert) ou dans [trailing] (fermé).
class ScreenHeader extends StatelessWidget {
  final String title, subtitle;
  final Widget? stamp;
  final String? live;
  // Utilitaires (recherche, notifications, profil) : affichés ici en format
  // fermé ; vides en ouvert (ils vivent dans le rail).
  final List<Widget> utilities;
  const ScreenHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.stamp,
    this.live,
    this.utilities = const [],
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = tokensOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, t.compact ? 12 : 18, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: c.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                // Le point est décoratif : lu « Aujourd’hui », pas « Aujourd’hui point ».
                Semantics(
                  header: true,
                  label: title,
                  excludeSemantics: true,
                  child: Text.rich(
                    TextSpan(
                      text: title,
                      children: [
                        TextSpan(
                          text: '.',
                          style: TextStyle(color: c.secondaryContainer),
                        ),
                      ],
                    ),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                      height: 1.02,
                      color: c.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (stamp != null || utilities.isNotEmpty) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (utilities.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: utilities,
                    ),
                  ),
                ?stamp,
                if (stamp != null && live != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: c.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        live!,
                        style: TextStyle(
                          fontSize: 13,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Rail latéral « Découpes » (écran ouvert) : bande teintée, wordmark en haut,
/// destinations signées avec tampon biseauté sur l'active, utilitaires puis
/// avatars « À deux » en bas.
class FoyerRail extends StatelessWidget {
  final int index;
  final List<(FoyerSign, String)> items;
  final ValueChanged<int> onSelected;
  final List<Map<String, dynamic>> members;
  final int meIndex;
  final VoidCallback onProfile;
  final List<Widget> utilities;
  const FoyerRail({
    super.key,
    required this.index,
    required this.items,
    required this.onSelected,
    required this.members,
    required this.meIndex,
    required this.onProfile,
    this.utilities = const [],
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final band = Color.alphaBlend(
      c.secondaryContainer.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .30 : .48,
      ),
      Theme.of(context).scaffoldBackgroundColor,
    );
    return Container(
      width: 88,
      color: band,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Wordmark « foyer✳ ».
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'foyer',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: c.onSurface,
                  ),
                ),
                const SizedBox(width: 2),
                SignIcon(FoyerSign.star, size: 12, color: c.primary),
              ],
            ),
            const SizedBox(height: 14),
            for (final (i, (sign, label)) in items.indexed)
              Semantics(
                selected: i == index,
                button: true,
                label: label,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => onSelected(i),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 46,
                          height: 34,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (i == index)
                                CustomPaint(
                                  size: const Size(44, 32),
                                  painter: _StampBg(c.primary),
                                ),
                              SignIcon(
                                sign,
                                size: 20,
                                color: i == index
                                    ? c.onPrimary
                                    : c.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 11,
                            fontWeight: i == index
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: i == index
                                ? c.onSurface
                                : c.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const Spacer(),
            if (utilities.isNotEmpty) ...[
              ...utilities.map(
                (u) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: u,
                ),
              ),
              const SizedBox(height: 6),
            ],
            // Avatars « À deux » (toucher = réglages).
            Semantics(
              button: true,
              label: 'Réglages',
              child: GestureDetector(
                onTap: onProfile,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 2),
                  child: Column(
                    children: [
                      for (final (i, m) in members.indexed)
                        Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                          child: MemberAvatar(
                            name: m['name'].toString(),
                            index: i,
                            size: 26,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'À deux.',
                        style: TextStyle(
                          fontSize: 11,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tampon biseauté irrégulier derrière le signe actif (rail et bandeau).
class _StampBg extends CustomPainter {
  final Color color;
  _StampBg(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(w * .48, 0)
        ..lineTo(w, h * .14)
        ..lineTo(w * .92, h * .78)
        ..lineTo(w * .58, h)
        ..lineTo(w * .08, h * .88)
        ..lineTo(0, h * .26)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_StampBg old) => old.color != color;
}

/// Pastille de filtre (pleine quand active).
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? c.onSurface : Colors.transparent,
          // Pastille « Découpes » : un petit coin coupé plutôt qu'une pilule.
          shape: cutShape(
            9,
            side: BorderSide(color: selected ? c.onSurface : c.outlineVariant),
          ),
          child: InkWell(
            customBorder: cutShape(9),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 18,
                      color: selected ? c.surface : c.onSurface,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? c.surface : c.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Feuille avec saisie : tant que le clavier est ouvert, « retour » ferme le clavier, pas la feuille.
class KeyboardBack extends StatelessWidget {
  final Widget child;
  const KeyboardBack({super.key, required this.child});
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: MediaQuery.viewInsetsOf(context).bottom == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) FocusManager.instance.primaryFocus?.unfocus();
    },
    child: child,
  );
}

/// Bandeau de navigation « Découpes » : une bande de papier au coin coupé,
/// quatre destinations signées ; l’active porte un tampon dans le principal.
class FloatingNav extends StatelessWidget {
  final int index;
  final List<(FoyerSign, String)> items;
  final ValueChanged<int> onSelected;
  const FloatingNav({
    super.key,
    required this.index,
    required this.items,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = tokensOf(context);
    return Material(
      color: Theme.of(context).cardTheme.color,
      elevation: 6,
      shadowColor: Colors.black26,
      shape: cutShape(t.cut + 6, side: BorderSide(color: c.outlineVariant)),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              for (final (i, (sign, label)) in items.indexed)
                Expanded(
                  child: Semantics(
                    selected: i == index,
                    button: true,
                    label: label,
                    excludeSemantics: true,
                    child: Tooltip(
                      message: label,
                      child: InkWell(
                        onTap: () => onSelected(i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 46,
                              height: 32,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (i == index)
                                    CustomPaint(
                                      size: const Size(44, 32),
                                      painter: _StampPainter(c.primary),
                                    ),
                                  SignIcon(
                                    sign,
                                    size: 19,
                                    color: i == index
                                        ? c.onPrimary
                                        : c.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: t.displayFont,
                                fontWeight: i == index
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                                color: i == index
                                    ? c.onSurface
                                    : c.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tampon irrégulier derrière le signe actif — même famille que les découpes.
class _StampPainter extends CustomPainter {
  final Color color;
  _StampPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(w * .48, 0)
        ..lineTo(w, h * .14)
        ..lineTo(w * .92, h * .78)
        ..lineTo(w * .58, h)
        ..lineTo(w * .08, h * .88)
        ..lineTo(0, h * .26)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_StampPainter old) => old.color != color;
}

/// État vide « Découpes » : une petite composition de signes superposés en
/// marge, un titre adulte et direct, une phrase d’explication. Jamais de
/// mascotte ni de félicitation ; les signes vivent au-dessus du texte, pas
/// dessous.
class EmptyState extends StatelessWidget {
  final String title, message;
  final List<FoyerSign> signs;
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.signs = const [FoyerSign.star, FoyerSign.leaf, FoyerSign.house],
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = tokensOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 40, 28, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 150,
              height: 104,
              child: CustomPaint(
                painter: _ComposedSigns(signs, c.secondaryContainer, c.primary),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: t.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: c.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposedSigns extends CustomPainter {
  final List<FoyerSign> signs;
  final Color a, b;
  _ComposedSigns(this.signs, this.a, this.b);
  @override
  void paint(Canvas canvas, Size size) {
    // Trois signes de tailles et teintes différentes, posés en biais —
    // comme des découpes de papier éparpillées, pas une grille.
    final spots = [
      (Offset(size.width * .18, size.height * .30), 58.0, -.18, a),
      (Offset(size.width * .60, size.height * .12), 44.0, .12, b),
      (Offset(size.width * .66, size.height * .56), 50.0, .22, a),
    ];
    for (final (i, (center, s, angle, color)) in spots.indexed) {
      if (i >= signs.length) break;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.translate(-s / 2, -s / 2);
      final painter = _SignPainter(
        signs[i],
        color.withValues(alpha: i == 1 ? .9 : .5),
      );
      painter.paint(canvas, Size.square(s));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ComposedSigns old) =>
      old.a != a || old.b != b || old.signs != signs;
}

/// Titre de section d’une liste (« EN RETARD 1 »), avec un signe Découpes
/// facultatif en marge (rayons de courses).
class SectionLabel extends StatelessWidget {
  final String label;
  final int count;
  final Color? color;
  final FoyerSign? sign;
  const SectionLabel(
    this.label,
    this.count, {
    super.key,
    this.color,
    this.sign,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
        child: Row(
          children: [
            if (sign != null) ...[
              SignIcon(sign!, size: 17),
              const SizedBox(width: 7),
            ],
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
                color: color ?? c.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau de chiffres d’Aujourd’hui : total, retards (filtre), répartition par personne.
class SummaryTiles extends StatelessWidget {
  final int total, late;
  final bool lateOnly;
  final VoidCallback onLate;
  final List<(String, int, int)> people;
  const SummaryTiles({
    super.key,
    required this.total,
    required this.late,
    required this.lateOnly,
    required this.onLate,
    required this.people,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = tokensOf(context);
    final number = TextStyle(
      fontFamily: t.displayFont,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1,
    );
    Widget tile({
      required Widget child,
      Color? color,
      VoidCallback? onTap,
      bool selected = false,
      required String label,
    }) => Expanded(
      child: Semantics(
        label: label,
        button: onTap != null,
        selected: selected,
        excludeSemantics: true,
        child: Material(
          color: color ?? Theme.of(context).cardTheme.color,
          shape: cutShape(
            t.cut,
            side: BorderSide(
              color: selected ? c.error : (color ?? c.outlineVariant),
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            customBorder: cutShape(t.cut),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(t.compact ? 10 : 14),
              child: SizedBox(height: 56, child: child),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          tile(
            label: '$total à faire',
            color: c.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$total', style: number.copyWith(color: c.onPrimary)),
                Text(
                  'à faire',
                  style: TextStyle(
                    color: c.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          tile(
            label: '$late en retard${lateOnly ? ', filtre actif' : ''}',
            onTap: onLate,
            selected: lateOnly,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$late',
                  style: number.copyWith(
                    color: late > 0 ? c.error : c.onSurface,
                  ),
                ),
                Text('en retard', style: TextStyle(color: c.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          tile(
            label: people.map((p) => '${p.$1} ${p.$3}').join(', '),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    for (final (i, (name, index, _)) in people.indexed)
                      Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                        child: MemberAvatar(name: name, index: index, size: 26),
                      ),
                  ],
                ),
                Text(
                  people.map((p) => '${p.$3}').join(' · '),
                  style: TextStyle(color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Frise des 7 jours de la semaine, avec un point par tâche ; toucher un jour filtre la liste.
class DayStrip extends StatelessWidget {
  final List<(DateTime, int)> days;
  final DateTime today;
  final DateTime? selected;
  final ValueChanged<DateTime?> onSelect;
  const DayStrip({
    super.key,
    required this.days,
    required this.today,
    required this.selected,
    required this.onSelect,
  });
  static const _letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = tokensOf(context);
    bool same(DateTime a, DateTime? b) =>
        b != null && a.year == b.year && a.month == b.month && a.day == b.day;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          for (final (i, (day, count)) in days.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Semantics(
                button: true,
                selected: same(day, selected),
                label:
                    '${relativeDay(day, today)} ${day.day}, ${plural(count, 'tâche')}',
                excludeSemantics: true,
                child: Material(
                  color: same(day, selected)
                      ? c.primary
                      : Theme.of(context).cardTheme.color,
                  shape: cutShape(
                    10,
                    side: BorderSide(
                      color: same(day, today) && !same(day, selected)
                          ? c.primary
                          : c.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    customBorder: cutShape(10),
                    onTap: () => onSelect(same(day, selected) ? null : day),
                    child: SizedBox(
                      height: 64,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _letters[day.weekday - 1],
                            style: TextStyle(
                              fontSize: 12,
                              color: same(day, selected)
                                  ? c.onPrimary
                                  : c.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontFamily: t.displayFont,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: same(day, selected)
                                  ? c.onPrimary
                                  : c.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var k = 0; k < (count > 3 ? 3 : count); k++)
                                Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: same(day, selected)
                                        ? c.onPrimary
                                        : c.secondaryContainer,
                                  ),
                                ),
                              if (count == 0) const SizedBox(height: 5),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Semaine civile (lundi → dimanche) contenant [day].
List<DateTime> weekOf(DateTime day) {
  final monday = _day(day).subtract(Duration(days: day.weekday - 1));
  return [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
}

/// Libellé de semaine pour l’historique : « Cette semaine », « Semaine dernière », « Semaine du 8 sept. ».
String weekLabel(DateTime day, DateTime today) {
  final start = weekOf(day).first, current = weekOf(today).first;
  final weeks = current.difference(start).inDays ~/ 7;
  return switch (weeks) {
    0 => 'Cette semaine',
    1 => 'Semaine dernière',
    _ =>
      'Semaine du ${start.day} ${_months[start.month - 1]}${start.year == today.year ? '' : ' ${start.year}'}',
  };
}

/// Sélecteur d’étape du tableau mobile : une colonne à la fois, avec compteurs.
class StageSelector extends StatelessWidget {
  final List<(String, String, int)> stages;
  final String selected;
  final ValueChanged<String> onSelect;
  const StageSelector({
    super.key,
    required this.stages,
    required this.selected,
    required this.onSelect,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = tokensOf(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(t.radius - 2),
      ),
      child: Row(
        children: [
          for (final (id, name, count) in stages)
            Expanded(
              child: Semantics(
                button: true,
                selected: id == selected,
                label: '$name, ${plural(count, 'tâche')}',
                excludeSemantics: true,
                child: Material(
                  color: id == selected
                      ? Theme.of(context).cardTheme.color
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(t.radius - 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(t.radius - 6),
                    onTap: () => onSelect(id),
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: id == selected
                                    ? c.onSurface
                                    : c.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: id == selected
                                  ? c.primary
                                  : c.outlineVariant,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: id == selected
                                    ? c.onPrimary
                                    : c.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Glisser une carte vers la gauche ou la droite pour la déplacer vers l’étape voisine.
/// Les mêmes déplacements sont proposés en actions d’accessibilité (sans geste).
class SwipeToMove extends StatefulWidget {
  final Widget child;
  final String? previous, next;
  final VoidCallback? onPrevious, onNext;
  const SwipeToMove({
    super.key,
    required this.child,
    this.previous,
    this.next,
    this.onPrevious,
    this.onNext,
  });
  @override
  State<SwipeToMove> createState() => _SwipeToMoveState();
}

class _SwipeToMoveState extends State<SwipeToMove> {
  double dx = 0;
  static const threshold = 90.0;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final target = dx > 0 ? widget.previous : widget.next;
    final armed = dx.abs() >= threshold && target != null;
    return Semantics(
      customSemanticsActions: {
        if (widget.onPrevious != null)
          CustomSemanticsAction(label: 'Déplacer vers ${widget.previous}'):
              widget.onPrevious!,
        if (widget.onNext != null)
          CustomSemanticsAction(label: 'Déplacer vers ${widget.next}'):
              widget.onNext!,
      },
      child: GestureDetector(
        onHorizontalDragUpdate: (d) => setState(() {
          final next = dx + d.delta.dx;
          // Pas de glissement vers une étape qui n’existe pas.
          dx =
              (next > 0 && widget.onPrevious == null) ||
                  (next < 0 && widget.onNext == null)
              ? 0
              : next.clamp(-160.0, 160.0);
        }),
        onHorizontalDragEnd: (_) {
          final action = dx >= threshold
              ? widget.onPrevious
              : dx <= -threshold
              ? widget.onNext
              : null;
          setState(() => dx = 0);
          action?.call();
        },
        child: Stack(
          children: [
            if (dx != 0)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: dx > 0
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  decoration: BoxDecoration(
                    color: armed ? c.primary : c.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(
                      tokensOf(context).radius,
                    ),
                  ),
                  child: Text(
                    '${dx > 0 ? '← ' : ''}${target ?? ''}${dx < 0 ? ' →' : ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: armed ? c.onPrimary : c.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            Transform.translate(offset: Offset(dx, 0), child: widget.child),
          ],
        ),
      ),
    );
  }
}

/// Notification « … · Annuler » qui disparaît d’elle-même après 6 s. Depuis Flutter 3.35,
/// une notification avec action reste affichée par défaut (persist) : on le désactive.
SnackBar undoSnackBar(String text, VoidCallback onUndo) => SnackBar(
  content: Text(text),
  duration: const Duration(seconds: 6),
  persist: false,
  action: SnackBarAction(label: 'Annuler', onPressed: onUndo),
);
