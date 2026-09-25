import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

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
                        if (task.wish) 'Envie',
                        if (task.repeat) '↻',
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
                  if (task.wish) ...[
                    const WishBadge(),
                    const SizedBox(width: 8),
                  ],
                  if (task.repeat) ...[
                    Icon(Icons.repeat, size: 16, color: c.onSurfaceVariant),
                    const SizedBox(width: 6),
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

/// Titre de section d’une liste (« EN RETARD 1 »).
class SectionLabel extends StatelessWidget {
  final String label;
  final int count;
  final Color? color;
  const SectionLabel(this.label, this.count, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
        child: Row(
          children: [
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radius - 2),
            side: BorderSide(
              color: selected ? c.error : (color ?? c.outlineVariant),
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(t.radius - 2),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(t.radius - 4),
                    side: BorderSide(
                      color: same(day, today) && !same(day, selected)
                          ? c.primary
                          : c.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(t.radius - 4),
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
