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
  DateTime? _weekStart;
  bool _showAllDay = true;

  DateTime get _today {
    final t = DateTime.tryParse(widget.data['today']?.toString() ?? '');
    return t == null ? _dateOnly(DateTime.now()) : _dateOnly(t);
  }

  DateTime get _week => _weekStart ?? _mondayOf(_today);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final days = [for (var i = 0; i < 7; i++) _week.add(Duration(days: i))];
    final timed = List.generate(7, (_) => <_Timed>[]);
    final allday = List.generate(7, (_) => <_AllDay>[]);

    int? idxOf(DateTime d) {
      final diff = _dateOnly(d).difference(_week).inDays;
      return (diff >= 0 && diff < 7) ? diff : null;
    }

    for (final t in _maps(widget.data['tickets'])) {
      final stage = t['stageId']?.toString();
      if (stage == 'done' || stage == 'abandoned') continue;
      final due = DateTime.tryParse(t['dueDate']?.toString() ?? '');
      if (due == null) continue;
      final idx = idxOf(due);
      if (idx == null) continue;
      final sm = t['startMinute'] as int?;
      final dm = t['durationMinutes'] as int?;
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
        _controls(c, days),
        _dayHeader(c, days),
        if (_showAllDay && hasAllDay) _allDayBand(c, allday),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: 24 * _hourH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: _gutter, child: _hoursGutter(c)),
                  for (var i = 0; i < 7; i++)
                    Expanded(child: _dayColumn(c, days[i], timed[i])),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controls(ColorScheme c, List<DateTime> days) {
    final label =
        '${days.first.day} – ${days.last.day} ${_mo[days.last.month - 1]}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Semaine précédente',
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                setState(() => _weekStart = _week.subtract(const Duration(days: 7))),
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
            tooltip: 'Semaine suivante',
            icon: const Icon(Icons.chevron_right),
            onPressed: () =>
                setState(() => _weekStart = _week.add(const Duration(days: 7))),
          ),
          TextButton(
            onPressed: () => setState(() => _weekStart = null),
            child: const Text('Auj.'),
          ),
          IconButton(
            tooltip: _showAllDay
                ? 'Masquer les tâches sans heure'
                : 'Afficher les tâches sans heure',
            icon: Icon(
              _showAllDay ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            ),
            onPressed: () => setState(() => _showAllDay = !_showAllDay),
          ),
          IconButton(
            tooltip: 'Nouvel événement',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(null),
          ),
        ],
      ),
    );
  }

  // Éditeur d'événement du foyer (création si [event] est null, sinon modification).
  // Les tâches ont leur propre fiche ; ici on ne touche qu'aux CalendarEvent.
  Future<void> _openEditor(Map<String, dynamic>? event) async {
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
    var date = start == null ? _today : _dateOnly(start);
    var allDay = event?['allDay'] == true;
    var startMin = (start != null && !allDay) ? start.hour * 60 + start.minute : 540;
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
      for (var i = 0; i < 7; i++)
        Expanded(
          child: Column(
            children: [
              Text(
                _wd[i],
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
          for (var i = 0; i < 7; i++)
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

  Widget _dayColumn(ColorScheme c, DateTime day, List<_Timed> slots) =>
      LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: day == _today ? c.primary.withValues(alpha: .05) : null,
              border: Border(left: BorderSide(color: c.outlineVariant)),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
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
                    left: s.lane * (w / s.lanes),
                    width: w / s.lanes,
                    child: _block(c, s),
                  ),
              ],
            ),
          );
        },
      );

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
