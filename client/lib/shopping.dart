import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'appearance.dart';
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

// Octets des photos d’ingrédients déjà chargées, par identifiant : une photo remplacée change
// d’identifiant, le cache ne sert donc jamais une version périmée. Un échec est retenté.
final _photoCache = <String, Future<Uint8List>>{};

Future<Uint8List> _photoBytes(Api api, String id) =>
    _photoCache.putIfAbsent(id, () async {
      try {
        return await api.imageBytes(id);
      } catch (_) {
        _photoCache.remove(id);
        rethrow;
      }
    });

/// Vignette de la photo d’un ingrédient ; un toucher l’ouvre en grand.
class IngredientPhoto extends StatelessWidget {
  final Api api;
  final String id;
  final double size;
  const IngredientPhoto({
    super.key,
    required this.api,
    required this.id,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _photoBytes(api, id),
    builder: (c, s) => s.hasData
        ? InkWell(
            onTap: () => showDialog<void>(
              context: c,
              builder: (d) => Dialog(
                child: InteractiveViewer(child: Image.memory(s.data!)),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                s.data!,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            ),
          )
        : SizedBox(
            width: size,
            height: size,
            child: Center(
              child: s.hasError
                  ? const Icon(Icons.broken_image)
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
  );
}

/// Champ photo des feuilles article/ingrédient : vignette actuelle ou choisie, galerie, retrait.
/// Les octets choisis (ou le retrait) remontent par [onChanged] ; l’envoi reste à l’appelant.
class PhotoField extends StatefulWidget {
  final Api api;
  final String? imageId;
  final void Function(Uint8List? photo, bool removePhoto) onChanged;
  const PhotoField({
    super.key,
    required this.api,
    required this.onChanged,
    this.imageId,
  });
  @override
  State<PhotoField> createState() => _PhotoFieldState();
}

class _PhotoFieldState extends State<PhotoField> {
  Uint8List? photo;
  bool removePhoto = false, picking = false;
  bool get has => photo != null || (widget.imageId != null && !removePhoto);

  Future<void> pick() async {
    if (picking) return;
    setState(() => picking = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        photo = bytes;
        removePhoto = false;
      });
      widget.onChanged(photo, removePhoto);
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  void clear() {
    setState(() {
      photo = null;
      removePhoto = true;
    });
    widget.onChanged(null, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photo', style: TextStyle(color: c.onSurfaceVariant)),
        const SizedBox(height: 6),
        Row(
          children: [
            if (photo != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  photo!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
            ] else if (widget.imageId != null && !removePhoto) ...[
              IngredientPhoto(api: widget.api, id: widget.imageId!, size: 48),
              const SizedBox(width: 10),
            ],
            TextButton.icon(
              onPressed: picking ? null : pick,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(has ? 'Changer' : 'Ajouter une photo'),
            ),
            if (has) TextButton(onPressed: clear, child: const Text('Retirer')),
          ],
        ),
        Text(
          'Attachée à l’ingrédient, la photo revient à chaque ajout.',
          style: TextStyle(color: c.onSurfaceVariant, fontSize: 13),
        ),
      ],
    );
  }
}

/// Résultat de la feuille d’article : quantité, rayon et photo, ou retrait de la liste.
typedef ItemChoice = ({
  String qty,
  String aisle,
  bool remove,
  Uint8List? photo,
  bool removePhoto,
});

class ItemSheet extends StatefulWidget {
  final String name;
  final String? qty, aisle;
  final bool inList;
  final List<Map<String, dynamic>> aisles;
  final Api api;
  // Photo actuelle de l’ingrédient au catalogue, et affichage du champ photo (pas à l’import).
  final String? imageId;
  final bool withPhoto;
  const ItemSheet({
    super.key,
    required this.name,
    required this.aisles,
    required this.api,
    this.qty,
    this.aisle,
    this.inList = false,
    this.imageId,
    this.withPhoto = false,
  });
  @override
  State<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<ItemSheet> {
  late final qty = TextEditingController(text: widget.qty ?? '');
  late String aisle = widget.aisle ?? 'other';
  Uint8List? photo;
  bool removePhoto = false;
  @override
  void dispose() {
    qty.dispose();
    super.dispose();
  }

  void done() => Navigator.pop<ItemChoice>(context, (
    qty: qty.text.trim(),
    aisle: aisle,
    remove: false,
    photo: photo,
    removePhoto: removePhoto,
  ));

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return KeyboardBack(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.name, style: Theme.of(context).textTheme.titleLarge),
              if (widget.inList)
                Text(
                  'Déjà dans la liste',
                  style: TextStyle(
                    color: c.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 12),
              // Le bouton reste à côté du champ : visible même clavier ouvert.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
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
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: done,
                    child: Text(widget.inList ? 'Enregistrer' : 'Ajouter'),
                  ),
                ],
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
              if (widget.withPhoto) ...[
                const SizedBox(height: 12),
                PhotoField(
                  api: widget.api,
                  imageId: widget.imageId,
                  onChanged: (p, r) {
                    photo = p;
                    removePhoto = r;
                  },
                ),
              ],
              if (widget.inList) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop<ItemChoice>(context, (
                      qty: '',
                      aisle: aisle,
                      remove: true,
                      photo: null,
                      removePhoto: false,
                    )),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Retirer de la liste'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Résultat de l’éditeur d’ingrédient : nouvelles valeurs, ou « Oublier ».
typedef IngredientChoice = ({
  String name,
  String qty,
  String aisle,
  bool forget,
  Uint8List? photo,
  bool removePhoto,
});

class IngredientSheet extends StatefulWidget {
  final Map<String, dynamic> ingredient;
  final List<Map<String, dynamic>> aisles;
  final Api api;
  const IngredientSheet({
    super.key,
    required this.ingredient,
    required this.aisles,
    required this.api,
  });
  @override
  State<IngredientSheet> createState() => _IngredientSheetState();
}

class _IngredientSheetState extends State<IngredientSheet> {
  late final name = TextEditingController(
    text: widget.ingredient['name']?.toString() ?? '',
  );
  late final qty = TextEditingController(
    text: widget.ingredient['lastQty']?.toString() ?? '',
  );
  late String aisle = widget.ingredient['aisle']?.toString() ?? 'other';
  Uint8List? photo;
  bool removePhoto = false;
  @override
  void dispose() {
    name.dispose();
    qty.dispose();
    super.dispose();
  }

  void done() {
    if (name.text.trim().isEmpty) return;
    Navigator.pop<IngredientChoice>(context, (
      name: name.text.trim(),
      qty: qty.text.trim(),
      aisle: aisle,
      forget: false,
      photo: photo,
      removePhoto: removePhoto,
    ));
  }

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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Modifier l’ingrédient',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton(onPressed: done, child: const Text('Enregistrer')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nom',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qty,
              maxLength: 40,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => done(),
              decoration: const InputDecoration(
                labelText: 'Quantité habituelle',
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
            const SizedBox(height: 8),
            Text(
              'Un nouveau nom ou rayon s’applique aussi aux listes en cours.',
              style: TextStyle(color: c.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            PhotoField(
              api: widget.api,
              imageId: (widget.ingredient['imageId'] ?? '').toString().isEmpty
                  ? null
                  : widget.ingredient['imageId'].toString(),
              onChanged: (p, r) {
                photo = p;
                removePhoto = r;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.pop<IngredientChoice>(context, (
                    name: '',
                    qty: '',
                    aisle: aisle,
                    forget: true,
                    photo: null,
                    removePhoto: false,
                  )),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Oublier'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Modifie ou oublie un ingrédient du catalogue ; renvoie vrai si quelque chose a changé.
Future<bool> editIngredient(
  BuildContext context,
  Api api,
  Map<String, dynamic> ingredient,
  List<Map<String, dynamic>> aisles,
) async {
  final choice = await showModalBottomSheet<IngredientChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => KeyboardBack(
      child: IngredientSheet(ingredient: ingredient, aisles: aisles, api: api),
    ),
  );
  if (choice == null) return false;
  final path =
      '/api/v1/shopping/ingredients/${Uri.encodeComponent(ingredient['name'].toString())}';
  try {
    if (choice.forget) {
      await api.call('DELETE', path);
    } else {
      await api.call('PUT', path, {
        'name': choice.name,
        'aisle': choice.aisle,
        'qty': choice.qty,
      });
      // La photo après le renommage éventuel : l’ingrédient porte déjà son nouveau nom.
      final renamed =
          '/api/v1/shopping/ingredients/${Uri.encodeComponent(choice.name)}';
      if (choice.removePhoto && choice.photo == null) {
        await api.call('DELETE', '$renamed/image');
      }
      if (choice.photo != null) {
        await api.ingredientImage(choice.name, choice.photo!, 'photo.jpg');
      }
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('$e')));
    }
    return false;
  }
}

/// Tous les ingrédients connus, par rayon, pour les corriger ou les oublier.
class IngredientsPage extends StatefulWidget {
  final Api api;
  final List<Map<String, dynamic>> ingredients, aisles;
  const IngredientsPage({
    super.key,
    required this.api,
    required this.ingredients,
    required this.aisles,
  });
  @override
  State<IngredientsPage> createState() => _IngredientsPageState();
}

class _IngredientsPageState extends State<IngredientsPage> {
  late var ingredients = widget.ingredients;
  String query = '';

  Future<void> edit(Map<String, dynamic> ingredient) async {
    if (!await editIngredient(context, widget.api, ingredient, widget.aisles)) {
      return;
    }
    final state = await widget.api.call('GET', '/api/v1/state');
    if (mounted) {
      setState(() => ingredients = _maps(state['shopping']?['ingredients']));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = query.trim().isEmpty
        ? ingredients
        : searchIngredients(ingredients, query, limit: 500);
    final known = {for (final a in widget.aisles) a['id']};
    List<Map<String, dynamic>> of(String aisle) => shown
        .where(
          (i) => (known.contains(i['aisle']) ? i['aisle'] : 'other') == aisle,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Ingrédients')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Chercher un ingrédient…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          for (final a in widget.aisles)
            if (of(a['id']).isNotEmpty) ...[
              SectionLabel(
                a['name'].toString(),
                of(a['id']).length,
                sign: aisleSign(a['id']?.toString()),
              ),
              for (final i in of(a['id']))
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: (i['imageId'] ?? '').toString().isEmpty
                      ? null
                      : IngredientPhoto(
                          api: widget.api,
                          id: i['imageId'].toString(),
                        ),
                  title: Text(i['name'].toString()),
                  subtitle: (i['lastQty'] ?? '').toString().isEmpty
                      ? null
                      : Text('Habituellement ${i['lastQty']}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => edit(i),
                ),
            ],
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text('Aucun ingrédient.', textAlign: TextAlign.center),
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
  // Change de valeur quand on arrive pour ajouter un article : le curseur va dans la recherche.
  final int focusSearch;
  const ShoppingView({
    super.key,
    this.focusSearch = 0,
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

  // Présentation « Préparer » / « En magasin » : un état d'affichage local à
  // l'appareil (jamais envoyé au serveur), retenu pour la session de l'app.
  static String mode = 'prep';

  @override
  void initState() {
    super.initState();
    if (widget.focusSearch > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
    }
  }

  @override
  void didUpdateWidget(ShoppingView old) {
    super.didUpdateWidget(old);
    if (widget.focusSearch != old.focusSearch) focus.requestFocus();
  }

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

  // Photo au catalogue pour cet ingrédient (joint par clé, comme le serveur).
  String? photoOf(String name) {
    final key = ingredientKey(name);
    for (final i in catalog) {
      if (ingredientKey(i['name'].toString()) == key) {
        final id = (i['imageId'] ?? '').toString();
        return id.isEmpty ? null : id;
      }
    }
    return null;
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
      api: widget.api,
      imageId: photoOf(name),
      withPhoto: widget.data['demo'] != true,
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
      // La photo vit sur l’ingrédient du catalogue : posée ou retirée ici, elle vaut partout.
      if (!choice.remove) {
        final target =
            existing?['text']?.toString() ??
            ingredient?['name']?.toString() ??
            name;
        if (choice.removePhoto && choice.photo == null) {
          await widget.api.call(
            'DELETE',
            '/api/v1/shopping/ingredients/${Uri.encodeComponent(target)}/image',
          );
        }
        if (choice.photo != null) {
          await widget.api.ingredientImage(target, choice.photo!, 'photo.jpg');
        }
      }
    });
  }

  // Ajout direct d'un habituel : quantité et rayon mémorisés, zéro feuille.
  Future<void> directAdd(
    Map<String, dynamic> list,
    Map<String, dynamic> ingredient,
  ) async {
    final name = ingredient['name'].toString();
    final qty = (ingredient['lastQty'] ?? '').toString();
    HapticFeedback.selectionClick();
    await run(
      () => widget.api.call('POST', '/api/v1/shopping/items', {
        'list': list['id'],
        'name': name,
        'qty': qty.isEmpty ? null : qty,
        'aisle': ingredient['aisle'],
      }),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          qty.isEmpty ? '« $name » ajouté.' : '« $name · $qty » ajouté.',
        ),
        duration: const Duration(seconds: 5),
        persist: false,
        action: SnackBarAction(
          label: 'Modifier',
          // La liste est relue au moment du toucher : celle capturée avant le
          // rafraîchissement ne contient pas encore l'article ajouté.
          onPressed: () => pick(
            _maps(widget.data['shopping']['lists'])
                .firstWhere((l) => l['id'] == list['id'], orElse: () => list),
            name,
            ingredient: ingredient,
          ),
        ),
      ),
    );
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

  // Appui long sur une suggestion : corriger l’ingrédient (nom, rayon, quantité) ou l’oublier.
  Future<void> editSuggestion(Map<String, dynamic> ingredient) async {
    if (await editIngredient(context, widget.api, ingredient, aisles)) {
      await widget.onChanged();
    }
  }

  Future<void> ingredientsPage() => Navigator.of(context)
      .push(
        MaterialPageRoute<void>(
          builder: (_) => IngredientsPage(
            api: widget.api,
            ingredients: catalog,
            aisles: aisles,
          ),
        ),
      )
      .then((_) => widget.onChanged());

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
    // Clôture : retour haptique franc, comme une touche qu'on enfonce (« Objet »).
    HapticFeedback.mediumImpact();
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

  // Coller une liste (recette, note, sortie d’assistant) : analyse serveur,
  // prévisualisation corrigeable, puis ajout en une fois.
  Future<void> importList(Map<String, dynamic> list) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ImportPage(
          api: widget.api,
          listId: list['id'].toString(),
          aisles: aisles,
        ),
      ),
    );
    await widget.onChanged();
    if (result == null) return;
    final added = result['added'] as int? ?? 0;
    final merged = result['merged'] as int? ?? 0;
    show(
      '${plural(added, 'article ajouté', 'articles ajoutés')}'
      '${merged > 0 ? ', ${plural(merged, 'fusionné')}' : ''}.',
    );
  }

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
      // Puce « Découpes ». Habituel absent de la liste : un toucher l'ajoute
      // avec sa quantité mémorisée ; déjà présent : la feuille s'ouvre.
      return CutChip(
        label: there == null ? ingredient['name'].toString() : itemLabel(there),
        selected: there != null,
        onLongPress: () => editSuggestion(ingredient),
        onTap: () => there == null
            ? directAdd(list, ingredient)
            : pick(list, ingredient['name'].toString(), ingredient: ingredient),
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
        onLongPress: () => editSuggestion(m),
      );
    }

    Widget row(Map<String, dynamic> item) {
      final photoId = photoOf(item['text'].toString());
      return Dismissible(
        key: ValueKey('${list['id']}-${item['id']}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: c.errorContainer,
          child: Icon(Icons.delete_outline, color: c.onErrorContainer),
        ),
        onDismissed: (_) => remove(list, item),
        // Rangée plate « Découpes » : tick ciseau + (vignette) + nom + chip qty,
        // filet 1 px. Le toucher sur le nom coche ; la case porte son haptique.
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.outlineVariant)),
          ),
          child: Row(
            children: [
              CutCheck(
                value: item['done'] == true,
                onChanged: (_) => toggle(list, item),
                semanticLabel: item['text'].toString(),
              ),
              if (photoId != null) ...[
                IngredientPhoto(api: widget.api, id: photoId),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    toggle(list, item);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      item['text'].toString(),
                      style: item['done'] == true
                          ? TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: c.onSurfaceVariant,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              // Chip de quantité « Découpes » : un toucher ouvre la feuille.
              GestureDetector(
                onTap: () => pick(list, item['text'].toString()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: ShapeDecoration(
                    color: c.primary.withValues(alpha: .13),
                    shape: cutShape(cutSmall),
                  ),
                  child: Text(
                    (item['qty'] ?? '').toString().isEmpty
                        ? 'Qté'
                        : item['qty'].toString(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: tokensOf(context).displayFont,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final prepTools = <Widget>[
      // Titre de programmation au-dessus des actions : tient aussi bien en
      // colonne étroite (volet) qu'en pleine largeur (écran fermé).
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
          PopupMenuButton<String>(
            tooltip: 'Plus d’options',
            onSelected: (v) => switch (v) {
              'import' => importList(list),
              'aisles' => reorderAisles(),
              'ingredients' => ingredientsPage(),
              _ => clearDone(list),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'import',
                child: Text('Importer une liste…'),
              ),
              const PopupMenuItem(
                value: 'ingredients',
                child: Text('Ingrédients'),
              ),
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
      // Programmer / changer la date, sous le titre.
      Row(
        children: [
          if (draft)
            FilledButton.tonalIcon(
              onPressed: items.isEmpty || busy ? null : () => schedule(list),
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
          children: [for (final i in quickIngredients(catalog)) suggestion(i)],
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
      if (items.isEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 32, bottom: 8),
          child: Text(
            'La liste est vide. Touchez un ingrédient ou tapez son nom. Appui long sur une suggestion pour la modifier.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.onSurfaceVariant),
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: busy ? null : () => importList(list),
            icon: const Icon(Icons.content_paste_go_outlined),
            label: const Text('Importer une liste collée'),
          ),
        ),
        const SizedBox(height: 16),
      ],
    ];

    // Écran ouvert, mode « Préparer » : les outils d'ajout passent dans un
    // volet à droite (le sketch), la liste occupe le volet principal à gauche.
    // En magasin, ou sur écran fermé, tout reste dans une seule colonne.
    // Écran ouvert, mode « Préparer » : les outils d'ajout passent dans un
    // volet à droite (le sketch), la liste occupe le volet principal à gauche.
    // En magasin, ou sur écran fermé, tout reste dans une seule colonne (les
    // outils réapparaissent en tête via le spread conditionnel ci-dessous).
    final wide = MediaQuery.sizeOf(context).width >= 640;
    final mainChildren = <Widget>[
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
      // Deux présentations d'une même liste : préparer (outillage complet)
      // ou en magasin (les articles d'abord, le reste replié).
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Row(
          children: [
            CutTab(
              label: 'Préparer',
              selected: mode == 'prep',
              onTap: () => setState(() => mode = 'prep'),
            ),
            CutTab(
              label: 'En magasin',
              selected: mode == 'store',
              onTap: () => setState(() => mode = 'store'),
            ),
            const SizedBox(width: 8),
            // Compteur flexible : il s'ellipse plutôt que de faire déborder la
            // barre quand la place manque (métriques de police selon la plateforme).
            Flexible(
              child: Text(
                plural(items.length, 'article'),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
      if (mode == 'prep' && !wide) ...prepTools,
      if (mode == 'store' && items.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Text(
            'Rien à rapporter. La liste se construit dans « Préparer ».',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.onSurfaceVariant),
          ),
        ),
      // Filet « À rapporter » : la ligne de structure du carnet.
      if (items.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.onSurface, width: 2)),
          ),
          child: Row(
            children: [
              const Text(
                'À RAPPORTER',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${items.where((i) => i['done'] != true).length} restants',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      for (final (aisle, rows) in groups) ...[
        SectionLabel(
          aisle['name'].toString(),
          rows.length,
          sign: aisleSign(aisle['id']?.toString()),
        ),
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
    ];
    if (wide && mode == 'prep') {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: widget.onChanged,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 16, 110),
                children: mainChildren,
              ),
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: c.outlineVariant),
          SizedBox(
            width: 320,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 110),
              children: prepTools,
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: widget.onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
        children: mainChildren,
      ),
    );
  }
}

/// Import d’une liste collée : le serveur analyse le texte (une ligne = un article),
/// la prévisualisation se corrige (rayon des inconnus en premier), puis tout est ajouté d’un coup.
class ImportPage extends StatefulWidget {
  final Api api;
  final String listId;
  final List<Map<String, dynamic>> aisles;
  const ImportPage({
    super.key,
    required this.api,
    required this.listId,
    required this.aisles,
  });
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final text = TextEditingController();
  // null : phase de saisie ; sinon, articles proposés par le serveur, corrigés sur place.
  List<Map<String, dynamic>>? rows;
  bool busy = false;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void show(String message) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));

  String aisleName(dynamic id) {
    for (final a in widget.aisles) {
      if (a['id'] == id) return a['name'].toString();
    }
    return 'Autre';
  }

  Future<void> analyze() async {
    if (busy || text.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final r = await widget.api.call(
        'POST',
        '/api/v1/shopping/import/preview',
        {'list': widget.listId, 'text': text.text},
      );
      setState(() => rows = _maps(r));
    } catch (e) {
      show('$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(Map<String, dynamic> row) async {
    final choice = await showModalBottomSheet<ItemChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ItemSheet(
        name: row['name'].toString(),
        qty: row['qty']?.toString(),
        aisle: row['aisle']?.toString(),
        aisles: widget.aisles,
        api: widget.api,
      ),
    );
    if (choice == null) return;
    setState(() {
      row['qty'] = choice.qty;
      row['aisle'] = choice.aisle;
      row['known'] = true;
    });
  }

  Future<void> submit() async {
    final items = rows ?? [];
    if (busy || items.isEmpty) return;
    setState(() => busy = true);
    try {
      final result = await widget.api.call(
        'POST',
        '/api/v1/shopping/items/batch',
        {
          'list': widget.listId,
          'items': [
            for (final r in items)
              {'name': r['name'], 'qty': r['qty'], 'aisle': r['aisle']},
          ],
        },
      );
      if (mounted) {
        Navigator.pop(context, Map<String, dynamic>.from(result as Map));
      }
    } catch (e) {
      show('$e');
      if (mounted) setState(() => busy = false);
    }
  }

  Widget row(Map<String, dynamic> r) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: Icon(
      r['known'] == true ? Icons.check_circle_outline : Icons.help_outline,
      color: r['known'] == true
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.tertiary,
    ),
    title: Text(r['name'].toString()),
    subtitle: Text(
      [
        aisleName(r['aisle']),
        if ((r['qty'] ?? '').toString().isNotEmpty) r['qty'],
        if (r['merge'] == true) 'déjà dans la liste',
      ].join(' · '),
    ),
    trailing: IconButton(
      tooltip: 'Retirer',
      icon: const Icon(Icons.close),
      onPressed: () => setState(() => rows!.remove(r)),
    ),
    onTap: () => edit(r),
  );

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final toFix = (rows ?? []).where((r) => r['known'] != true).toList();
    final ready = (rows ?? []).where((r) => r['known'] == true).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Importer une liste')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: rows == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Collez une liste d’ingrédients : une ligne par article, '
                    'quantité au début ou à la fin. Les rayons connus seront '
                    'retrouvés automatiquement.',
                    style: TextStyle(color: c.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      controller: text,
                      autofocus: true,
                      maxLines: null,
                      minLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText:
                            '- 500 g de farine\n- 6 œufs\n- 25 cl de lait',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: busy || text.text.trim().isEmpty
                        ? null
                        : analyze,
                    icon: const Icon(Icons.manage_search),
                    label: const Text('Analyser'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        if (toFix.isNotEmpty) ...[
                          SectionLabel('Rayon à préciser', toFix.length),
                          for (final r in toFix) row(r),
                        ],
                        if (ready.isNotEmpty) ...[
                          SectionLabel('Reconnus', ready.length),
                          for (final r in ready) row(r),
                        ],
                        if (rows!.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              'Plus rien à importer.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => rows = null),
                        child: const Text('Modifier le texte'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: busy || rows!.isEmpty ? null : submit,
                        icon: const Icon(Icons.playlist_add),
                        label: Text(
                          'Ajouter ${plural(rows!.length, 'article')}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
