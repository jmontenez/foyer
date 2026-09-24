import 'package:flutter/material.dart';

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

/// Données d’affichage d’une tâche, calculées par l’écran à partir du ticket.
class TaskView {
  final String title;
  final String meta;
  final TaskBadge? badge;
  final int done, total, comments;
  final List<(String, int)> people;
  const TaskView({
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
  const TaskTile({super.key, required this.task, required this.onTap});

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

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final c = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: c.onSurfaceVariant);
    final title = TextStyle(
      fontFamily: t.displayFont,
      fontSize: t.rows ? 16 : 18,
      fontWeight: FontWeight.w700,
      height: 1.25,
      color: c.onSurface,
    );
    final extras = [
      if (task.total > 0) '${task.done}/${task.total}',
      if (task.comments > 0) plural(task.comments, 'commentaire'),
    ];
    if (t.rows) {
      final ring = switch (task.badge) {
        TaskBadge.late || TaskBadge.urgent => c.error,
        TaskBadge.high => c.secondaryContainer,
        null => c.outline,
      };
      return InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: EdgeInsets.symmetric(vertical: t.compact ? 8 : 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.outlineVariant)),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title, style: title),
                    Text(
                      [
                        task.meta,
                        ...extras,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              people(26),
            ],
          ),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.only(bottom: t.compact ? 8 : 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(t.radius),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(t.compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (task.badge != null) ...[
                    PriorityBadge(task.badge!),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      task.meta,
                      style: muted,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  people(28),
                ],
              ),
              SizedBox(height: t.compact ? 6 : 9),
              Text(task.title, style: title),
              if (task.total > 0 || task.comments > 0) ...[
                SizedBox(height: t.compact ? 6 : 10),
                Row(
                  children: [
                    if (task.total > 0) ...[
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: task.done / task.total,
                            minHeight: 6,
                            color: c.secondaryContainer,
                            backgroundColor: c.outlineVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ] else
                      const Spacer(),
                    Text(extras.join(' · '), style: muted),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// En-tête compact : date ou sous-titre, titre de la vue, recherche et profil.
class ScreenHeader extends StatelessWidget {
  final String title, subtitle;
  final Widget profile;
  final VoidCallback onSearch;
  final bool searching;
  const ScreenHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.profile,
    required this.onSearch,
    this.searching = false,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = tokensOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, t.compact ? 12 : 18, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subtitle, style: TextStyle(color: c.onSurfaceVariant)),
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
                          style: TextStyle(color: c.primary),
                        ),
                      ],
                    ),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.5,
                      color: c.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton.filled(
            tooltip: searching ? 'Fermer la recherche' : 'Rechercher',
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).cardTheme.color,
              foregroundColor: c.onSurface,
              side: BorderSide(color: c.outlineVariant),
            ),
            onPressed: onSearch,
            icon: Icon(searching ? Icons.close : Icons.search),
          ),
          const SizedBox(width: 6),
          profile,
        ],
      ),
    );
  }
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
          shape: StadiumBorder(
            side: BorderSide(color: selected ? c.onSurface : c.outlineVariant),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
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

/// Barre de navigation flottante : l’onglet actif affiche son nom.
class FloatingNav extends StatelessWidget {
  final int index;
  final List<(IconData, String)> items;
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: Theme.of(context).cardTheme.color,
          elevation: 2,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radius + 4),
            side: BorderSide(color: c.outlineVariant),
          ),
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final (i, (icon, label)) in items.indexed)
                    Semantics(
                      selected: i == index,
                      button: true,
                      label: label,
                      excludeSemantics: true,
                      child: Tooltip(
                        message: label,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => onSelected(i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 46,
                            padding: EdgeInsets.symmetric(
                              horizontal: i == index ? 14 : 12,
                            ),
                            decoration: BoxDecoration(
                              color: i == index
                                  ? c.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 22,
                                  color: i == index
                                      ? c.onPrimary
                                      : c.onSurfaceVariant,
                                ),
                                if (i == index) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      color: c.onPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
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
        ),
      ),
    );
  }
}
