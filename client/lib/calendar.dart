import 'dart:math';
import 'package:flutter/material.dart';
import 'api.dart';

/// Vue Calendrier — vue **Semaine** (grille horaire) + bande « toute la journée »
/// togglable. Union de la timeline : tâches datées (timées = blocs horaires ; sans
/// heure = bande all-day) et événements (Household.Events). Création/édition des
/// événements du foyer (POST/PUT/DELETE /events) ; taper une tâche ouvre sa fiche.
class CalendarView extends StatefulWidget {
  final Map<String, dynamic> data;
  final Api api;
  final void Function(Map<String, dynamic> ticket) onOpenTicket;
  final Future<void> Function() onChanged;
  const CalendarView({
    super.key,
    required this.data,
    required this.api,
    required this.onOpenTicket,
    required this.onChanged,
  });

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

const _wd = ['LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM', 'DIM'];
const _mo = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _mondayOf(DateTime d) =>
    _dateOnly(d).subtract(Duration(days: d.weekday - 1));
String _hhmm(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}h${(m % 60).toString().padLeft(2, '0')}';
// Nombre venu du JSON, tolérant (int, double, chaîne) : jamais de cast qui plante.
int? _int(dynamic v) => v is int
    ? v
    : v is num
    ? v.toInt()
    : v is String
    ? int.tryParse(v)
    : null;
String _durLabel(int m) => m < 60
    ? '$m min'
    : m % 60 == 0
    ? '${m ~/ 60} h'
    : '${m ~/ 60} h ${m % 60}';
const _cats = ['birthday', 'appointment', 'reminder', 'other'];
const _catLabels = {
  'birthday': 'Anniversaire',
  'appointment': 'Rendez-vous',
  'reminder': 'Rappel',
  'other': 'Autre',
};
String _catLabel(String c) => _catLabels[c] ?? 'Autre';

// Bloc horaire placé sur la grille (tâche timée ou événement).
class _Timed {
  final String title;
  final bool isEvent;
  final int start, end; // minutes depuis minuit
  final Map<String, dynamic>? ticket; // la tâche (pour l'ouvrir), null si événement
  final Map<String, dynamic>? event; // l'événement (pour l'éditer), null si tâche
  int lane = 0, lanes = 1;
  _Timed(this.title, this.isEvent, this.start, this.end, this.ticket, this.event);
}

class _AllDay {
  final String title;
  final bool isEvent;
  final Map<String, dynamic>? ticket;
  final Map<String, dynamic>? event;
  _AllDay(this.title, this.isEvent, this.ticket, this.event);
}

// Attribue des « couloirs » aux blocs qui se chevauchent (algo d'intervalles).
void _assignLanes(List<_Timed> day) {
  day.sort((a, b) => a.start.compareTo(b.start));
  var i = 0;
  while (i < day.length) {
    var clusterEnd = day[i].end;
    var j = i;
    final cluster = <_Timed>[];
    while (j < day.length && day[j].start < clusterEnd) {
      cluster.add(day[j]);
      clusterEnd = max(clusterEnd, day[j].end);
      j++;
    }
    final laneEnds = <int>[];
    for (final s in cluster) {
      var placed = -1;
      for (var l = 0; l < laneEnds.length; l++) {
        if (laneEnds[l] <= s.start) {
          placed = l;
          laneEnds[l] = s.end;
          break;
        }
      }
      if (placed == -1) {
        placed = laneEnds.length;
        laneEnds.add(s.end);
      }
      s.lane = placed;
    }
    for (final s in cluster) {
      s.lanes = laneEnds.length;
    }
    i = j;
  }
}

class _CalendarViewState extends State<CalendarView> {
  static const double _hourH = 44, _gutter = 42;
  final ScrollController _scroll = ScrollController(
    initialScrollOffset: 7 * _hourH,
  );
  DateTime? _anchor; // jour focalisé (défaut : aujourd'hui)
  String _view = 'semaine'; // jour | semaine | mois
  bool _showAllDay = true;

  DateTime get _today {
    final t = DateTime.tryParse(widget.data['today']?.toString() ?? '');
    return t == null ? _dateOnly(DateTime.now()) : _dateOnly(t);
  }

  DateTime get _focus => _anchor ?? _today;
  // Jours affichés par la grille horaire (1 en vue Jour, 7 en vue Semaine).
  List<DateTime> get _gridDays => _view == 'jour'
      ? [_dateOnly(_focus)]
      : [for (var i = 0; i < 7; i++) _mondayOf(_focus).add(Duration(days: i))];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Filet de sécurité : une donnée inattendue ne doit jamais donner une page grise ;
    // on affiche l'erreur plutôt que de planter la zone contenu.
    try {
      return _buildView(context);
    } catch (e) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Calendrier indisponible.\n$e',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildView(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    if (_view == 'mois') {
      return Column(
        children: [
          _controls(c),
          const Divider(height: 1),
          Expanded(child: _monthGrid(c)),
        ],
      );
    }
    final days = _gridDays;
    final n = days.length;
    final first = days.first;
    final timed = List.generate(n, (_) => <_Timed>[]);
    final allday = List.generate(n, (_) => <_AllDay>[]);

    int? idxOf(DateTime d) {
      final diff = _dateOnly(d).difference(first).inDays;
      return (diff >= 0 && diff < n) ? diff : null;
    }

    for (final t in _maps(widget.data['tickets'])) {
      final stage = t['stageId']?.toString();
      if (stage == 'done' || stage == 'abandoned') continue;
      final due = DateTime.tryParse(t['dueDate']?.toString() ?? '');
      if (due == null) continue;
      final idx = idxOf(due);
      if (idx == null) continue;
      final sm = _int(t['startMinute']);
      final dm = _int(t['durationMinutes']);
      if (sm != null && dm != null) {
        timed[idx].add(
          _Timed(t['title'].toString(), false, sm, max(sm + 15, min(1440, sm + dm)), t, null),
        );
      } else {
        allday[idx].add(_AllDay(t['title'].toString(), false, t, null));
      }
    }
    for (final e in _maps(widget.data['events'])) {
      final start = DateTime.tryParse(e['start']?.toString() ?? '')?.toLocal();
      if (start == null) continue;
      final idx = idxOf(start);
      if (idx == null) continue;
      if (e['allDay'] == true) {
        allday[idx].add(_AllDay(e['title'].toString(), true, null, e));
      } else {
        final end = DateTime.tryParse(e['end']?.toString() ?? '')?.toLocal();
        final sm = start.hour * 60 + start.minute;
        final sameDay = end != null && _dateOnly(end) == _dateOnly(start);
        final em = end == null ? sm + 60 : (sameDay ? end.hour * 60 + end.minute : 1440);
        timed[idx].add(
          _Timed(e['title'].toString(), true, sm, max(sm + 15, min(1440, em)), null, e),
        );
      }
    }
    for (final list in timed) {
      _assignLanes(list);
    }
    final hasAllDay = allday.any((l) => l.isNotEmpty);

    return Column(
      children: [
        _controls(c),
        _dayHeader(c, days),
        if (_showAllDay && hasAllDay) _allDayBand(c, allday),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              // Largeur mesurée une seule fois → colonnes à largeur FIXE (plus de
              // LayoutBuilder imbriqué ni d'Expanded dans le défilement : robuste).
              final totalW = box.hasBoundedWidth ? box.maxWidth : 700.0;
              final dayW = max(1.0, (totalW - _gutter) / days.length);
              return SingleChildScrollView(
                controller: _scroll,
                child: SizedBox(
                  height: 24 * _hourH,
                  width: totalW,
                  child: Row(
                    children: [
                      SizedBox(
                        width: _gutter,
                        height: 24 * _hourH,
                        child: _hoursGutter(c),
                      ),
                      for (var i = 0; i < days.length; i++)
                        SizedBox(
                          width: dayW,
                          height: 24 * _hourH,
                          child: _dayColumn(c, days[i], timed[i], dayW),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _controls(ColorScheme c) {
    final f = _focus;
    final d = _gridDays;
    final label = switch (_view) {
      'jour' => '${f.day} ${_mo[f.month - 1]} ${f.year}',
      'mois' => '${_mo[f.month - 1]} ${f.year}',
      _ => '${d.first.day} – ${d.last.day} ${_mo[d.last.month - 1]}',
    };
    void step(int dir) => setState(() {
      _anchor = switch (_view) {
        'jour' => f.add(Duration(days: dir)),
        'mois' => DateTime(f.year, f.month + dir, 1),
        _ => f.add(Duration(days: 7 * dir)),
      };
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Précédent',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => step(-1),
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: c.onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Suivant',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => step(1),
              ),
              IconButton(
                tooltip: 'Nouvel événement',
                icon: const Icon(Icons.add),
                onPressed: () => _openEditor(null),
              ),
            ],
          ),
          Row(
            children: [
              SegmentedButton<String>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'jour', label: Text('Jour')),
                  ButtonSegment(value: 'semaine', label: Text('Semaine')),
                  ButtonSegment(value: 'mois', label: Text('Mois')),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _anchor = null),
                child: const Text('Auj.'),
              ),
              if (_view != 'mois')
                IconButton(
                  tooltip: _showAllDay
                      ? 'Masquer les tâches sans heure'
                      : 'Afficher les tâches sans heure',
                  icon: Icon(
                    _showAllDay
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _showAllDay = !_showAllDay),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Éditeur d'événement du foyer (création si [event] est null, sinon modification).
  // Les tâches ont leur propre fiche ; ici on ne touche qu'aux CalendarEvent.
  Future<void> _openEditor(
    Map<String, dynamic>? event, {
    DateTime? initialDay,
    int? initialMinute,
  }) async {
    final members = _maps(widget.data['members']);
    final start = event == null
        ? null
        : DateTime.tryParse(event['start']?.toString() ?? '')?.toLocal();
    final end = event == null
        ? null
        : DateTime.tryParse(event['end']?.toString() ?? '')?.toLocal();
    final titleCtrl = TextEditingController(
      text: event?['title']?.toString() ?? '',
    );
    var date = start == null ? (initialDay ?? _focus) : _dateOnly(start);
    var allDay = event?['allDay'] == true;
    var startMin = start != null && !allDay
        ? start.hour * 60 + start.minute
        : (initialMinute ?? 540);
    var durMin = (start != null && end != null && !allDay)
        ? max(15, end.difference(start).inMinutes)
        : 60;
    var category = event?['category']?.toString() ?? 'other';
    final participants = <String>{
      ...?(event?['participants'] as List?)?.map((e) => e.toString()),
    };
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final c = Theme.of(ctx).colorScheme;
          Future<void> submit() async {
            if (titleCtrl.text.trim().isEmpty || saving) return;
            setSheet(() => saving = true);
            DateTime at(int min) =>
                DateTime(date.year, date.month, date.day, min ~/ 60, min % 60);
            final body = {
              'title': titleCtrl.text.trim(),
              'start': (allDay ? at(0) : at(startMin)).toUtc().toIso8601String(),
              'end': (allDay ? at(23 * 60 + 59) : at(startMin + durMin))
                  .toUtc()
                  .toIso8601String(),
              'allDay': allDay,
              'category': category,
              'participants': participants.toList(),
            };
            try {
              await widget.api.call(
                event == null ? 'POST' : 'PUT',
                event == null ? '/api/v1/events' : '/api/v1/events/${event['id']}',
                body,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              await widget.onChanged();
            } catch (_) {
              setSheet(() => saving = false);
            }
          }

          Future<void> remove() async {
            if (saving) return;
            setSheet(() => saving = true);
            try {
              await widget.api.call('DELETE', '/api/v1/events/${event!['id']}');
              if (ctx.mounted) Navigator.pop(ctx);
              await widget.onChanged();
            } catch (_) {
              setSheet(() => saving = false);
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event == null ? 'Nouvel événement' : 'Modifier l’événement',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      autofocus: event == null,
                      decoration: const InputDecoration(labelText: 'Titre'),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.event_outlined, size: 18),
                          label: Text('${date.day} ${_mo[date.month - 1]}'),
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: ctx,
                              initialDate: date,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (p != null) setSheet(() => date = _dateOnly(p));
                          },
                        ),
                        FilterChip(
                          label: const Text('Toute la journée'),
                          selected: allDay,
                          onSelected: (v) => setSheet(() => allDay = v),
                        ),
                        if (!allDay)
                          ActionChip(
                            avatar: const Icon(Icons.schedule_outlined, size: 18),
                            label: Text(_hhmm(startMin)),
                            onPressed: () async {
                              final p = await showTimePicker(
                                context: ctx,
                                initialTime: TimeOfDay(
                                  hour: startMin ~/ 60,
                                  minute: startMin % 60,
                                ),
                              );
                              if (p != null) {
                                setSheet(() => startMin = p.hour * 60 + p.minute);
                              }
                            },
                          ),
                        if (!allDay)
                          PopupMenuButton<int>(
                            onSelected: (v) => setSheet(() => durMin = v),
                            itemBuilder: (_) => [
                              for (final d in [15, 30, 45, 60, 90, 120, 180])
                                PopupMenuItem(value: d, child: Text(_durLabel(d))),
                            ],
                            child: Chip(label: Text('Durée · ${_durLabel(durMin)}')),
                          ),
                        PopupMenuButton<String>(
                          onSelected: (v) => setSheet(() => category = v),
                          itemBuilder: (_) => [
                            for (final k in _cats)
                              PopupMenuItem(value: k, child: Text(_catLabel(k))),
                          ],
                          child: Chip(
                            avatar: const Icon(Icons.label_outline, size: 18),
                            label: Text(_catLabel(category)),
                          ),
                        ),
                      ],
                    ),
                    if (members.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Qui est concerné ?',
                        style: TextStyle(color: c.onSurfaceVariant, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final m in members)
                            FilterChip(
                              label: Text(m['name'].toString()),
                              selected: participants.contains(m['id']),
                              onSelected: (v) => setSheet(
                                () => v
                                    ? participants.add(m['id'].toString())
                                    : participants.remove(m['id']),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (event != null)
                          TextButton.icon(
                            onPressed: saving ? null : remove,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Supprimer'),
                          ),
                        const Spacer(),
                        FilledButton(
                          onPressed: saving ? null : submit,
                          child: const Text('Enregistrer'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    titleCtrl.dispose();
  }

  Widget _dayHeader(ColorScheme c, List<DateTime> days) => Row(
    children: [
      const SizedBox(width: _gutter),
      for (var i = 0; i < days.length; i++)
        Expanded(
          child: Column(
            children: [
              Text(
                _wd[days[i].weekday - 1],
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: .5,
                  color: c.onSurfaceVariant,
                ),
              ),
              Text(
                '${days[i].day}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: days[i] == _today ? c.primary : c.onSurface,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _allDayBand(ColorScheme c, List<List<_AllDay>> allday) => Container(
    constraints: const BoxConstraints(maxHeight: 92),
    padding: const EdgeInsets.only(top: 4, bottom: 4),
    child: SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: _gutter),
          for (var i = 0; i < allday.length; i++)
            Expanded(
              child: Column(
                children: [
                  for (final a in allday[i]) _allDayChip(c, a),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _allDayChip(ColorScheme c, _AllDay a) {
    final fill = a.isEvent
        ? c.secondary.withValues(alpha: .18)
        : c.primary.withValues(alpha: .14);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 3),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: a.ticket != null
              ? () => widget.onOpenTicket(a.ticket!)
              : a.event != null
              ? () => _openEditor(a.event)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            child: Text(
              a.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: c.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  // Vue Mois : grille 6×7 (du lundi avant le 1er). Chaque jour montre ses éléments ;
  // un tap sur un jour bascule en vue Jour.
  Widget _monthGrid(ColorScheme c) {
    final f = _focus;
    final gridStart = _mondayOf(DateTime(f.year, f.month, 1));
    final cells = [for (var i = 0; i < 42; i++) gridStart.add(Duration(days: i))];
    final items = <int, List<_AllDay>>{};
    int? cellOf(DateTime d) {
      final diff = _dateOnly(d).difference(gridStart).inDays;
      return (diff >= 0 && diff < 42) ? diff : null;
    }

    for (final t in _maps(widget.data['tickets'])) {
      final stage = t['stageId']?.toString();
      if (stage == 'done' || stage == 'abandoned') continue;
      final due = DateTime.tryParse(t['dueDate']?.toString() ?? '');
      if (due == null) continue;
      final k = cellOf(due);
      if (k == null) continue;
      (items[k] ??= []).add(_AllDay(t['title'].toString(), false, t, null));
    }
    for (final e in _maps(widget.data['events'])) {
      final start = DateTime.tryParse(e['start']?.toString() ?? '')?.toLocal();
      if (start == null) continue;
      final k = cellOf(start);
      if (k == null) continue;
      (items[k] ??= []).add(_AllDay(e['title'].toString(), true, null, e));
    }
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    _wd[i],
                    style: TextStyle(fontSize: 10, color: c.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        for (var w = 0; w < 6; w++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _monthCell(
                      c,
                      cells[w * 7 + col],
                      items[w * 7 + col] ?? const <_AllDay>[],
                      f.month,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _monthCell(
    ColorScheme c,
    DateTime day,
    List<_AllDay> items,
    int focusMonth,
  ) {
    final inMonth = day.month == focusMonth;
    final isToday = day == _today;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _view = 'jour';
        _anchor = day;
      }),
      child: Container(
        decoration: BoxDecoration(
          color: isToday ? c.primary.withValues(alpha: .08) : null,
          border: Border.all(
            color: c.outlineVariant.withValues(alpha: .5),
            width: .5,
          ),
        ),
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${day.day}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: inMonth
                    ? (isToday ? c.primary : c.onSurface)
                    : c.onSurfaceVariant.withValues(alpha: .5),
              ),
            ),
            // Rogné (pas de débordement) : au plus 3 éléments puis « +N ».
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final a in items.take(3)) _monthChip(c, a),
                    if (items.length > 3)
                      Text(
                        '+${items.length - 3}',
                        style: TextStyle(
                          fontSize: 9,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthChip(ColorScheme c, _AllDay a) {
    final fill = a.isEvent
        ? c.secondary.withValues(alpha: .20)
        : c.primary.withValues(alpha: .16);
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(3),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        child: Text(
          a.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 9, color: c.onSurface),
        ),
      ),
    );
  }

  Widget _hoursGutter(ColorScheme c) => Stack(
    children: [
      for (var h = 1; h < 24; h++)
        Positioned(
          top: h * _hourH - 6,
          right: 4,
          child: Text(
            '${h}h',
            style: TextStyle(fontSize: 10, color: c.onSurfaceVariant),
          ),
        ),
    ],
  );

  // [dayW] est fourni par la grille (largeur fixe) : plus de LayoutBuilder ici.
  Widget _dayColumn(ColorScheme c, DateTime day, List<_Timed> slots, double dayW) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: day == _today ? c.primary.withValues(alpha: .05) : null,
        border: Border(left: BorderSide(color: c.outlineVariant)),
      ),
      child: Stack(
        children: [
          // Fond tappable (sous les blocs) : taper un créneau vide ouvre un nouvel
          // événement à l'heure touchée (arrondie au quart d'heure, modifiable).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final minute = ((d.localPosition.dy / _hourH * 4).round() * 15)
                    .clamp(0, 1425)
                    .toInt();
                _openEditor(null, initialDay: day, initialMinute: minute);
              },
            ),
          ),
          for (var h = 1; h < 24; h++)
            Positioned(
              top: h * _hourH,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                color: c.outlineVariant.withValues(alpha: .45),
              ),
            ),
          for (final s in slots)
            Positioned(
              top: s.start / 60 * _hourH,
              height: (s.end - s.start) / 60 * _hourH,
              left: s.lane * (dayW / s.lanes),
              width: dayW / s.lanes,
              child: _block(c, s),
            ),
        ],
      ),
    );
  }

  Widget _block(ColorScheme c, _Timed s) {
    final accent = s.isEvent ? c.secondary : c.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 2, bottom: 1),
      child: Material(
        color: accent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(5),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: s.ticket != null
              ? () => widget.onOpenTicket(s.ticket!)
              : s.event != null
              ? () => _openEditor(s.event)
              : null,
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: accent, width: 3)),
            ),
            padding: const EdgeInsets.fromLTRB(5, 2, 3, 2),
            // Un bloc court (p. ex. 15 min) ne doit jamais déborder : on laisse le
            // contenu à sa taille naturelle et on le rogne (pas de RenderFlex overflow).
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hhmm(s.start),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, color: c.onSurfaceVariant),
                  ),
                  Text(
                    s.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: c.onSurface,
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
