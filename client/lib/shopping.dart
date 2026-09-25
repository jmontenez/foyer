import 'package:flutter/material.dart';

import 'api.dart';
import 'ui.dart';

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'ç': 'c', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', //
  'í': 'i', 'ì': 'i', 'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', //
  'õ': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ÿ': 'y', //
  'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
};

/// Clé de comparaison, identique à celle du serveur : sans casse ni accents, pluriel en s/x ignoré.
String ingredientKey(String name) {
  final plain = StringBuffer();
  for (final r in name.trim().toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    plain.write(_accents[ch] ?? ch);
  }
  return plain
      .toString()
      .split(RegExp(r"[ \-']+"))
      .where((w) => w.isNotEmpty)
      .map(
        (w) => w.length > 2 && (w.endsWith('s') || w.endsWith('x'))
            ? w.substring(0, w.length - 1)
            : w,
      )
      .join(' ');
}

// Au plus une faute : lettre en trop, en moins, remplacée ou deux lettres inversées.
bool _oneTypo(String a, String b) {
  if (a == b) return true;
  if ((a.length - b.length).abs() > 1) return false;
  if (a.length == b.length) {
    final diff = [
      for (var i = 0; i < a.length; i++)
        if (a[i] != b[i]) i,
    ];
    return diff.length == 1 ||
        (diff.length == 2 &&
            diff[1] == diff[0] + 1 &&
            a[diff[0]] == b[diff[1]] &&
            a[diff[1]] == b[diff[0]]);
  }
  final (long, short) = a.length > b.length ? (a, b) : (b, a);
  for (var i = 0; i < long.length; i++) {
    if (long.substring(0, i) + long.substring(i + 1) == short) return true;
  }
  return false;
}

/// Recherche dans le catalogue : nom exact, début du nom, début d’un mot, n’importe où, puis
/// une faute de frappe (à partir de 4 lettres). À score égal, les plus utilisés d’abord.
List<Map<String, dynamic>> searchIngredients(
  List<Map<String, dynamic>> catalog,
  String query, {
  int limit = 8,
}) {
  final q = ingredientKey(query);
  if (q.isEmpty) return [];
  final found = <(int, int, int, Map<String, dynamic>)>[];
  for (final (i, ingredient) in catalog.indexed) {
    final key = ingredientKey(ingredient['name'].toString());
    final words = key.split(' ');
    final score = key == q
        ? 0
        : key.startsWith(q)
        ? 1
        : words.any((w) => w.startsWith(q))
        ? 2
        : key.contains(q)
        ? 3
        : q.length >= 4 &&
              words.any(
                (w) =>
                    _oneTypo(w, q) ||
                    (w.length > q.length &&
                        _oneTypo(w.substring(0, q.length), q)),
              )
        ? 4
        : null;
    if (score != null) {
      found.add((score, -(ingredient['uses'] as int? ?? 0), i, ingredient));
    }
  }
  found.sort(
    (a, b) => a.$1 != b.$1
        ? a.$1 - b.$1
        : a.$2 != b.$2
        ? a.$2 - b.$2
        : a.$3 - b.$3,
  );
  return [for (final f in found.take(limit)) f.$4];
}

/// Accès rapide : les ingrédients les plus utilisés, dans l’ordre du catalogue à égalité.
List<Map<String, dynamic>> quickIngredients(
  List<Map<String, dynamic>> catalog, {
  int limit = 12,
}) {
  final indexed = catalog.indexed.toList()
    ..sort((a, b) {
      final uses = (b.$2['uses'] as int? ?? 0) - (a.$2['uses'] as int? ?? 0);
      return uses != 0 ? uses : a.$1 - b.$1;
    });
  return [for (final e in indexed.take(limit)) e.$2];
}

/// Articles groupés par rayon, dans l’ordre du magasin ; les articles cochés à part, en bas.
(
  List<(Map<String, dynamic>, List<Map<String, dynamic>>)>,
  List<Map<String, dynamic>>,
)
groupByAisle(
  List<Map<String, dynamic>> items,
  List<Map<String, dynamic>> aisles,
) {
  final left = items.where((i) => i['done'] != true).toList();
  final known = {for (final a in aisles) a['id']};
  final groups = [
    for (final a in aisles)
      (
        a,
        left
            .where(
              (i) =>
                  (known.contains(i['aisle']) ? i['aisle'] : 'other') ==
                  a['id'],
            )
            .toList(),
      ),
  ].where((g) => g.$2.isNotEmpty).toList();
  return (groups, items.where((i) => i['done'] == true).toList());
}

String apiDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String itemLabel(Map<String, dynamic> item) =>
    item['qty'] == null || item['qty'].toString().isEmpty
    ? item['text'].toString()
    : '${item['text']} · ${item['qty']}';

/// Libellé d’une liste : « Samedi », « Aujourd’hui »… ou « Non programmée ».
String listLabel(Map<String, dynamic> list, DateTime today) {
  final date = DateTime.tryParse(list['date']?.toString() ?? '');
  if (list['id'] == 'draft' || date == null) return 'Non programmée';
  return relativeDay(date, today);
}

/// Choix de la date des courses : aujourd’hui, demain, samedi, ou une autre date.
Future<DateTime?> pickShoppingDate(BuildContext context, DateTime today) async {
  final day = DateTime(today.year, today.month, today.day);
  final saturday = day.add(Duration(days: (6 - day.weekday) % 7));
  final choice = await showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Quand faites-vous les courses ?',
              style: Theme.of(c).textTheme.titleLarge,
            ),
          ),
          for (final d in {day, day.add(const Duration(days: 1)), saturday})
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(relativeDay(d, today)),
              subtitle: Text(headerDay(d)),
              onTap: () => Navigator.pop(c, d),
            ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Choisir une date…'),
            onTap: () async {
              final picked = await showDatePicker(
                context: c,
                firstDate: day,
                lastDate: day.add(const Duration(days: 365)),
                initialDate: day,
              );
              if (c.mounted) Navigator.pop(c, picked);
            },
          ),
        ],
      ),
    ),
  );
  return choice;
}

/// « demain », « samedi », « le 3 oct. » : un jour dans une phrase.
String dayPhrase(String label) {
  final l = label.toLowerCase();
  return RegExp(r'^\d').hasMatch(l) ? 'le $l' : l;
}

/// « d’aujourd’hui », « de samedi », « du 3 oct. ».
String ofDay(String label) {
  final l = label.toLowerCase();
  if (RegExp(r'^\d').hasMatch(l)) return 'du $l';
  return RegExp(r'^[aeiouyhâéèêîôœ]').hasMatch(l) ? 'd’$l' : 'de $l';
}

/// Une tâche Courses existe déjà : l’enrichir, tout regrouper à la nouvelle date, ou garder deux tâches.
Future<String?> askScheduleMode(
  BuildContext context,
  Map<String, dynamic> existing,
  DateTime date,
  DateTime today,
) {
  final when = listLabel(existing, today);
  final newDay = relativeDay(date, today);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Des courses sont déjà prévues'),
      content: Text(
        'Une tâche Courses existe déjà ${dayPhrase(when)}. Que faire de cette liste ?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, 'new'),
          child: const Text('Garder deux tâches'),
        ),
        if (when != newDay)
          TextButton(
            onPressed: () => Navigator.pop(c, 'merge'),
            child: Text('Tout regrouper ${dayPhrase(newDay)}'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(c, 'append'),
          child: Text('Ajouter aux courses ${ofDay(when)}'),
        ),
      ],
    ),
  );
}

/// Choix de qui a fait la tâche (au moins une personne, deux au plus).
Future<List<String>?> askPerformers(
  BuildContext context,
  List<Map<String, dynamic>> members,
  Set<String> initial, {
  String action = 'C’est fait',
}) async {
  final chosen = {...initial};
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, change) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Qui l’a réalisé ?',
                style: Theme.of(c).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text('Choix explicite, indépendant des responsables.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in members)
                    FilterChip(
                      label: Text(m['name']),
                      selected: chosen.contains(m['id']),
                      onSelected: (v) => change(
                        () => v ? chosen.add(m['id']) : chosen.remove(m['id']),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: chosen.isEmpty ? null : () => Navigator.pop(c, true),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok == true ? chosen.toList() : null;
}

/// Résultat de la feuille d’article : quantité et rayon, ou retrait de la liste.
typedef ItemChoice = ({String qty, String aisle, bool remove});

class ItemSheet extends StatefulWidget {
  final String name;
  final String? qty, aisle;
  final bool inList;
  final List<Map<String, dynamic>> aisles;
  const ItemSheet({
    super.key,
    required this.name,
    required this.aisles,
    this.qty,
    this.aisle,
    this.inList = false,
  });
  @override
  State<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<ItemSheet> {
  late final qty = TextEditingController(text: widget.qty ?? '');
  late String aisle = widget.aisle ?? 'other';
  @override
  void dispose() {
    qty.dispose();
    super.dispose();
  }

  void done() => Navigator.pop<ItemChoice>(context, (
    qty: qty.text.trim(),
    aisle: aisle,
    remove: false,
  ));

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.name, style: Theme.of(context).textTheme.titleLarge),
          if (widget.inList)
            Text(
              'Déjà dans la liste',
              style: TextStyle(color: c.primary, fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: qty,
            autofocus: true,
            maxLength: 40,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => done(),
            decoration: const InputDecoration(
              labelText: 'Quantité',
              hintText: 'ex. 2, 500 g, 1 L',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          Text('Rayon', style: TextStyle(color: c.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in widget.aisles)
                ChoiceChip(
                  label: Text(a['name'].toString()),
                  selected: aisle == a['id'],
                  onSelected: (_) => setState(() => aisle = a['id']),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.inList)
                TextButton.icon(
                  onPressed: () => Navigator.pop<ItemChoice>(context, (
                    qty: '',
                    aisle: aisle,
                    remove: true,
                  )),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Retirer'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: done,
                child: Text(widget.inList ? 'Enregistrer' : 'Ajouter'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Onglet Courses : liste en cours, recherche et accès rapide, programmation.
class ShoppingView extends StatefulWidget {
  final Map<String, dynamic> data;
  final Api api;
  final Future<void> Function() onChanged;
  final void Function(Map<String, dynamic> ticket) onOpenTicket;
  const ShoppingView({
    super.key,
    required this.data,
    required this.api,
    required this.onChanged,
    required this.onOpenTicket,
  });
  @override
  State<ShoppingView> createState() => _ShoppingViewState();
}

class _ShoppingViewState extends State<ShoppingView> {
  final search = TextEditingController();
  final focus = FocusNode();
  String? selectedId;
  bool busy = false;

  @override
  void dispose() {
    search.dispose();
    focus.dispose();
    super.dispose();
  }

  Map<String, dynamic> get shopping =>
      Map<String, dynamic>.from(widget.data['shopping'] as Map? ?? {});
  List<Map<String, dynamic>> get aisles => _maps(shopping['aisles']);
  List<Map<String, dynamic>> get catalog => _maps(shopping['ingredients']);
  DateTime get today =>
      DateTime.tryParse(widget.data['today'].toString()) ?? DateTime.now();

  // Tâches Courses ouvertes, puis le brouillon s’il n’est pas vide (ou s’il n’y a rien d’autre).
  List<Map<String, dynamic>> visibleLists() {
    final all = _maps(shopping['lists']);
    final tasks = all.where((l) => l['id'] != 'draft').toList();
    final draft = all.firstWhere(
      (l) => l['id'] == 'draft',
      orElse: () => {'id': 'draft', 'items': []},
    );
    return [
      ...tasks,
      if (_maps(draft['items']).isNotEmpty || tasks.isEmpty) draft,
    ];
  }

  void show(String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      show('$e');
    } finally {
      await widget.onChanged();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<ItemChoice?> sheet(
    String name, {
    String? qty,
    String? aisle,
    bool inList = false,
  }) => showModalBottomSheet<ItemChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => ItemSheet(
      name: name,
      qty: qty,
      aisle: aisle,
      inList: inList,
      aisles: aisles,
    ),
  );

  // Toucher une suggestion : ajout, ou modification si l’ingrédient est déjà dans la liste.
  Future<void> pick(
    Map<String, dynamic> list,
    String name, {
    Map<String, dynamic>? ingredient,
  }) async {
    final existing = _maps(list['items'])
        .where(
          (i) => ingredientKey(i['text'].toString()) == ingredientKey(name),
        )
        .firstOrNull;
    final choice = await sheet(
      existing?['text']?.toString() ?? ingredient?['name']?.toString() ?? name,
      qty: existing?['qty']?.toString() ?? ingredient?['lastQty']?.toString(),
      aisle: existing?['aisle']?.toString() ?? ingredient?['aisle']?.toString(),
      inList: existing != null,
    );
    if (choice == null) return;
    search.clear();
    await run(() async {
      if (existing == null) {
        await widget.api.call('POST', '/api/v1/shopping/items', {
          'list': list['id'],
          'name': name,
          'qty': choice.qty,
          'aisle': choice.aisle,
        });
      } else if (choice.remove) {
        await widget.api.call(
          'DELETE',
          '/api/v1/shopping/items/${list['id']}/${existing['id']}',
        );
      } else {
        await widget.api.call(
          'PATCH',
          '/api/v1/shopping/items/${list['id']}/${existing['id']}',
          {'done': false, 'qty': choice.qty, 'aisle': choice.aisle},
        );
      }
    });
  }

  Future<void> toggle(
    Map<String, dynamic> list,
    Map<String, dynamic> item,
  ) async {
    // Coché tout de suite à l’écran ; le serveur suit.
    setState(() => item['done'] = item['done'] != true);
    final raw = (widget.data['shopping']['lists'] as List)
        .cast<Map>()
        .firstWhere((l) => l['id'] == list['id']);
    for (final i in (raw['items'] as List).cast<Map>()) {
      if (i['id'] == item['id']) i['done'] = item['done'];
    }
    await run(
      () => widget.api.call(
        'PATCH',
        '/api/v1/shopping/items/${list['id']}/${item['id']}',
        {'done': item['done'], 'qty': null, 'aisle': null},
      ),
    );
  }

  Future<void> remove(
    Map<String, dynamic> list,
    Map<String, dynamic> item,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await run(
      () => widget.api.call(
        'DELETE',
        '/api/v1/shopping/items/${list['id']}/${item['id']}',
      ),
    );
    messenger?.showSnackBar(
      undoSnackBar('« ${item['text']} » retiré.', () async {
        try {
          await widget.api.call('POST', '/api/v1/shopping/items', {
            'list': list['id'],
            'name': item['text'],
            'qty': item['qty'],
            'aisle': item['aisle'],
          });
        } catch (e) {
          show('$e');
        }
        await widget.onChanged();
      }),
    );
  }

  Future<void> forget(Map<String, dynamic> ingredient) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Oublier « ${ingredient['name']} » ?'),
        content: const Text(
          'Il ne sera plus proposé. Vous pourrez toujours le rajouter en le tapant.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Oublier'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await run(
      () => widget.api.call(
        'DELETE',
        '/api/v1/shopping/ingredients/${Uri.encodeComponent(ingredient['name'].toString())}',
      ),
    );
  }

  Future<void> schedule(Map<String, dynamic> list) async {
    final date = await pickShoppingDate(context, today);
    if (date == null || !mounted) return;
    if (list['id'] != 'draft') {
      await run(
        () => widget.api.call('POST', '/api/v1/shopping/${list['id']}/date', {
          'date': apiDate(date),
        }),
      );
      return;
    }
    final tasks = visibleLists().where((l) => l['id'] != 'draft').toList();
    var mode = 'new';
    if (tasks.isNotEmpty) {
      final chosen = await askScheduleMode(context, tasks.first, date, today);
      if (chosen == null) return;
      mode = chosen;
    }
    await run(() async {
      final t = await widget.api.call('POST', '/api/v1/shopping/schedule', {
        'date': apiDate(date),
        'mode': mode,
        'targetId': mode == 'new' ? null : tasks.first['id'],
      });
      selectedId = t['id']?.toString();
      show(
        mode == 'append'
            ? 'Liste ajoutée aux courses prévues.'
            : 'Courses prévues ${relativeDay(date, today).toLowerCase()}.',
      );
    });
  }

  Future<void> finish(Map<String, dynamic> list) async {
    final ticket = _maps(widget.data['tickets'])
        .where((t) => t['id'] == list['id'])
        .firstOrNull;
    if (ticket == null) return;
    final me = widget.data['me']?['id']?.toString();
    final assignees = (ticket['assignees'] as List? ?? []).cast<String>();
    final performers = await askPerformers(
      context,
      _maps(widget.data['members']),
      {...assignees, if (assignees.isEmpty && me != null) me},
      action: 'Courses faites',
    );
    if (performers == null) return;
    final left = _maps(list['items']).where((i) => i['done'] != true).length;
    await run(() async {
      await widget.api.call('PUT', '/api/v1/tickets/${ticket['id']}', {
        for (final key in [
          'title',
          'description',
          'kind',
          'priority',
          'startDate',
          'dueDate',
          'assignees',
          'tagIds',
          'checklist',
          'version',
        ])
          key: ticket[key],
        'stageId': 'done',
        'performers': performers,
      });
      selectedId = null;
      show(
        left == 0
            ? 'Bravo, les courses sont faites.'
            : '${plural(left, 'article non acheté', 'articles non achetés')} remis dans la liste.',
      );
    });
  }

  Future<void> clearDone(Map<String, dynamic> list) => run(
    () => widget.api.call('POST', '/api/v1/shopping/${list['id']}/clear-done'),
  );

  Future<void> reorderAisles() => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => AisleOrderPage(api: widget.api, aisles: aisles),
        ),
      )
      .then((_) => widget.onChanged());

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final lists = visibleLists();
    final list = lists.firstWhere(
      (l) => l['id'] == selectedId,
      orElse: () => lists.first,
    );
    final items = _maps(list['items']);
    final inList = {for (final i in items) ingredientKey(i['text']): i};
    final draft = list['id'] == 'draft';
    final query = search.text.trim();
    final matches = searchIngredients(catalog, query);
    final exact =
        query.isNotEmpty &&
        (matches.any((m) => ingredientKey(m['name']) == ingredientKey(query)) ||
            inList.containsKey(ingredientKey(query)));
    final (groups, basket) = groupByAisle(items, aisles);
    final ticket = _maps(widget.data['tickets'])
        .where((t) => t['id'] == list['id'])
        .firstOrNull;

    Widget suggestion(Map<String, dynamic> ingredient) {
      final there = inList[ingredientKey(ingredient['name'])];
      return GestureDetector(
        onLongPress: () => forget(ingredient),
        child: FilterChip(
          selected: there != null,
          showCheckmark: true,
          label: Text(
            there == null ? ingredient['name'].toString() : itemLabel(there),
          ),
          tooltip: there == null ? null : 'Déjà dans la liste',
          onSelected: (_) =>
              pick(list, ingredient['name'].toString(), ingredient: ingredient),
        ),
      );
    }

    Widget match(Map<String, dynamic> m) {
      final there = inList[ingredientKey(m['name'])];
      final aisle = aisles.where((a) => a['id'] == m['aisle']).firstOrNull;
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(
          there != null ? Icons.check_circle : Icons.add_circle_outline,
          color: there != null ? c.primary : null,
        ),
        title: Text(m['name'].toString()),
        subtitle: Text(
          there != null
              ? 'Dans la liste${(there['qty'] ?? '').toString().isEmpty ? '' : ' · ${there['qty']}'}'
              : aisle?['name']?.toString() ?? '',
        ),
        onTap: () => pick(list, m['name'].toString(), ingredient: m),
        onLongPress: () => forget(m),
      );
    }

    Widget row(Map<String, dynamic> item) => Dismissible(
      key: ValueKey('${list['id']}-${item['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: c.errorContainer,
        child: Icon(Icons.delete_outline, color: c.onErrorContainer),
      ),
      onDismissed: (_) => remove(list, item),
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        controlAffinity: ListTileControlAffinity.leading,
        value: item['done'] == true,
        onChanged: (_) => toggle(list, item),
        title: Text(
          item['text'].toString(),
          style: item['done'] == true
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: c.onSurfaceVariant,
                )
              : null,
        ),
        secondary: TextButton(
          onPressed: () => pick(list, item['text'].toString()),
          child: Text(
            (item['qty'] ?? '').toString().isEmpty ? 'Qté' : item['qty'],
          ),
        ),
      ),
    );

    return RefreshIndicator(
      onRefresh: widget.onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
        children: [
          if (lists.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final l in lists)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          '${listLabel(l, today)} · ${_maps(l['items']).length}',
                        ),
                        selected: l['id'] == list['id'],
                        onSelected: (_) => setState(() => selectedId = l['id']),
                      ),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              Icon(
                draft ? Icons.edit_calendar_outlined : Icons.event_available,
                color: draft ? c.onSurfaceVariant : c.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  draft
                      ? 'Pas encore programmées'
                      : 'Prévues ${listLabel(list, today).toLowerCase()}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (draft)
                FilledButton.tonalIcon(
                  onPressed: items.isEmpty || busy
                      ? null
                      : () => schedule(list),
                  icon: const Icon(Icons.event_outlined),
                  label: const Text('Programmer'),
                )
              else ...[
                TextButton(
                  onPressed: busy ? null : () => schedule(list),
                  child: const Text('Changer la date'),
                ),
                if (ticket != null)
                  IconButton(
                    tooltip: 'Voir la tâche',
                    onPressed: () => widget.onOpenTicket(ticket),
                    icon: const Icon(Icons.open_in_new),
                  ),
              ],
              PopupMenuButton<String>(
                tooltip: 'Plus d’options',
                onSelected: (v) =>
                    v == 'aisles' ? reorderAisles() : clearDone(list),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'aisles',
                    child: Text('Ordre des rayons'),
                  ),
                  if (basket.isNotEmpty)
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('Retirer les articles cochés'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: search,
            focusNode: focus,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Ajouter un ingrédient…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer',
                      onPressed: () => setState(search.clear),
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) {
              if (v.trim().isEmpty) return;
              final first = matches.firstOrNull;
              if (first != null &&
                  ingredientKey(first['name']) == ingredientKey(v)) {
                pick(list, first['name'].toString(), ingredient: first);
              } else {
                pick(list, v.trim());
              }
            },
          ),
          if (query.isEmpty) ...[
            SectionLabel('Accès rapide', quickIngredients(catalog).length),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final i in quickIngredients(catalog)) suggestion(i),
              ],
            ),
          ] else ...[
            const SizedBox(height: 6),
            for (final m in matches) match(m),
            if (!exact)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.add),
                title: Text('Ajouter « $query »'),
                subtitle: const Text('Nouvel ingrédient'),
                onTap: () => pick(list, query),
              ),
          ],
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'La liste est vide. Touchez un ingrédient ou tapez son nom.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.onSurfaceVariant),
              ),
            ),
          for (final (aisle, rows) in groups) ...[
            SectionLabel(aisle['name'].toString(), rows.length),
            for (final item in rows) row(item),
          ],
          if (basket.isNotEmpty) ...[
            SectionLabel('Dans le panier', basket.length, color: c.primary),
            for (final item in basket) row(item),
          ],
          if (!draft && items.isNotEmpty) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : () => finish(list),
              icon: const Icon(Icons.check),
              label: const Text('Courses faites'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ordre des rayons dans le magasin, commun au foyer.
class AisleOrderPage extends StatefulWidget {
  final Api api;
  final List<Map<String, dynamic>> aisles;
  const AisleOrderPage({super.key, required this.api, required this.aisles});
  @override
  State<AisleOrderPage> createState() => _AisleOrderPageState();
}

class _AisleOrderPageState extends State<AisleOrderPage> {
  late final items = [...widget.aisles];

  Future<void> reorder(int from, int to) async {
    // onReorderItem fournit déjà l’index final, élément retiré compris.
    setState(() => items.insert(to, items.removeAt(from)));
    try {
      await widget.api.call('PUT', '/api/v1/shopping/aisle-order', [
        for (final a in items) a['id'],
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ordre des rayons')),
    body: ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Text(
          'Dans l’ordre de votre parcours en magasin : la liste suivra le même ordre. Glisser pour réordonner.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      itemCount: items.length,
      onReorderItem: reorder,
      itemBuilder: (_, i) => Card(
        key: ValueKey(items[i]['id']),
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          title: Text(items[i]['name'].toString()),
          trailing: const Icon(Icons.drag_handle),
        ),
      ),
    ),
  );
}
