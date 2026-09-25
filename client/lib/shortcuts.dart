import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
List<String> _strings(dynamic v) =>
    (v as List? ?? []).map((e) => e.toString()).toList();

/// « Il y a 3 jours », « À faire » (occurrence ouverte) ou « Jamais fait ».
String shortcutLast(Map<String, dynamic> s, DateTime today) {
  if (s['openTicketId'] != null) return 'À faire';
  final last = DateTime.tryParse(s['lastDoneAt']?.toString() ?? '');
  return last == null ? 'Jamais fait' : relativeDay(last.toLocal(), today);
}

String dueLabel(int? days) => switch (days) {
  null => 'Sans date',
  0 => 'Aujourd’hui',
  1 => 'Demain',
  7 => 'Dans une semaine',
  _ => 'Dans $days jours',
};

String assignLabel(
  Map<String, dynamic> s,
  List<Map<String, dynamic>> members,
) => switch (s['assign']) {
  'none' => 'Personne',
  'rotation' => 'À tour de rôle',
  'member' =>
    members
            .where((m) => m['id'] == s['assigneeId'])
            .map((m) => m['name'].toString())
            .firstOrNull ??
        'Qui le lance',
  _ => 'Qui le lance',
};

const _dayNames = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

/// Répétition active d’un raccourci (null si aucune ou en pause).
Map<String, dynamic>? activeRepeat(Map<String, dynamic>? s) {
  final r = s?['repeat'];
  return r is Map && r['active'] == true ? Map<String, dynamic>.from(r) : null;
}

/// « Tous les 3 jours après la dernière fois », « Toutes les 2 semaines, le dimanche », « Chaque mois, le 5 ».
String repeatLabel(Map<String, dynamic> r) {
  final every = (r['every'] as num? ?? 1).toInt();
  switch (r['mode']) {
    case 'after':
      return every == 1
          ? 'Chaque jour après la dernière fois'
          : 'Tous les $every jours après la dernière fois';
    case 'weekly':
      final days = [
        for (final d in _strings(r['days']).map(int.parse).toList()..sort())
          _dayNames[d - 1],
      ];
      final list = days.length > 1
          ? '${days.sublist(0, days.length - 1).join(', ')} et ${days.last}'
          : days.join();
      return every == 1
          ? 'Chaque semaine, le $list'
          : 'Toutes les $every semaines, le $list';
    default:
      final day = (r['monthDay'] as num? ?? 1).toInt();
      return day == 31
          ? 'Chaque mois, le dernier jour'
          : 'Chaque mois, le ${day == 1 ? '1er' : day}';
  }
}

/// Raccourcis du panneau de création, les plus utilisés d’abord.
List<Map<String, dynamic>> byUse(dynamic shortcuts) =>
    _maps(shortcuts)..sort((a, b) {
      final uses = (b['uses'] as num? ?? 0).compareTo(a['uses'] as num? ?? 0);
      return uses != 0
          ? uses
          : (a['order'] as num? ?? 0).compareTo(b['order'] as num? ?? 0);
    });

/// Puce d’un raccourci : un toucher lance, un appui long préremplit pour étoffer.
class ShortcutChip extends StatelessWidget {
  final Map<String, dynamic> shortcut;
  final DateTime today;
  final VoidCallback onTap, onLongPress;
  const ShortcutChip({
    super.key,
    required this.shortcut,
    required this.today,
    required this.onTap,
    required this.onLongPress,
  });
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = tokensOf(context);
    final last = shortcutLast(shortcut, today);
    return Semantics(
      button: true,
      label:
          '${shortcut['title']}, ${activeRepeat(shortcut) != null ? 'répété, ' : ''}$last',
      hint: 'Toucher pour ajouter, appui long pour préciser',
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Material(
        color: Theme.of(context).cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radius - 4),
          side: BorderSide(
            color: shortcut['openTicketId'] != null
                ? c.secondaryContainer
                : c.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.radius - 4),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            width: 132,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  shortcut['title'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: t.displayFont,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                Row(
                  children: [
                    if (activeRepeat(shortcut) != null) ...[
                      Icon(Icons.repeat, size: 14, color: c.onSurfaceVariant),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        last,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Réglages → Raccourcis : liste réordonnable, création et modification.
class ShortcutsPage extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> data;
  const ShortcutsPage({super.key, required this.api, required this.data});
  @override
  State<ShortcutsPage> createState() => _ShortcutsPageState();
}

class _ShortcutsPageState extends State<ShortcutsPage> {
  late List<Map<String, dynamic>> items = _maps(widget.data['shortcuts']);
  late Map<String, dynamic> data = widget.data;

  Future<void> reload() async {
    data = Map<String, dynamic>.from(
      await widget.api.call('GET', '/api/v1/state'),
    );
    if (mounted) setState(() => items = _maps(data['shortcuts']));
  }

  Future<void> edit([Map<String, dynamic>? shortcut]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ShortcutEditor(api: widget.api, data: data, shortcut: shortcut),
      ),
    );
    if (changed == true) await reload();
  }

  Future<void> reorder(int from, int to) async {
    setState(() {
      // onReorderItem fournit déjà l’index final, élément retiré compris.
      items.insert(to, items.removeAt(from));
    });
    try {
      await widget.api.call('PUT', '/api/v1/shortcuts-order', [
        for (final s in items) s['id'],
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('$e')));
      }
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final members = _maps(data['members']);
    final today = DateTime.tryParse(data['today'].toString()) ?? DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Raccourcis')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => edit(),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau raccourci'),
      ),
      body: items.isEmpty
          ? const Center(child: Text('Aucun raccourci pour l’instant.'))
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
              header: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  'Toucher un raccourci dans le bouton + crée la tâche d’un geste. Glisser pour réordonner.',
                  style: TextStyle(color: c.onSurfaceVariant),
                ),
              ),
              itemCount: items.length,
              onReorderItem: reorder,
              itemBuilder: (_, i) {
                final s = items[i];
                final steps = _strings(s['checklist']).length;
                return Card(
                  key: ValueKey(s['id']),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(s['title'].toString()),
                    subtitle: Text(
                      [
                        dueLabel(s['dueInDays'] as int?),
                        assignLabel(s, members),
                        if (steps > 0) plural(steps, 'étape'),
                        if (s['repeat'] is Map)
                          '↻ ${repeatLabel(Map<String, dynamic>.from(s['repeat']))}${s['repeat']['active'] == true ? '' : ' (désactivée)'}',
                        shortcutLast(s, today),
                      ].join(' · '),
                    ),
                    trailing: const Icon(Icons.drag_handle),
                    onTap: () => edit(s),
                  ),
                );
              },
            ),
    );
  }
}

/// Création ou modification d’un raccourci. Renvoie true si quelque chose a changé.
class ShortcutEditor extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? shortcut;
  const ShortcutEditor({
    super.key,
    required this.api,
    required this.data,
    this.shortcut,
  });
  @override
  State<ShortcutEditor> createState() => _ShortcutEditorState();
}

class _ShortcutEditorState extends State<ShortcutEditor> {
  late final s = Map<String, dynamic>.from(
    widget.shortcut ??
        {
          'title': '',
          'description': '',
          'kind': 'obligation',
          'priority': 'normal',
          'tagIds': <String>[],
          'checklist': <String>[],
          'dueInDays': 0,
          'assign': 'launcher',
          'assigneeId': null,
        },
  );
  late final title = TextEditingController(text: s['title']);
  late final description = TextEditingController(text: s['description']);
  late final steps = [
    for (final text in _strings(s['checklist']))
      TextEditingController(text: text),
  ];
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    for (final c in steps) {
      c.dispose();
    }
    super.dispose();
  }

  void fail(Object e) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('$e')));

  Future<void> save() async {
    if (title.text.trim().isEmpty) {
      return fail('Donnez un titre à ce raccourci.');
    }
    setState(() => saving = true);
    try {
      final body = {
        'title': title.text.trim(),
        'description': description.text.trim(),
        'kind': s['kind'],
        'priority': s['priority'],
        'tagIds': _strings(s['tagIds']),
        'checklist': [
          for (final c in steps)
            if (c.text.trim().isNotEmpty) c.text.trim(),
        ],
        'dueInDays': s['dueInDays'],
        'assign': s['assign'],
        'assigneeId': s['assign'] == 'member' ? s['assigneeId'] : null,
        'repeat': repeat,
      };
      await widget.api.call(
        widget.shortcut == null ? 'POST' : 'PUT',
        widget.shortcut == null
            ? '/api/v1/shortcuts'
            : '/api/v1/shortcuts/${widget.shortcut!['id']}',
        body,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      fail(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer ce raccourci ?'),
        content: const Text('Les tâches déjà créées restent.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.call(
        'DELETE',
        '/api/v1/shortcuts/${widget.shortcut!['id']}',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      fail(e);
    }
  }

  Map<String, dynamic>? get repeat =>
      s['repeat'] is Map ? Map<String, dynamic>.from(s['repeat']) : null;
  void setRepeat(Map<String, dynamic>? r) => setState(() => s['repeat'] = r);

  Widget stepper(
    String before,
    int value,
    int min,
    int max,
    String after,
    ValueChanged<int> set,
  ) => Row(
    children: [
      Text(before),
      IconButton(
        tooltip: 'Moins',
        onPressed: value > min ? () => set(value - 1) : null,
        icon: const Icon(Icons.remove_circle_outline),
      ),
      Text(
        '$value',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
      IconButton(
        tooltip: 'Plus',
        onPressed: value < max ? () => set(value + 1) : null,
        icon: const Icon(Icons.add_circle_outline),
      ),
      Flexible(child: Text(after)),
    ],
  );

  List<Widget> repeatEditor() {
    final r = repeat;
    final mode = r?['mode'] ?? 'none';
    Map<String, dynamic> base(String m) => {
      'mode': m,
      'every': 1,
      'days': m == 'weekly' ? [DateTime.now().weekday] : <int>[],
      'monthDay': DateTime.now().day,
      'active': true,
    };
    void update(String key, Object value) => setRepeat({...?r, key: value});
    final next = DateTime.tryParse(
      widget.shortcut?['nextDate']?.toString() ?? '',
    );
    return [
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'none', label: Text('Jamais')),
          ButtonSegment(value: 'after', label: Text('Après')),
          ButtonSegment(value: 'weekly', label: Text('Semaine')),
          ButtonSegment(value: 'monthly', label: Text('Mois')),
        ],
        selected: {mode},
        onSelectionChanged: (v) =>
            setRepeat(v.first == 'none' ? null : base(v.first)),
      ),
      if (r != null) ...[
        const SizedBox(height: 8),
        if (mode == 'after')
          stepper(
            'Tous les',
            (r['every'] as num).toInt(),
            1,
            365,
            ' jours après la dernière fois',
            (v) => update('every', v),
          ),
        if (mode == 'weekly') ...[
          Wrap(
            spacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(_dayNames[d - 1].substring(0, 3)),
                  selected: _strings(r['days']).contains('$d'),
                  onSelected: (on) {
                    final days = _strings(r['days']).map(int.parse).toSet();
                    on ? days.add(d) : days.remove(d);
                    if (days.isNotEmpty) update('days', days.toList()..sort());
                  },
                ),
            ],
          ),
          stepper(
            'Toutes les',
            (r['every'] as num).toInt(),
            1,
            8,
            ' semaine(s)',
            (v) => update('every', v),
          ),
        ],
        if (mode == 'monthly')
          stepper(
            'Le',
            (r['monthDay'] as num).toInt(),
            1,
            31,
            ' du mois (31 = dernier jour)',
            (v) => update('monthDay', v),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Créer automatiquement'),
          subtitle: Text(
            r['active'] == true
                ? 'Une tâche à la fois : la suivante arrive quand celle-ci est faite.'
                : 'Désactivée : rien n’est créé tout seul.',
          ),
          value: r['active'] == true,
          onChanged: (v) => update('active', v),
        ),
        Text(
          r['active'] == true &&
                  next != null &&
                  mode == (widget.shortcut?['repeat']?['mode'])
              ? 'Prochaine : ${headerDay(next)}'
              : repeatLabel(r),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ];
  }

  Widget label(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) {
    final members = _maps(widget.data['members']);
    final tags = _maps(widget.data['tags']);
    final due = s['dueInDays'] as int?;
    final who = s['assign'] == 'member'
        ? 'member:${s['assigneeId']}'
        : s['assign'].toString();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Annuler',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: Text(
          widget.shortcut == null ? 'Nouveau raccourci' : 'Raccourci',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: saving ? null : save,
              child: const Text('Enregistrer'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          TextField(
            controller: title,
            autofocus: widget.shortcut == null,
            maxLength: 160,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Titre',
              counterText: '',
            ),
          ),
          label('Échéance'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final d in [
                null,
                0,
                1,
                7,
                if (due != null && ![0, 1, 7].contains(due)) due,
              ])
                ChoiceChip(
                  label: Text(dueLabel(d)),
                  selected: due == d,
                  onSelected: (_) => setState(() => s['dueInDays'] = d),
                ),
            ],
          ),
          label('Qui s’en occupe ?'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (value, text) in [
                ('launcher', 'Qui le lance'),
                for (final m in members)
                  ('member:${m['id']}', m['name'].toString()),
                ('rotation', 'À tour de rôle'),
                ('none', 'Personne'),
              ])
                ChoiceChip(
                  label: Text(text),
                  selected: who == value,
                  onSelected: (_) => setState(() {
                    s['assign'] = value.startsWith('member:')
                        ? 'member'
                        : value;
                    s['assigneeId'] = value.startsWith('member:')
                        ? value.substring(7)
                        : null;
                  }),
                ),
            ],
          ),
          label('Type et priorité'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (value, text) in [
                ('obligation', 'Obligation'),
                ('wish', 'Envie'),
              ])
                ChoiceChip(
                  label: Text(text),
                  selected: s['kind'] == value,
                  onSelected: (_) => setState(() => s['kind'] = value),
                ),
              const SizedBox(width: 8),
              for (final (value, text) in [
                ('low', 'Basse'),
                ('normal', 'Normale'),
                ('high', 'Haute'),
                ('urgent', 'Urgente'),
              ])
                ChoiceChip(
                  label: Text(text),
                  selected: s['priority'] == value,
                  onSelected: (_) => setState(() => s['priority'] = value),
                ),
            ],
          ),
          label('Tags'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in tags)
                FilterChip(
                  label: Text(t['name'].toString()),
                  selected: _strings(s['tagIds']).contains(t['id']),
                  onSelected: (v) => setState(() {
                    final ids = _strings(s['tagIds']);
                    v ? ids.add(t['id']) : ids.remove(t['id']);
                    s['tagIds'] = ids;
                  }),
                ),
            ],
          ),
          label('Étapes'),
          for (final (i, c) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: c,
                decoration: InputDecoration(
                  hintText: 'Étape ${i + 1}',
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: 'Retirer l’étape',
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        setState(() => steps.removeAt(i).dispose()),
                  ),
                ),
              ),
            ),
          if (steps.length < 20)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => steps.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une étape'),
              ),
            ),
          label('Répéter'),
          ...repeatEditor(),
          label('Notes'),
          TextField(
            controller: description,
            minLines: 2,
            maxLines: 6,
            maxLength: 4000,
            decoration: const InputDecoration(
              hintText: 'Précisions utiles à chaque fois',
            ),
          ),
          if (widget.shortcut != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Supprimer ce raccourci'),
            ),
          ],
        ],
      ),
    );
  }
}
