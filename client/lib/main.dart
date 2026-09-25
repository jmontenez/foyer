import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'appearance.dart';
import 'shopping.dart';
import 'shortcuts.dart';
import 'ui.dart';
import 'update.dart';
import 'widgets.dart';

final messenger = GlobalKey<ScaffoldMessengerState>();
final api = Api();
void message(Object error) => messenger.currentState?.showSnackBar(
  SnackBar(content: Text(error.toString())),
);
String id() => DateTime.now().microsecondsSinceEpoch.toString();
List<Map<String, dynamic>> maps(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
List<String> strings(dynamic value) =>
    (value as List? ?? []).map((e) => e.toString()).toList();
String dateLabel(dynamic value) {
  if (value == null) return '';
  final date = DateTime.tryParse(value.toString());
  return date == null ? '' : DateFormat('dd/MM/yyyy').format(date.toLocal());
}

String timeLabel(dynamic value) {
  if (value == null) return '';
  final date = DateTime.tryParse(value.toString());
  return date == null ? '' : DateFormat('dd/MM à HH:mm').format(date.toLocal());
}

String priorityName(String p) =>
    {
      'low': 'Basse',
      'normal': 'Normale',
      'high': 'Haute',
      'urgent': 'Urgente',
    }[p] ??
    p;
Color priorityColor(String p, [Brightness brightness = Brightness.light]) =>
    brightness == Brightness.dark
    ? switch (p) {
        'urgent' => const Color(0xFFFF8A7A),
        'high' => const Color(0xFFFFB870),
        _ => const Color(0xFFA9B4C0),
      }
    : switch (p) {
        'urgent' => const Color(0xFFAA4036),
        'high' => const Color(0xFFAD6932),
        _ => const Color(0xFF52606D),
      };

@pragma('vm:entry-point')
// Notification reçue application fermée : les widgets de l’écran d’accueil se remettent à jour.
@pragma('vm:entry-point')
Future<void> backgroundMessage(RemoteMessage message) async {
  final background = Api();
  await background.initialize();
  await refreshWidgets(background);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in [
      ('Space Grotesk', 'SpaceGrotesk'),
      ('DM Sans', 'DMSans'),
      ('Fraunces', 'Fraunces'),
      ('Atkinson Hyperlegible', 'Atkinson'),
      ('Manrope', 'Manrope'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('fonts/$file-OFL.txt'));
    }
  });
  await api.initialize();
  await registerWidgetActions();
  if (!kIsWeb && const bool.fromEnvironment('FIREBASE_ENABLED')) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
        appId: String.fromEnvironment('FIREBASE_APP_ID'),
        messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
      ),
    );
    FirebaseMessaging.onBackgroundMessage(backgroundMessage);
  }
  runApp(const FoyerApp());
}

class FoyerApp extends StatelessWidget {
  const FoyerApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppAppearance>(
    valueListenable: selectedAppearance,
    builder: (context, appearance, _) => MaterialApp(
      title: 'Foyer',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messenger,
      theme: buildAppTheme(appearance),
      home: const Home(),
    ),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  Map<String, dynamic>? data;
  Map<String, dynamic> config = {};
  bool loading = true, signing = false;
  String? error;
  int tab = 0;
  String person = 'all', query = '', tag = 'all';
  bool searching = false;
  DateTime? historyFrom, historyTo;
  // Filtres propres aux vues : retards (Aujourd’hui), jour (Semaine), type (Backlog), période (Historique).
  bool lateOnly = false;
  String? boardStage;
  DateTime? weekDay;
  String backlogKind = 'all', period = '30';
  Timer? timer;
  bool refreshing = false;
  bool pushInitialized = false;
  bool choosingPalette = false;
  AndroidUpdate? update;
  bool updateDismissed = false, installingUpdate = false;
  DateTime? updateCheckedAt;
  StreamSubscription<RemoteMessage>? pushOpen, pushForeground;
  StreamSubscription<String>? tokenRefresh;
  StreamSubscription<Uri?>? widgetTaps;
  // Toucher sur un widget arrivé avant le chargement des données : traité juste après.
  WidgetLink? pendingLink;
  // Incrémenté pour placer le curseur dans la recherche de Courses (« + » du widget).
  int shoppingSearch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    timer = Timer.periodic(const Duration(seconds: 12), (_) => checkRevision());
    initialWidgetUri().then(openWidgetLink);
    widgetTaps = widgetClicks.listen(openWidgetLink);
  }

  void openWidgetLink(Uri? uri) {
    final link = WidgetLink.parse(uri);
    if (link == null || !mounted) return;
    if (data == null) {
      pendingLink = link;
    } else {
      unawaited(followWidgetLink(link));
    }
  }

  Future<void> followWidgetLink(WidgetLink link) async {
    switch (link) {
      case OpenToday():
        setState(() => tab = 0);
      case QuickCreate():
        await quickCreate();
      case OpenCourses(:final add):
        setState(() {
          tab = 5;
          if (add) shoppingSearch++;
        });
      case OpenTicket(:final id):
        final ticket = maps(data!['tickets'])
            .where((t) => t['id'] == id)
            .firstOrNull;
        if (ticket == null) {
          message('Cette tâche n’existe plus.');
        } else {
          await openTicket(ticket);
        }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    pushOpen?.cancel();
    pushForeground?.cancel();
    tokenRefresh?.cancel();
    widgetTaps?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      checkUpdate(maxAge: const Duration(seconds: 30));
    }
  }

  Future<void> checkRevision() async {
    if (data == null || refreshing) return;
    try {
      final r = await api.call('GET', '/api/v1/revision');
      if (r['revision'] != data!['revision']) await refresh();
    } catch (e) {
      if (e is ApiError && e.status == 401) {
        await refresh();
      } else if (mounted) {
        setState(() => error = e.toString());
      }
    }
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    try {
      if (api.base.isEmpty) {
        if (mounted) setState(() => loading = false);
        return;
      }
      config = Map<String, dynamic>.from(await api.call('GET', '/auth/config'));
      final result = Map<String, dynamic>.from(
        await api.call('GET', '/api/v1/state'),
      );
      if (mounted) {
        setState(() {
          data = result;
          if (!choosingPalette) {
            selectedAppearance.value = AppAppearance.fromMember(result['me']);
          }
          loading = false;
          error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          if (e.status == 401) {
            unawaited(clearWidgets());
            data = null;
            pushInitialized = false;
            error = null;
          } else {
            error = e.toString();
          }
          loading = false;
        });
      }
    } finally {
      refreshing = false;
    }
    if (data != null && !pushInitialized) {
      pushInitialized = true;
      await setupPush();
    }
    if (data != null) {
      unawaited(checkUpdate());
      unawaited(refreshWidgets(api));
      if (pendingLink case final link?) {
        pendingLink = null;
        unawaited(followWidgetLink(link));
      }
    }
  }

  // Vérification au retour dans l’application (au plus toutes les 30 s), sinon au plus une
  // fois par heure lors des rafraîchissements ; silencieuse sauf demande explicite.
  Future<void> checkUpdate({
    bool manual = false,
    Duration maxAge = const Duration(hours: 1),
  }) async {
    if (!Updater.supported) return;
    final last = updateCheckedAt;
    if (!manual && last != null && DateTime.now().difference(last) < maxAge) {
      return;
    }
    updateCheckedAt = DateTime.now();
    try {
      final installed = await Updater.installedVersion();
      final found = await Updater.available(api, installed);
      if (mounted) {
        setState(() {
          update = found;
          if (manual) updateDismissed = false;
        });
      }
      if (manual && found == null) {
        message('Foyer est à jour (build $installed).');
      }
    } catch (e) {
      if (manual) message(e);
    }
  }

  Future<void> installUpdate() async {
    final available = update;
    if (available == null || installingUpdate) return;
    setState(() => installingUpdate = true);
    try {
      if (!await Updater.install(api, available)) {
        await updatePermissionDialog();
      }
    } on PlatformException catch (e) {
      message(e.message ?? 'Mise à jour impossible.');
    } catch (e) {
      message(e);
    } finally {
      if (mounted) setState(() => installingUpdate = false);
    }
  }

  Future<void> updatePermissionDialog() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Autoriser les mises à jour'),
      content: const Text(
        'Android doit autoriser Foyer à installer des applications. '
        'Activez « Autoriser cette source », revenez dans Foyer puis relancez la mise à jour.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(c);
            Updater.openPermission();
          },
          child: const Text('Ouvrir les réglages'),
        ),
      ],
    ),
  );

  Future<void> login({int? demo}) async {
    setState(() => signing = true);
    try {
      if (demo != null) {
        final r = await api.call('POST', '/auth/demo/$demo');
        await api.setSession(r['token']);
      } else if (kIsWeb) {
        await launchUrl(
          api.uri('/auth/google/start'),
          webOnlyWindowName: '_self',
        );
        return;
      } else {
        await GoogleSignIn.instance.initialize(
          serverClientId: config['googleClientId'] as String?,
        );
        final account = await GoogleSignIn.instance.authenticate();
        final r = await api.call('POST', '/auth/google/mobile', {
          'idToken': account.authentication.idToken,
        });
        await api.setSession(r['token']);
      }
      await refresh();
    } catch (e) {
      message(e);
    } finally {
      if (mounted) setState(() => signing = false);
    }
  }

  Future<void> setupPush() async {
    if (kIsWeb || Firebase.apps.isEmpty) return;
    try {
      final permission = await FirebaseMessaging.instance.requestPermission();
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        message(
          'Notifications désactivées : vous pouvez les autoriser dans les réglages Android.',
        );
        return;
      }
      // Le build installé permet au serveur de n’annoncer une mise à jour qu’aux appareils en retard.
      final appVersion = await Updater.installedVersionOrNull();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await api.call('POST', '/api/v1/devices', {
          'token': token,
          'appVersion': ?appVersion,
        });
      }
      await tokenRefresh?.cancel();
      tokenRefresh = FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        api
            .call('POST', '/api/v1/devices', {
              'token': t,
              'appVersion': ?appVersion,
            })
            .catchError((Object e) {
              message(e);
              return null;
            });
      });
      await pushOpen?.cancel();
      pushOpen = FirebaseMessaging.onMessageOpenedApp.listen(openPush);
      await pushForeground?.cancel();
      pushForeground = FirebaseMessaging.onMessage.listen((m) {
        if (m.data['kind'] == 'update') {
          checkUpdate(manual: true);
          return;
        }
        // Application ouverte : un bandeau « titre — corps ».
        final title = m.notification?.title, body = m.notification?.body;
        final text = [
          if (title != null && title != 'Foyer') title,
          ?body,
        ].join(' — ');
        message(text.isEmpty ? 'Nouvelle activité' : text);
        refresh();
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) await openPush(initial);
    } catch (e) {
      message('Notifications non disponibles : $e');
    }
  }

  Future<void> openPush(RemoteMessage m) async {
    if (m.data['kind'] == 'update') {
      await checkUpdate(manual: true);
      return;
    }
    await refresh();
    if (!mounted || data == null) return;
    final ticket = maps(data!['tickets'])
        .where((t) => t['id'] == m.data['ticketId'])
        .firstOrNull;
    if (ticket != null) {
      await openTicket(ticket);
    } else {
      setState(() => tab = 0);
    }
  }

  Future<void> serverDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => ServerAddressDialog(initialValue: api.base),
    );
    if (!mounted) return;
    if (result != null) {
      try {
        await api.setServer(result);
        if (mounted) setState(() => data = null);
        await refresh();
      } catch (e) {
        message(e);
      }
    }
  }

  Future<void> openTicket([Map<String, dynamic>? ticket]) async {
    if (data == null) return;
    final result = await Navigator.of(context).push(
      MaterialPageRoute<String>(
        builder: (_) => TicketPage(data: data!, ticket: ticket),
      ),
    );
    // « Ouvrir la liste de courses » depuis une tâche Courses.
    if (result == 'shopping' && mounted) setState(() => tab = 5);
    await refresh();
  }

  // Création rapide : un titre et quelques puces ; « Plus de détails » ouvre la fiche complète.
  Future<void> quickCreate() async {
    if (data == null) return;
    final title = TextEditingController();
    final ticket = <String, dynamic>{
      'title': '',
      'description': '',
      'kind': 'obligation',
      'priority': 'normal',
      'stageId': 'backlog',
      'startDate': null,
      'dueDate': null,
      'assignees': <String>[],
      'performers': <String>[],
      'tagIds': <String>[],
      'checklist': <Map<String, dynamic>>[],
      'comments': <Map<String, dynamic>>[],
      'images': <Map<String, dynamic>>[],
      'history': <Map<String, dynamic>>[],
      'version': 0,
    };
    final members = maps(data!['members']);
    final me = data!['me']['id'];
    final shortcuts = byUse(data!['shortcuts']);
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    String iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => KeyboardBack(
        child: StatefulBuilder(
          builder: (c, change) {
            Widget chip({
              required IconData icon,
              required String label,
              required bool active,
              required List<(String, Object?)> options,
              required void Function(Object?) onPick,
            }) => PopupMenuButton<int>(
              tooltip: label,
              onSelected: (i) => change(() => onPick(options[i].$2)),
              itemBuilder: (_) => [
                for (final (i, (name, _)) in options.indexed)
                  PopupMenuItem(value: i, child: Text(name)),
              ],
              child: IgnorePointer(
                child: FilterPill(
                  label: label,
                  icon: icon,
                  selected: active,
                  onTap: () {},
                ),
              ),
            );
            final due = DateTime.tryParse(ticket['dueDate'] ?? '');
            final who = strings(ticket['assignees']);
            final tag = maps(data!['tags'])
                .where((g) => strings(ticket['tagIds']).contains(g['id']))
                .firstOrNull;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 + MediaQuery.viewInsetsOf(c).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (shortcuts.isNotEmpty) ...[
                    Text(
                      'RACCOURCIS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                        color: Theme.of(c).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: shortcuts.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => ShortcutChip(
                          shortcut: shortcuts[i],
                          today: day,
                          onTap: () => Navigator.pop(
                            c,
                            'shortcut:${shortcuts[i]['id']}',
                          ),
                          // Appui long : on préremplit pour étoffer avant de créer.
                          onLongPress: () => change(() {
                            final s = shortcuts[i];
                            title.text = s['title'].toString();
                            ticket['shortcutId'] = s['id'];
                            ticket['description'] = s['description'] ?? '';
                            ticket['kind'] = s['kind'];
                            ticket['priority'] = s['priority'];
                            ticket['tagIds'] = strings(s['tagIds']);
                            ticket['checklist'] = [
                              for (final (k, text) in strings(
                                s['checklist'],
                              ).indexed)
                                {'id': 's$k', 'text': text, 'done': false},
                            ];
                            final d = s['dueInDays'] as int?;
                            ticket['dueDate'] = d == null
                                ? null
                                : iso(day.add(Duration(days: d)));
                            ticket['assignees'] = switch (s['assign']) {
                              'none' => <String>[],
                              'member' => [s['assigneeId'].toString()],
                              _ => [me.toString()],
                            };
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'Nouvelle tâche',
                    style: TextStyle(
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextField(
                    controller: title,
                    autofocus: true,
                    maxLength: 160,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      fontFamily: tokensOf(c).displayFont,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Qu’est-ce qu’on a en tête ?',
                      counterText: '',
                    ),
                    onSubmitted: (_) => Navigator.pop(c, 'create'),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    runSpacing: 8,
                    children: [
                      chip(
                        icon: Icons.event_outlined,
                        label: due == null
                            ? 'Quand ?'
                            : relativeDay(due, today),
                        active: due != null,
                        options: [
                          ('Sans date', null),
                          ('Aujourd’hui', day),
                          ('Demain', day.add(const Duration(days: 1))),
                          (
                            'Dans une semaine',
                            day.add(const Duration(days: 7)),
                          ),
                        ],
                        onPick: (d) => ticket['dueDate'] = d == null
                            ? null
                            : iso(d as DateTime),
                      ),
                      chip(
                        icon: Icons.person_outline,
                        label: who.isEmpty
                            ? 'Qui ?'
                            : who
                                  .map(
                                    (id) => id == me ? 'Moi' : memberName(id),
                                  )
                                  .join(' + '),
                        active: who.isNotEmpty,
                        options: [
                          ('Personne pour l’instant', <String>[]),
                          ('Moi', [me]),
                          for (final m in members.where((m) => m['id'] != me))
                            (m['name'].toString(), [m['id']]),
                          if (members.length > 1)
                            ('Nous deux', [for (final m in members) m['id']]),
                        ],
                        onPick: (v) =>
                            ticket['assignees'] = List<String>.from(v as List),
                      ),
                      chip(
                        icon: Icons.auto_awesome_outlined,
                        label: ticket['kind'] == 'wish'
                            ? 'Envie'
                            : 'Obligation',
                        active: ticket['kind'] == 'wish',
                        options: [
                          ('Obligation', 'obligation'),
                          ('Envie', 'wish'),
                        ],
                        onPick: (k) => ticket['kind'] = k,
                      ),
                      chip(
                        icon: Icons.flag_outlined,
                        label: ticket['priority'] == 'normal'
                            ? 'Priorité'
                            : priorityName(ticket['priority']),
                        active: ticket['priority'] != 'normal',
                        options: [
                          for (final p in ['low', 'normal', 'high', 'urgent'])
                            (priorityName(p), p),
                        ],
                        onPick: (p) => ticket['priority'] = p,
                      ),
                      chip(
                        icon: Icons.sell_outlined,
                        label: tag == null ? 'Tag' : tag['name'].toString(),
                        active: tag != null,
                        options: [
                          ('Aucun', null),
                          for (final g in maps(data!['tags']))
                            (g['name'].toString(), g['id']),
                        ],
                        onPick: (id) => ticket['tagIds'] = [?id as String?],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(c, 'details'),
                        child: const Text('Plus de détails'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(c, 'create'),
                          child: const Text('Créer'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    ticket['title'] = title.text.trim();
    title.dispose();
    if (choice != null && choice.startsWith('shortcut:')) {
      final s = shortcuts.firstWhere((s) => s['id'] == choice.substring(9));
      await launchShortcut(s);
      return;
    }
    if (choice == 'details') {
      await openTicket(ticket);
      return;
    }
    if (choice != 'create') return;
    if (ticket['title'].toString().isEmpty) {
      message('Donnez un titre à cette tâche.');
      return;
    }
    try {
      await api.call('POST', '/api/v1/tickets', {
        for (final key in [
          'title',
          'description',
          'kind',
          'priority',
          'stageId',
          'startDate',
          'dueDate',
          'assignees',
          'performers',
          'tagIds',
          'checklist',
        ])
          key: ticket[key],
        if (ticket['shortcutId'] != null) 'shortcutId': ticket['shortcutId'],
      });
      message('Tâche créée.');
    } catch (e) {
      message(e);
    }
    await refresh();
  }

  Future<void> launchShortcut(Map<String, dynamic> s) async {
    if (s['openTicketId'] != null) {
      final again = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('« ${s['title']} » est déjà à faire'),
          content: const Text('En ajouter une autre quand même ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Non'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('En ajouter une'),
            ),
          ],
        ),
      );
      if (again != true) return;
    }
    // Raccourci Courses : proposer d’y mettre la liste en cours (brouillon non programmé).
    final draft = maps(
      maps(data?['shopping']?['lists'])
          .where((l) => l['id'] == 'draft')
          .firstOrNull?['items'],
    );
    var withList = false;
    if (s['seedKey'] == 'groceries' && draft.isNotEmpty && mounted) {
      final load = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(
            'Une liste en cours (${plural(draft.length, 'article')})',
          ),
          content: const Text('La mettre dans cette tâche ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Non'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Oui, la charger'),
            ),
          ],
        ),
      );
      if (load == null) return;
      withList = load;
    }
    try {
      final t = await api.call(
        'POST',
        '/api/v1/shortcuts/${s['id']}/launch${withList ? '?withList=true' : ''}',
      );
      await refresh();
      messenger.currentState?.showSnackBar(
        undoSnackBar('« ${s['title']} » ajoutée.', () async {
          try {
            await api.call('POST', '/api/v1/tickets/${t['id']}/undo-launch');
          } catch (e) {
            message(e);
          }
          await refresh();
        }),
      );
    } catch (e) {
      message(e);
    }
  }

  String memberName(String who) =>
      maps(data?['members'])
          .where((m) => m['id'] == who)
          .map((m) => m['name'].toString())
          .firstOrNull ??
      (who == 'system' ? 'Automatisation' : who);
  List<Map<String, dynamic>> visible() {
    if (data == null) return [];
    return maps(data!['tickets']).where((t) {
      final stage = t['stageId'];
      final closed = stage == 'done' || stage == 'abandoned';
      final ids = tab == 0
          ? strings(data!['todayIds'])
          : strings(data!['weekIds']);
      final inTab = switch (tab) {
        0 || 1 => ids.contains(t['id']),
        2 => !closed && stage != 'backlog',
        3 => stage == 'backlog',
        _ => closed,
      };
      if (!inTab) return false;
      final people = tab == 4
          ? strings(t['performers'])
          : strings(t['assignees']);
      if (person == 'none' && people.isNotEmpty) return false;
      if (person != 'all' && person != 'none' && !people.contains(person)) {
        return false;
      }
      if (tag != 'all' && !strings(t['tagIds']).contains(tag)) return false;
      if (tab == 3 && backlogKind != 'all') {
        if (backlogKind == 'dated'
            ? t['startDate'] == null
            : t['kind'] != backlogKind) {
          return false;
        }
      }
      if (tab == 4 && (period == '30' || period == '90')) {
        final when = DateTime.tryParse(t['closedAt'] ?? '');
        final limit = DateTime.now().subtract(
          Duration(days: int.parse(period)),
        );
        if (when == null || when.isBefore(limit)) return false;
      }
      if (tab == 4) {
        final when = DateTime.tryParse(t['closedAt'] ?? '');
        if (historyFrom != null &&
            (when == null || when.isBefore(historyFrom!))) {
          return false;
        }
        if (historyTo != null &&
            (when == null ||
                !when.isBefore(historyTo!.add(const Duration(days: 1))))) {
          return false;
        }
      }
      final text =
          '${t['title']} ${t['description']} ${maps(t['comments']).map((c) => c['text']).join(' ')}'
              .toLowerCase();
      return text.contains(query.toLowerCase());
    }).toList()..sort((a, b) {
      final weights = {'urgent': 0, 'high': 1, 'normal': 2, 'low': 3};
      return (weights[a['priority']] ?? 2).compareTo(
        weights[b['priority']] ?? 2,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.cottage_rounded,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Foyer',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Un endroit pour nos idées.\nUn peu plus de place dans nos têtes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, height: 1.5),
                    ),
                    const SizedBox(height: 32),
                    if (loading)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      // Pas de connexion Google sur la démonstration publique.
                      if (config['publicDemo'] != true)
                        FilledButton.icon(
                          onPressed: signing || api.base.isEmpty
                              ? null
                              : () => login(),
                          icon: const Icon(Icons.login),
                          label: Text(
                            signing ? 'Connexion…' : 'Continuer avec Google',
                          ),
                        ),
                      if (config['demo'] == true) ...[
                        const SizedBox(height: 16),
                        Text(
                          config['publicDemo'] == true
                              ? 'Démonstration · données fictives, remises à zéro chaque nuit.\nChoisissez qui vous voulez être :'
                              : 'Démonstration locale · données fictives',
                          textAlign: TextAlign.center,
                        ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => login(demo: 0),
                              child: const Text('Camille'),
                            ),
                            TextButton(
                              onPressed: () => login(demo: 1),
                              child: const Text('Alex'),
                            ),
                          ],
                        ),
                      ],
                      if (!kIsWeb)
                        TextButton(
                          onPressed: serverDialog,
                          child: const Text('Configurer le serveur'),
                        ),
                      TextButton(
                        onPressed: refresh,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width > 900;
    final today =
        DateTime.tryParse(data!['today'].toString()) ?? DateTime.now();
    final subtitles = [
      headerDay(today),
      'Les jours qui viennent',
      'Chacun sait où on en est',
      'Plus tard, sans pression',
      'Ce qu’on a fait, et ce qu’on a décidé',
      'Ce qu’il faut rapporter',
    ];
    final tickets = visible();
    const views = [
      (Icons.wb_sunny_outlined, 'Aujourd’hui'),
      (Icons.date_range_outlined, 'Semaine'),
      (Icons.view_kanban_outlined, 'Tableau'),
      (Icons.inventory_2_outlined, 'Backlog'),
      (Icons.history, 'Historique'),
      (Icons.shopping_basket_outlined, 'Courses'),
    ];
    final members = maps(data!['members']);
    final me = Map<String, dynamic>.from(data!['me']);
    final meIndex = members.indexWhere((m) => m['id'] == me['id']);
    final selectedTag = maps(data!['tags'])
        .where((t) => t['id'] == tag)
        .firstOrNull;
    final rows = tokensOf(context).rows;
    return Scaffold(
      floatingActionButton: tab == 5
          ? null
          : FloatingActionButton(
              tooltip: 'Une nouvelle tâche',
              shape: const CircleBorder(),
              onPressed: quickCreate,
              child: const Icon(Icons.add, size: 28),
            ),
      bottomNavigationBar: wide
          ? null
          : FloatingNav(
              index: tab,
              items: views,
              onSelected: (i) => setState(() => tab = i),
            ),
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final (icon, label) in views)
                    NavigationRailDestination(
                      icon: Icon(icon),
                      label: Text(label),
                    ),
                ],
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ScreenHeader(
                      title: views[tab].$2,
                      subtitle: subtitles[tab],
                      searching: searching,
                      // Courses a sa propre recherche d’ingrédients.
                      onSearch: tab == 5
                          ? null
                          : () => setState(() {
                              searching = !searching;
                              if (!searching) query = '';
                            }),
                      profile: IconButton(
                        tooltip: 'Réglages',
                        onPressed: () => settingsDialog(),
                        icon: ExcludeSemantics(
                          child: MemberAvatar(
                            name: me['name'].toString(),
                            index: meIndex < 0 ? 0 : meIndex,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                    if (searching && tab != 5)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: TextField(
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Rechercher dans cette vue…',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => query = v),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (error != null)
                            MaterialBanner(
                              content: Text(error!),
                              actions: [
                                TextButton(
                                  onPressed: refresh,
                                  child: const Text('Réessayer'),
                                ),
                              ],
                            ),
                          if (update != null && !updateDismissed)
                            MaterialBanner(
                              leading: const Icon(Icons.system_update_outlined),
                              content: Text(
                                'Mise à jour de Foyer disponible (build ${update!.versionCode}).',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      setState(() => updateDismissed = true),
                                  child: const Text('Plus tard'),
                                ),
                                FilledButton(
                                  onPressed: installingUpdate
                                      ? null
                                      : installUpdate,
                                  child: Text(
                                    installingUpdate
                                        ? 'Téléchargement…'
                                        : 'Installer',
                                  ),
                                ),
                              ],
                            ),
                          if (data!['demo'] == true)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.science_outlined,
                                    size: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Démonstration : données fictives, remises à zéro chaque nuit.',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (data!['maintenance'] == true)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'Maintenance en cours : modifications temporairement suspendues.',
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (tab != 5) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: filterPills(members, me, selectedTag),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: tab == 5
                          ? ShoppingView(
                              focusSearch: shoppingSearch,
                              data: data!,
                              api: api,
                              onChanged: refresh,
                              onOpenTicket: openTicket,
                            )
                          : tab == 2
                          ? board(tickets)
                          : RefreshIndicator(
                              onRefresh: refresh,
                              child: ListView(
                                padding: EdgeInsets.fromLTRB(
                                  0,
                                  rows ? 0 : 4,
                                  0,
                                  100,
                                ),
                                children: listFor(tickets, members, today),
                              ),
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

  bool isLate(Map<String, dynamic> t) =>
      t['dueDate'] != null &&
      t['dueDate'].toString().compareTo(data!['today'].toString()) < 0 &&
      t['stageId'] != 'done' &&
      t['stageId'] != 'abandoned';

  // Jour de rattachement dans la semaine : échéance, sinon début ; retard et « en cours » sans date = aujourd’hui.
  DateTime weekKey(Map<String, dynamic> t, DateTime today) {
    final d = DateTime.tryParse(
      (t['dueDate'] ?? t['startDate'] ?? '').toString(),
    );
    final day = DateTime(today.year, today.month, today.day);
    return d == null || d.isBefore(day)
        ? day
        : DateTime(d.year, d.month, d.day);
  }

  List<Widget> filterPills(
    List<Map<String, dynamic>> members,
    Map<String, dynamic> me,
    Map<String, dynamic>? selectedTag,
  ) {
    FilterPill pill(String label, bool selected, VoidCallback onTap) =>
        FilterPill(label: label, selected: selected, onTap: onTap);
    return [
      if (tab == 3)
        for (final (id, label) in [
          ('all', 'Tout'),
          ('obligation', 'Obligations'),
          ('wish', 'Envies'),
          ('dated', 'Avec date'),
        ])
          pill(
            label,
            backlogKind == id,
            () => setState(() => backlogKind = id),
          ),
      if (tab == 4) ...[
        for (final (id, label) in [
          ('30', '30 jours'),
          ('90', '3 mois'),
          ('all', 'Tout'),
        ])
          pill(
            label,
            period == id,
            () => setState(() {
              period = id;
              historyFrom = historyTo = null;
            }),
          ),
        pill(
          period == 'custom' && historyFrom != null
              ? '${dateLabel(historyFrom!.toIso8601String())} → ${dateLabel(historyTo!.toIso8601String())}'
              : 'Période…',
          period == 'custom',
          choosePeriod,
        ),
      ],
      if (tab != 3) ...[
        if (tab != 4)
          pill(
            'Tout le foyer',
            person == 'all',
            () => setState(() => person = 'all'),
          ),
        // « Moi » d’abord, puis l’autre membre.
        for (final m in [
          ...members.where((m) => m['id'] == me['id']),
          ...members.where((m) => m['id'] != me['id']),
        ])
          pill(
            m['id'] == me['id'] ? 'Moi' : m['name'].toString(),
            person == m['id'],
            () => setState(() => person = person == m['id'] ? 'all' : m['id']),
          ),
        pill(
          tab == 4 ? 'Sans réalisation' : 'Sans resp.',
          person == 'none',
          () => setState(() => person = person == 'none' ? 'all' : 'none'),
        ),
      ],
      PopupMenuButton<String>(
        tooltip: 'Filtrer par tag',
        initialValue: tag,
        onSelected: (v) => setState(() => tag = v),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'all', child: Text('Tous les tags')),
          for (final t in maps(data!['tags']))
            PopupMenuItem(value: t['id'] as String, child: Text(t['name'])),
        ],
        child: IgnorePointer(
          child: FilterPill(
            label: selectedTag == null
                ? 'Tags'
                : selectedTag['name'].toString(),
            icon: Icons.sell_outlined,
            selected: selectedTag != null,
            onTap: () {},
          ),
        ),
      ),
    ];
  }

  Future<void> choosePeriod() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: historyFrom == null
          ? null
          : DateTimeRange(start: historyFrom!, end: historyTo!),
    );
    if (range != null) {
      setState(() {
        period = 'custom';
        historyFrom = range.start;
        historyTo = range.end;
      });
    }
  }

  List<Widget> listFor(
    List<Map<String, dynamic>> tickets,
    List<Map<String, dynamic>> members,
    DateTime today,
  ) {
    final c = Theme.of(context).colorScheme;
    Widget padded(Widget w) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: w);
    List<Widget> section(
      String label,
      List<Map<String, dynamic>> items, [
      Color? color,
    ]) => items.isEmpty
        ? []
        : [
            padded(SectionLabel(label, items.length, color: color)),
            for (final t in items) padded(ticketCard(t)),
          ];
    final top = <Widget>[];
    var shown = tickets;
    switch (tab) {
      case 0:
        final late = tickets.where(isLate).toList();
        top.add(
          SummaryTiles(
            total: tickets.length,
            late: late.length,
            lateOnly: lateOnly,
            onLate: () => setState(() => lateOnly = !lateOnly),
            people: [
              for (final (i, m) in members.indexed)
                (
                  m['name'].toString(),
                  i,
                  tickets
                      .where((t) => strings(t['assignees']).contains(m['id']))
                      .length,
                ),
            ],
          ),
        );
        shown = lateOnly ? late : tickets;
        final body = [
          ...section('En retard', shown.where(isLate).toList(), c.error),
          ...section('Aujourd’hui', shown.where((t) => !isLate(t)).toList()),
        ];
        return [...top, if (body.isEmpty) empty() else ...body];
      case 1:
        final days = weekOf(today);
        final all = maps(data!['tickets'])
            .where((t) => strings(data!['weekIds']).contains(t['id']))
            .toList();
        top.add(
          DayStrip(
            today: today,
            selected: weekDay,
            onSelect: (d) => setState(() => weekDay = d),
            days: [
              for (final d in days)
                (d, all.where((t) => weekKey(t, today) == d).length),
            ],
          ),
        );
        final body = <Widget>[
          for (final d in days.where((d) => weekDay == null || d == weekDay))
            ...section(
              d == DateTime(today.year, today.month, today.day)
                  ? 'Aujourd’hui · ${headerDay(d).toLowerCase()}'
                  : headerDay(d),
              tickets.where((t) => weekKey(t, today) == d).toList(),
            ),
        ];
        return [...top, if (body.isEmpty) empty() else ...body];
      case 3:
        final dated = tickets.where((t) => t['startDate'] != null).toList()
          ..sort(
            (a, b) =>
                a['startDate'].toString().compareTo(b['startDate'].toString()),
          );
        final body = [
          ...section('Commence bientôt', dated),
          ...section(
            'Un jour',
            tickets.where((t) => t['startDate'] == null).toList(),
          ),
        ];
        return body.isEmpty ? [empty()] : body;
      default:
        final byWeek = <String, List<Map<String, dynamic>>>{};
        final sorted = [...tickets]
          ..sort(
            (a, b) => (b['closedAt'] ?? '').toString().compareTo(
              (a['closedAt'] ?? '').toString(),
            ),
          );
        for (final t in sorted) {
          final when = DateTime.tryParse(t['closedAt']?.toString() ?? '');
          byWeek
              .putIfAbsent(
                when == null ? 'Sans date' : weekLabel(when.toLocal(), today),
                () => [],
              )
              .add(t);
        }
        final body = [
          for (final e in byWeek.entries) ...section(e.key, e.value),
        ];
        return body.isEmpty ? [empty()] : body;
    }
  }

  Widget empty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.spa_outlined,
          size: 52,
          color: Theme.of(context).colorScheme.primary,
        ),
        SizedBox(height: 16),
        Text(
          'De la place pour la suite.',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 8),
        Text('Aucune tâche ne correspond à cette vue.'),
      ],
    ),
  );
  // Déplacer une carte d’étape : même enregistrement que la fiche, avec contrôle de version.
  Future<void> moveTicket(Map<String, dynamic> t, String stageId) async {
    try {
      await api.call('PUT', '/api/v1/tickets/${t['id']}', {
        for (final key in [
          'title',
          'description',
          'kind',
          'priority',
          'startDate',
          'dueDate',
          'assignees',
          'performers',
          'tagIds',
          'checklist',
          'version',
        ])
          key: t[key],
        'stageId': stageId,
      });
    } catch (e) {
      message(e);
    }
    await refresh();
  }

  Widget board(List<Map<String, dynamic>> tickets) {
    final stages = maps(data!['stages'])
      ..sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    if (stages.isEmpty) return empty();
    List<Map<String, dynamic>> itemsOf(String id) =>
        tickets.where((t) => t['stageId'] == id).toList();
    Widget card(Map<String, dynamic> t, int i) => SwipeToMove(
      previous: i > 0 ? stages[i - 1]['name'].toString() : null,
      next: i < stages.length - 1 ? stages[i + 1]['name'].toString() : null,
      onPrevious: i > 0 ? () => moveTicket(t, stages[i - 1]['id']) : null,
      onNext: i < stages.length - 1
          ? () => moveTicket(t, stages[i + 1]['id'])
          : null,
      child: ticketCard(t),
    );
    // Grand écran : toutes les colonnes côte à côte.
    if (MediaQuery.sizeOf(context).width > 900) {
      return ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
        children: [
          for (final (i, s) in stages.indexed)
            SizedBox(
              width: 320,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionLabel(s['name'].toString(), itemsOf(s['id']).length),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final t in itemsOf(s['id'])) card(t, i),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    // Mobile : une étape à la fois.
    final index = stages.indexWhere((s) => s['id'] == boardStage);
    final i = index < 0 ? 0 : index;
    final items = itemsOf(stages[i]['id']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: StageSelector(
            selected: stages[i]['id'],
            onSelect: (id) => setState(() => boardStage = id),
            stages: [
              for (final s in stages)
                (
                  s['id'].toString(),
                  s['name'].toString(),
                  itemsOf(s['id']).length,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              children: [
                if (items.isEmpty)
                  empty()
                else ...[
                  for (final t in items) card(t, i),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Glisser une carte vers la gauche ou la droite pour changer d’étape.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget ticketCard(Map<String, dynamic> t) {
    final today =
        DateTime.tryParse(data!['today'].toString()) ?? DateTime.now();
    final closed = t['stageId'] == 'done' || t['stageId'] == 'abandoned';
    final due = DateTime.tryParse(t['dueDate']?.toString() ?? '');
    final start = DateTime.tryParse(t['startDate']?.toString() ?? '');
    final overdue =
        due != null &&
        t['dueDate'].toString().compareTo(data!['today'].toString()) < 0 &&
        !closed;
    final members = maps(data!['members']);
    final people = [
      for (final id in strings(tab == 4 ? t['performers'] : t['assignees']))
        (memberName(id), members.indexWhere((m) => m['id'] == id)),
    ].where((p) => p.$2 >= 0).toList();
    final stage =
        maps(data!['stages'])
            .where((s) => s['id'] == t['stageId'])
            .map((s) => s['name'].toString())
            .firstOrNull ??
        {'backlog': 'Backlog'}[t['stageId']];
    final firstTag = maps(data!['tags'])
        .where((tag) => strings(t['tagIds']).contains(tag['id']))
        .map((tag) => tag['name'].toString())
        .firstOrNull;
    final closedAt = DateTime.tryParse(t['closedAt']?.toString() ?? '');
    final when = closed
        ? (closedAt == null
              ? null
              : '${t['stageId'] == 'done' ? 'Fait' : 'Abandonné'} ${relativeDay(closedAt.toLocal(), today).toLowerCase()}')
        : due != null
        ? relativeDay(due, today)
        : start != null
        ? 'Dès ${relativeDay(start, today).toLowerCase()}'
        : null;
    final check = maps(t['checklist']);
    return TaskTile(
      onTap: () => openTicket(t),
      task: TaskView(
        title: t['title'].toString(),
        meta: [?when, if (tab != 2 && !closed) ?stage, ?firstTag].join(' · '),
        badge: overdue
            ? TaskBadge.late
            : closed
            ? null
            : switch (t['priority']) {
                'urgent' => TaskBadge.urgent,
                'high' => TaskBadge.high,
                _ => null,
              },
        done: check.where((c) => c['done'] == true).length,
        total: check.length,
        comments: maps(t['comments']).length,
        people: people,
        wish: t['kind'] == 'wish',
        repeat:
            activeRepeat(
              maps(data!['shortcuts'])
                  .where((s) => s['id'] == t['shortcutId'])
                  .firstOrNull,
            ) !=
            null,
      ),
    );
  }

  Future<void> appearanceDialog() async {
    if (choosingPalette) return;
    choosingPalette = true;
    final initial = selectedAppearance.value;
    try {
      final choice = await Navigator.push<AppAppearance>(
        context,
        MaterialPageRoute(builder: (_) => AppearancePage(initial: initial)),
      );
      if (choice != null && choice != initial) {
        final me = await api.call('PUT', '/api/v1/appearance', choice.toJson());
        if (mounted && data != null) setState(() => data!['me'] = me);
      }
    } catch (e) {
      message(e);
    } finally {
      choosingPalette = false;
      selectedAppearance.value = AppAppearance.fromMember(data?['me']);
    }
  }

  Future<void> settingsDialog() async {
    final me = Map<String, dynamic>.from(data!['me']);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, change) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'À votre rythme',
                    style: Theme.of(c).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Résumé quotidien'),
                    subtitle: Text(
                      'Chaque matin à ${me['digestTime']} · les rappels de la nuit attendent cette heure',
                    ),
                    value: me['digestEnabled'],
                    onChanged: (v) => change(() => me['digestEnabled'] = v),
                  ),
                  if (Updater.supported)
                    TextButton.icon(
                      icon: const Icon(Icons.tune),
                      label: const Text('Gérer les notifications par type'),
                      onPressed: () => Updater.openNotificationSettings()
                          .catchError((Object e) => message(e)),
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: const Text('Choisir l’heure'),
                    onPressed: () async {
                      final p = me['digestTime'].toString().split(':');
                      final selected = await showTimePicker(
                        context: c,
                        initialTime: TimeOfDay(
                          hour: int.parse(p[0]),
                          minute: int.parse(p[1]),
                        ),
                      );
                      if (selected != null) {
                        change(
                          () => me['digestTime'] =
                              '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
                        );
                      }
                    },
                  ),
                  FilledButton(
                    onPressed: () async {
                      try {
                        await api.call('PUT', '/api/v1/preferences', {
                          'digestTime': me['digestTime'],
                          'digestEnabled': me['digestEnabled'],
                        });
                        if (c.mounted) Navigator.pop(c);
                        await refresh();
                      } catch (e) {
                        message(e);
                      }
                    },
                    child: const Text('Enregistrer'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('Apparence'),
                    subtitle: Text(
                      presetOf(AppAppearance.fromMember(me))?.name ??
                          paletteById(me['paletteId']).name,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(c);
                      appearanceDialog();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.bolt_outlined),
                    title: const Text('Raccourcis'),
                    subtitle: Text(
                      plural(maps(data!['shortcuts']).length, 'raccourci'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      Navigator.pop(c);
                      await Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ShortcutsPage(api: api, data: data!),
                        ),
                      );
                      await refresh();
                    },
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(c);
                      stagesDialog();
                    },
                    child: const Text('Personnaliser les étapes'),
                  ),
                  if (!kIsWeb)
                    TextButton(
                      onPressed: setupPush,
                      child: const Text(
                        'Activer / vérifier les notifications Android',
                      ),
                    ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(c);
                      sessionsDialog();
                    },
                    child: const Text('Appareils connectés'),
                  ),
                  if (Updater.supported)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(c);
                        checkUpdate(manual: true);
                      },
                      child: const Text('Rechercher une mise à jour'),
                    ),
                  if (!kIsWeb)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(c);
                        serverDialog();
                      },
                      child: const Text(
                        'Changer de serveur (reconnexion requise)',
                      ),
                    ),
                  TextButton(
                    onPressed: () async {
                      try {
                        await api.call('POST', '/api/v1/logout');
                        await api.clearSession();
                        await clearWidgets();
                        if (c.mounted) Navigator.pop(c);
                        if (mounted) setState(() => data = null);
                      } catch (e) {
                        message(e);
                      }
                    },
                    child: const Text('Se déconnecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> sessionsDialog() async {
    try {
      final sessions = maps(await api.call('GET', '/api/v1/sessions'));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Appareils connectés'),
          content: SizedBox(
            width: 450,
            child: ListView(
              shrinkWrap: true,
              children: sessions
                  .map(
                    (s) => ListTile(
                      title: Text(
                        '${s['deviceName']}${s['current'] == true ? ' · cet appareil' : ''}',
                      ),
                      subtitle: Text('Depuis ${timeLabel(s['createdAt'])}'),
                      trailing: IconButton(
                        tooltip: 'Révoquer',
                        icon: const Icon(Icons.logout),
                        onPressed: () async {
                          await api.call(
                            'DELETE',
                            '/api/v1/sessions/${s['id']}',
                          );
                          if (c.mounted) Navigator.pop(c);
                          await refresh();
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (e) {
      message(e);
    }
  }

  Future<void> stagesDialog() async {
    final stages = maps(data!['stages']);
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, change) => AlertDialog(
          title: const Text('Nos étapes'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...stages.asMap().entries.map((entry) {
                    final i = entry.key;
                    final s = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          TextFormField(
                            initialValue: s['name'],
                            decoration: const InputDecoration(labelText: 'Nom'),
                            onChanged: (v) => s['name'] = v,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: s['category'],
                                  onChanged: s['id'] == 'todo'
                                      ? null
                                      : (v) => change(() => s['category'] = v),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'todo',
                                      child: Text('À faire'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'doing',
                                      child: Text('En cours'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'waiting',
                                      child: Text('En attente'),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: i == 0
                                    ? null
                                    : () => change(() {
                                        final moved = stages.removeAt(i);
                                        stages.insert(i - 1, moved);
                                      }),
                                icon: const Icon(Icons.arrow_upward),
                              ),
                              IconButton(
                                onPressed: s['id'] == 'todo'
                                    ? null
                                    : () => change(() => stages.removeAt(i)),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () => change(
                      () => stages.add({
                        'id': id(),
                        'name': 'Nouvelle étape',
                        'category': 'todo',
                        'order': stages.length,
                      }),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une étape'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await api.call('PUT', '/api/v1/stages', {
                    'stages': stages,
                    'revision': data!['revision'],
                  });
                  if (c.mounted) Navigator.pop(c);
                  await refresh();
                } catch (e) {
                  message(e);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class TicketPage extends StatefulWidget {
  final Map<String, dynamic> data;
  final Map<String, dynamic>? ticket;
  const TicketPage({super.key, required this.data, this.ticket});
  @override
  State<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<TicketPage> {
  late Map<String, dynamic> t;
  late final TextEditingController title, description;
  final comment = TextEditingController();
  late List<Map<String, dynamic>> tags;
  bool saving = false, details = false, dirty = false;
  final imageCache = <String, Future<Uint8List>>{};
  @override
  void initState() {
    super.initState();
    t = widget.ticket == null
        ? {
            'title': '',
            'description': '',
            'kind': 'obligation',
            'priority': 'normal',
            'stageId': 'backlog',
            'startDate': null,
            'dueDate': null,
            'assignees': <String>[],
            'performers': <String>[],
            'tagIds': <String>[],
            'checklist': <Map<String, dynamic>>[],
            'comments': <Map<String, dynamic>>[],
            'images': <Map<String, dynamic>>[],
            'history': <Map<String, dynamic>>[],
            'version': 0,
          }
        : Map<String, dynamic>.from(jsonDecode(jsonEncode(widget.ticket)));
    title = TextEditingController(text: t['title']);
    description = TextEditingController(text: t['description']);
    tags = maps(widget.data['tags']);
    details = widget.ticket != null;
    title.addListener(() {
      if (mounted) setState(() => dirty = true);
    });
    description.addListener(() {
      if (mounted) setState(() => dirty = true);
    });
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    comment.dispose();
    super.dispose();
  }

  String name(String id) =>
      maps(widget.data['members'])
          .where((m) => m['id'] == id)
          .map((m) => m['name'].toString())
          .firstOrNull ??
      (id == 'system' ? 'Automatisation' : id);
  Future<void> save({bool close = true}) async {
    if (saving) return;
    if (title.text.trim().isEmpty) {
      message('Donnez un titre à cette tâche.');
      return;
    }
    setState(() => saving = true);
    try {
      final body = {
        for (final key in [
          'kind',
          'priority',
          'stageId',
          'startDate',
          'dueDate',
          'assignees',
          'performers',
          'tagIds',
          'checklist',
          'version',
        ])
          key: t[key],
        'title': title.text,
        'description': description.text,
      };
      final result = Map<String, dynamic>.from(
        await api.call(
          t['id'] == null ? 'POST' : 'PUT',
          t['id'] == null ? '/api/v1/tickets' : '/api/v1/tickets/${t['id']}',
          body,
        ),
      );
      if (mounted) {
        setState(() {
          t = result;
          dirty = false;
        });
        if (close) {
          await WidgetsBinding.instance.endOfFrame;
          if (mounted) Navigator.pop(context);
        }
      }
    } catch (e) {
      message(e);
      if (e is ApiError && e.status == 409 && mounted) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Une modification plus récente existe'),
            content: const Text(
              'Vos saisies restent affichées. Fermez puis rouvrez ce ticket pour consulter la dernière version avant de les reporter.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Compris'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> datePick(String key) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(t[key] ?? '') ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        t[key] = DateFormat('yyyy-MM-dd').format(picked);
        dirty = true;
      });
    }
  }

  Future<void> addTag() async {
    var input = '';
    String color = '#557B6E';
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, change) => AlertDialog(
          title: const Text('Un nouveau tag'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => input = value,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children:
                    [
                          '#557B6E',
                          '#B86545',
                          '#9272A3',
                          '#B18A38',
                          '#427DA5',
                          '#A45273',
                        ]
                        .map(
                          (v) => ChoiceChip(
                            label: Icon(
                              Icons.circle,
                              color: Color(
                                int.parse(v.replaceFirst('#', 'FF'), radix: 16),
                              ),
                            ),
                            selected: color == v,
                            onSelected: (_) => change(() => color = v),
                          ),
                        )
                        .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final tag = Map<String, dynamic>.from(
                    await api.call('POST', '/api/v1/tags', {
                      'name': input,
                      'color': color,
                    }),
                  );
                  if (!mounted) return;
                  setState(() {
                    tags.add(tag);
                    t['tagIds'] = strings(t['tagIds'])..add(tag['id']);
                    dirty = true;
                  });
                  if (c.mounted) Navigator.pop(c);
                } catch (e) {
                  message(e);
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> addCheck() async {
    var input = '';
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ajouter à la checklist'),
        content: TextField(
          onChanged: (value) => input = value,
          autofocus: true,
          onSubmitted: (s) => Navigator.pop(c, s),
          decoration: const InputDecoration(labelText: 'Une petite étape'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, input),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (mounted && text != null && text.trim().isNotEmpty) {
      setState(() {
        t['checklist'] = maps(t['checklist'])
          ..add({'id': id(), 'text': text.trim(), 'done': false});
        dirty = true;
      });
    }
  }

  Future<void> upload() async {
    try {
      if (dirty || t['id'] == null) {
        await save(close: false);
        if (dirty || t['id'] == null) return;
      }
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (image == null) return;
      setState(() => saving = true);
      await api.image(t['id'], await image.readAsBytes(), image.name);
      await reload();
    } catch (e) {
      message(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> reload() async {
    final state = await api.call('GET', '/api/v1/state');
    final current = maps(state['tickets'])
        .firstWhere((i) => i['id'] == t['id']);
    if (mounted) setState(() => t = current);
  }

  Future<void> postComment() async {
    if (comment.text.trim().isEmpty) return;
    try {
      if (dirty) {
        await save(close: false);
        if (dirty) return;
      }
      setState(() => saving = true);
      final result = Map<String, dynamic>.from(
        await api.call('POST', '/api/v1/tickets/${t['id']}/comments', {
          'text': comment.text,
        }),
      );
      if (mounted) {
        setState(() {
          t = result;
          comment.clear();
        });
      }
    } catch (e) {
      message(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget heading(String value) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(
      value,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
  Widget memberChoices(String field) => Wrap(
    spacing: 8,
    children: maps(widget.data['members'])
        .map(
          (m) => FilterChip(
            label: Text(m['name']),
            selected: strings(t[field]).contains(m['id']),
            onSelected: (v) => setState(() {
              final list = strings(t[field]);
              v ? list.add(m['id']) : list.remove(m['id']);
              t[field] = list;
              dirty = true;
            }),
          ),
        )
        .toList(),
  );
  bool get existing => t['id'] != null;
  List<Map<String, dynamic>> get members => maps(widget.data['members']);
  List<Map<String, dynamic>> get stages =>
      maps(widget.data['stages'])
        ..sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
  String get stageName =>
      {
        'backlog': 'Backlog',
        'done': 'Terminé',
        'abandoned': 'Abandonné',
        for (final s in stages) s['id']: s['name'],
      }[t['stageId']]?.toString() ??
      '';
  String? stageOf(String category) =>
      stages.where((s) => s['category'] == category).firstOrNull?['id'];
  bool get blocked =>
      stages.any((s) => s['id'] == t['stageId'] && s['category'] == 'waiting');

  // Actions rapides : décisives, elles enregistrent tout de suite.
  Future<void> apply(
    void Function() change,
    String done, {
    bool close = false,
  }) async {
    setState(change);
    dirty = true;
    await save(close: close);
    if (!dirty) message(done);
  }

  // Tâche Courses : la checklist est la liste, rangée dans l’ordre des rayons du magasin.
  bool get shopping => t['shopping'] == true;
  List<Map<String, dynamic>> checklistItems() {
    final items = maps(t['checklist']);
    if (!shopping) return items;
    final order = [
      for (final a in maps(widget.data['shopping']?['aisles'])) a['id'],
    ];
    int rank(Map<String, dynamic> i) {
      final r = order.indexOf(i['aisle'] ?? 'other');
      return r < 0 ? order.length : r;
    }

    final ranked = items.indexed.toList()
      ..sort((a, b) {
        final r = rank(a.$2) - rank(b.$2);
        return r != 0 ? r : a.$1 - b.$1;
      });
    return [for (final e in ranked) e.$2];
  }

  List<Widget> checklistHeading() => [
    heading(shopping ? 'Liste de courses' : 'Une étape à la fois'),
    if (shopping && t['id'] != null && !closedTicket)
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () async {
            if (dirty) await save(close: false);
            if (mounted && !dirty) Navigator.pop(context, 'shopping');
          },
          icon: const Icon(Icons.shopping_basket_outlined),
          label: const Text('Ouvrir la liste de courses'),
        ),
      ),
  ];

  bool get closedTicket =>
      t['stageId'] == 'done' || t['stageId'] == 'abandoned';

  Future<void> finish() async {
    final me = widget.data['me']?['id']?.toString();
    final performers = await askPerformers(context, members, {
      ...strings(t['assignees']),
      if (strings(t['assignees']).isEmpty && me != null) me,
    });
    if (performers == null) return;
    // Courses : les articles non cochés reviennent dans la liste en cours (côté serveur).
    final left = shopping
        ? maps(t['checklist']).where((i) => i['done'] != true).length
        : 0;
    await apply(
      () {
        t['stageId'] = 'done';
        t['performers'] = performers;
      },
      left == 0
          ? 'Bravo, c’est fait.'
          : 'Bravo ! ${plural(left, 'article non acheté', 'articles non achetés')} remis dans la liste.',
      close: true,
    );
  }

  Future<void> postpone() async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final nextMonday = day.add(Duration(days: 8 - day.weekday));
    final choice = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, d) in [
              ('Demain', day.add(const Duration(days: 1))),
              ('Dans 3 jours', day.add(const Duration(days: 3))),
              ('Lundi prochain', nextMonday),
            ])
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(label),
                subtitle: Text(headerDay(d)),
                onTap: () => Navigator.pop(c, d),
              ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Choisir une date…'),
              onTap: () async {
                final d = await showDatePicker(
                  context: c,
                  initialDate: day.add(const Duration(days: 1)),
                  firstDate: day,
                  lastDate: DateTime(2100),
                );
                if (c.mounted) Navigator.pop(c, d);
              },
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    // On décale l’échéance ; à défaut la date de début si c’est la seule renseignée.
    final key = t['dueDate'] == null && t['startDate'] != null
        ? 'startDate'
        : 'dueDate';
    await apply(
      () => t[key] = DateFormat('yyyy-MM-dd').format(choice),
      'Reporté à ${relativeDay(choice, today).toLowerCase()}.',
    );
  }

  // Mémorise cette tâche comme raccourci réutilisable (sans dates précises ni avancement).
  Future<void> saveAsShortcut() async {
    final assignees = strings(t['assignees']);
    try {
      await api.call('POST', '/api/v1/shortcuts', {
        'title': title.text.trim(),
        'description': description.text.trim(),
        'kind': t['kind'],
        'priority': t['priority'],
        'tagIds': strings(t['tagIds']),
        'checklist': [
          for (final c in maps(t['checklist'])) c['text'].toString(),
        ].take(20).toList(),
        'dueInDays': t['dueDate'] == null ? null : 0,
        'assign': assignees.isEmpty
            ? 'none'
            : assignees.length == 1
            ? 'member'
            : 'launcher',
        'assigneeId': assignees.length == 1 ? assignees.first : null,
      });
      message('Raccourci « ${title.text.trim()} » enregistré.');
    } catch (e) {
      message(e);
    }
  }

  // Pas de suppression : l’historique garde la décision de ne pas faire.
  Future<void> abandon() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Abandonner cette tâche ?'),
        content: const Text(
          'Elle disparaît des listes et reste visible dans l’historique.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await apply(
        () => t['stageId'] = 'abandoned',
        'Tâche abandonnée.',
        close: true,
      );
    }
  }

  Future<void> makeTodo() async {
    final target = stageOf('todo') ?? stages.firstOrNull?['id'];
    if (target == null) return;
    await apply(() => t['stageId'] = target, 'Tâche passée à faire.');
  }

  Future<void> toggleBlocked() async {
    final target = blocked
        ? (stageOf('doing') ?? stageOf('todo'))
        : stageOf('waiting');
    if (target == null) {
      message('Aucune étape « en attente » dans vos étapes.');
      return;
    }
    await apply(
      () => t['stageId'] = target,
      blocked ? 'Tâche débloquée.' : 'Tâche marquée bloquée.',
    );
  }

  Future<void> editField(String title, Widget Function(StateSetter) body) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => StatefulBuilder(
          builder: (c, change) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(c).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  body((f) {
                    change(f);
                    setState(() {});
                  }),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Valider'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget chips(
    String field,
    List<Map<String, dynamic>> items,
    StateSetter change,
  ) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final item in items)
        FilterChip(
          label: Text(item['name']),
          selected: strings(t[field]).contains(item['id']),
          onSelected: (v) => change(() {
            final list = strings(t[field]);
            v ? list.add(item['id']) : list.remove(item['id']);
            t[field] = list;
            dirty = true;
          }),
        ),
    ],
  );

  Map<String, dynamic>? get shortcut =>
      maps(widget.data['shortcuts'])
          .where((s) => s['id'] == t['shortcutId'])
          .firstOrNull;

  Future<void> skip() async {
    try {
      await api.call('POST', '/api/v1/tickets/${t['id']}/skip');
      message('Passée cette fois : la suivante est prévue.');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      message(e);
    }
  }

  Future<void> editRepeat() async {
    final s = shortcut;
    if (s == null) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ShortcutEditor(api: api, data: widget.data, shortcut: s),
      ),
    );
  }

  List<Widget> summary() {
    final c = Theme.of(context).colorScheme;
    final repeat = activeRepeat(shortcut);
    final closed = t['stageId'] == 'done' || t['stageId'] == 'abandoned';
    return [
      Text(
        'F-${t['number']} · $stageName',
        style: TextStyle(color: c.onSurfaceVariant),
      ),
      if (repeat != null) ...[
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.repeat, size: 18, color: c.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                repeatLabel(repeat),
                style: TextStyle(color: c.onSurfaceVariant),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 4,
          children: [
            if (!closed)
              TextButton.icon(
                onPressed: saving ? null : skip,
                icon: const Icon(Icons.skip_next_outlined),
                label: const Text('Passer cette fois'),
              ),
            TextButton.icon(
              onPressed: editRepeat,
              icon: const Icon(Icons.tune),
              label: const Text('Modifier la répétition'),
            ),
          ],
        ),
      ],
      const SizedBox(height: 6),
    ];
  }

  List<Widget> actions() {
    final c = Theme.of(context).colorScheme;
    final tk = tokensOf(context);
    final closed = t['stageId'] == 'done' || t['stageId'] == 'abandoned';
    Widget action(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      bool primary = false,
    }) => Expanded(
      child: Material(
        color: primary ? c.primary : Theme.of(context).cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tk.radius - 2),
          side: primary ? BorderSide.none : BorderSide(color: c.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(tk.radius - 2),
          onTap: saving ? null : onTap,
          child: SizedBox(
            height: 66,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: primary ? c.onPrimary : c.onSurface),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: primary ? c.onPrimary : c.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Widget tile(String label, Widget value, VoidCallback onTap) => Expanded(
      child: Material(
        color: Theme.of(context).cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tk.radius - 2),
          side: BorderSide(color: c.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(tk.radius - 2),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: c.onSurfaceVariant)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 28,
                  child: Align(alignment: Alignment.centerLeft, child: value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final bold = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 16,
      color: c.onSurface,
    );
    final assignees = strings(t['assignees']);
    final check = maps(t['checklist']);
    final done = check.where((i) => i['done'] == true).length;
    final due = DateTime.tryParse(t['dueDate']?.toString() ?? '');
    final start = DateTime.tryParse(t['startDate']?.toString() ?? '');
    final selectedTags = tags
        .where((g) => strings(t['tagIds']).contains(g['id']))
        .toList();
    return [
      const SizedBox(height: 14),
      if (!closed) ...[
        Row(
          children: [
            action(Icons.check, 'C’est fait', finish, primary: true),
            const SizedBox(width: 10),
            action(Icons.event_repeat, 'Reporter', postpone),
            const SizedBox(width: 10),
            // Depuis le Backlog, l’action utile est de passer la tâche à faire.
            if (t['stageId'] == 'backlog')
              action(Icons.play_arrow_outlined, 'À faire', makeTodo)
            else
              action(
                blocked
                    ? Icons.play_arrow_outlined
                    : Icons.pause_circle_outline,
                blocked ? 'Débloquer' : 'Bloqué',
                toggleBlocked,
              ),
          ],
        ),
        const SizedBox(height: 10),
      ],
      Row(
        children: [
          tile(
            'Qui',
            assignees.isEmpty
                ? Text('Personne', style: bold)
                : Row(
                    children: [
                      for (final id in assignees)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: MemberAvatar(
                            name: name(id),
                            index: members.indexWhere((m) => m['id'] == id),
                            size: 26,
                          ),
                        ),
                      if (assignees.length == 1)
                        Flexible(
                          child: Text(
                            name(assignees.first),
                            style: bold,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
            () => editField(
              'Qui s’en occupe ?',
              (change) => chips('assignees', members, change),
            ),
          ),
          const SizedBox(width: 10),
          tile(
            'Quand',
            Text(
              due != null
                  ? relativeDay(due, DateTime.now())
                  : start != null
                  ? 'Dès ${relativeDay(start, DateTime.now()).toLowerCase()}'
                  : 'Sans date',
              style: bold,
            ),
            () => datePick('dueDate'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          tile(
            'Étapes',
            check.isEmpty
                ? Text('Aucune', style: bold)
                : Row(
                    children: [
                      Text('$done/${check.length}', style: bold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: done / check.length,
                            minHeight: 6,
                            color: c.secondaryContainer,
                            backgroundColor: c.outlineVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
            addCheck,
          ),
          const SizedBox(width: 10),
          tile(
            selectedTags.length > 1 ? 'Tags' : 'Tag',
            Text(
              selectedTags.isEmpty
                  ? 'Aucun'
                  : selectedTags.map((g) => g['name']).join(', '),
              style: bold,
              overflow: TextOverflow.ellipsis,
            ),
            () => editField(
              'Les tags',
              (change) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  chips('tagIds', tags, change),
                  TextButton.icon(
                    onPressed: () async {
                      await addTag();
                      change(() {});
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Nouveau tag'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ];
  }

  String activityDetail(Map<String, dynamic> a) {
    final action = a['action'];
    if (action == 'stage') {
      final stages = {
        'backlog': 'Backlog',
        'done': 'Terminé',
        'abandoned': 'Abandonné',
        for (final s in maps(widget.data['stages'])) s['id']: s['name'],
      };
      return a['detail']
          .toString()
          .split(' → ')
          .map((s) => stages[s] ?? s)
          .join(' → ');
    }
    if (action == 'assignees' || action == 'performers') {
      try {
        final d = jsonDecode(a['detail']);
        final before = strings(d['before']).map(name).join(' + ');
        final after = strings(d['after']).map(name).join(' + ');
        return '${action == 'performers' ? 'Réalisé par' : 'Responsables'} : ${before.isEmpty ? 'personne' : before} → ${after.isEmpty ? 'personne' : after}';
      } catch (_) {
        return 'Attribution modifiée';
      }
    }
    if (action == 'checklist') return 'Checklist mise à jour';
    return a['detail'];
  }

  @override
  Widget build(BuildContext context) {
    final stageItems = [
      {'id': 'backlog', 'name': 'Backlog'},
      ...maps(widget.data['stages']),
      {'id': 'done', 'name': 'Terminé'},
      {'id': 'abandoned', 'name': 'Abandonné / décidé de ne pas faire'},
    ];
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Quitter sans enregistrer ?'),
            content: const Text(
              'Les modifications de ce ticket ne sont pas encore enregistrées.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Continuer'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Quitter'),
              ),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          setState(() => dirty = false);
          await WidgetsBinding.instance.endOfFrame;
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(t['id'] == null ? 'Une nouvelle tâche' : ''),
          actions: [
            if (existing &&
                (t['priority'] == 'urgent' || t['priority'] == 'high'))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PriorityBadge(
                  t['priority'] == 'urgent' ? TaskBadge.urgent : TaskBadge.high,
                ),
              ),
            if (existing)
              PopupMenuButton<String>(
                tooltip: 'Plus d’actions',
                onSelected: (v) =>
                    v == 'abandon' ? abandon() : saveAsShortcut(),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'shortcut',
                    child: ListTile(
                      leading: Icon(Icons.bolt_outlined),
                      title: Text('Enregistrer comme raccourci'),
                    ),
                  ),
                  if (t['stageId'] != 'done' && t['stageId'] != 'abandoned')
                    const PopupMenuItem(
                      value: 'abandon',
                      child: ListTile(
                        leading: Icon(Icons.do_not_disturb_on_outlined),
                        title: Text('Abandonner'),
                        subtitle: Text(
                          'Décidé de ne pas faire, gardé dans l’historique',
                        ),
                      ),
                    ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: saving ? null : () => save(),
                child: Text(saving ? 'Enregistrement…' : 'Enregistrer'),
              ),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 60),
              children: [
                if (!existing) ...[
                  TextField(
                    controller: title,
                    maxLength: 160,
                    // Titre sur plusieurs lignes, sans retour à la ligne saisi.
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    autofocus: t['id'] == null,
                    style: TextStyle(
                      fontFamily: tokensOf(context).displayFont,
                      fontSize: existing ? 28 : 24,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Qu’est-ce qu’on a en tête ?',
                      counterText: '',
                      border: existing ? InputBorder.none : null,
                      enabledBorder: existing ? InputBorder.none : null,
                      filled: existing ? false : null,
                      contentPadding: existing ? EdgeInsets.zero : null,
                    ),
                  ),
                  if (!details)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TextButton.icon(
                        onPressed: () => setState(() => details = true),
                        icon: const Icon(Icons.tune),
                        label: const Text(
                          'Ajouter des détails, une date, un responsable…',
                        ),
                      ),
                    ),
                  if (details) ...[
                    heading(existing ? 'Notes' : 'L’essentiel'),
                    TextField(
                      controller: description,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 12000,
                      decoration: const InputDecoration(
                        labelText: 'Notes et contexte',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: t['stageId'],
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Avancement',
                      ),
                      items: stageItems
                          .map(
                            (s) => DropdownMenuItem(
                              value: s['id'].toString(),
                              child: Text(
                                s['name'].toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        t['stageId'] = v;
                        dirty = true;
                      }),
                    ),
                    if (t['stageId'] == 'done') ...[
                      heading('Qui l’a réalisé ?'),
                      const Text(
                        'Choix explicite, indépendant des responsables.',
                      ),
                      memberChoices('performers'),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: t['kind'],
                            decoration: const InputDecoration(
                              labelText: 'Type',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'obligation',
                                child: Text('Obligation'),
                              ),
                              DropdownMenuItem(
                                value: 'wish',
                                child: Text('Envie'),
                              ),
                            ],
                            onChanged: (v) => setState(() {
                              t['kind'] = v;
                              dirty = true;
                            }),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: t['priority'],
                            decoration: const InputDecoration(
                              labelText: 'Priorité',
                            ),
                            items: ['low', 'normal', 'high', 'urgent']
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(priorityName(p)),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() {
                              t['priority'] = v;
                              dirty = true;
                            }),
                          ),
                        ),
                      ],
                    ),
                    heading('Qui s’en occupe ?'),
                    memberChoices('assignees'),
                    heading('Quand ?'),
                    ...['startDate', 'dueDate'].map(
                      (key) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: Text(
                          key == 'startDate'
                              ? 'À faire à partir du'
                              : 'Échéance',
                        ),
                        subtitle: Text(
                          t[key] == null ? 'Sans date' : dateLabel(t[key]),
                        ),
                        onTap: () => datePick(key),
                        trailing: t[key] == null
                            ? null
                            : IconButton(
                                onPressed: () => setState(() {
                                  t[key] = null;
                                  dirty = true;
                                }),
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                    heading('Les tags'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ...tags.map(
                          (tag) => FilterChip(
                            avatar: Icon(
                              Icons.circle,
                              size: 12,
                              color: Color(
                                int.parse(
                                  tag['color'].toString().replaceFirst(
                                    '#',
                                    'FF',
                                  ),
                                  radix: 16,
                                ),
                              ),
                            ),
                            label: Text(tag['name']),
                            selected: strings(t['tagIds']).contains(tag['id']),
                            onSelected: (v) => setState(() {
                              final list = strings(t['tagIds']);
                              v ? list.add(tag['id']) : list.remove(tag['id']);
                              t['tagIds'] = list;
                              dirty = true;
                            }),
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 18),
                          label: const Text('Nouveau tag'),
                          onPressed: addTag,
                        ),
                      ],
                    ),
                    ...checklistHeading(),
                    ...checklistItems().map(
                      (item) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: item['done'],
                        title: Text(itemLabel(item)),
                        secondary: IconButton(
                          tooltip: 'Retirer',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            t['checklist'] = maps(t['checklist'])
                              ..removeWhere((c) => c['id'] == item['id']);
                            dirty = true;
                          }),
                        ),
                        onChanged: (v) => setState(() {
                          t['checklist'] = maps(t['checklist'])
                              .map(
                                (c) => c['id'] == item['id']
                                    ? {...c, 'done': v}
                                    : c,
                              )
                              .toList();
                          dirty = true;
                        }),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: addCheck,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter une étape'),
                    ),
                    if (widget.data['demo'] != true) heading('Images'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: maps(t['images']).map((image) {
                        final key = image['id'].toString();
                        return FutureBuilder<Uint8List>(
                          future: imageCache.putIfAbsent(
                            key,
                            () => api.imageBytes(key),
                          ),
                          builder: (c, s) => s.hasData
                              ? InkWell(
                                  onTap: () => showDialog<void>(
                                    context: context,
                                    builder: (c) => Dialog(
                                      child: InteractiveViewer(
                                        child: Image.memory(s.data!),
                                      ),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      s.data!,
                                      width: 120,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                              : SizedBox(
                                  width: 120,
                                  height: 100,
                                  child: Center(
                                    child: s.hasError
                                        ? const Icon(Icons.broken_image)
                                        : const CircularProgressIndicator(),
                                  ),
                                ),
                        );
                      }).toList(),
                    ),
                    if (widget.data['demo'] != true)
                      TextButton.icon(
                        onPressed: saving ? null : upload,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Ajouter une image'),
                      ),
                  ],
                ] else ...[
                  ...summary(),
                  TextField(
                    controller: title,
                    maxLength: 160,
                    // Titre sur plusieurs lignes, sans retour à la ligne saisi.
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    autofocus: t['id'] == null,
                    style: TextStyle(
                      fontFamily: tokensOf(context).displayFont,
                      fontSize: existing ? 28 : 24,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Qu’est-ce qu’on a en tête ?',
                      counterText: '',
                      border: existing ? InputBorder.none : null,
                      enabledBorder: existing ? InputBorder.none : null,
                      filled: existing ? false : null,
                      contentPadding: existing ? EdgeInsets.zero : null,
                    ),
                  ),
                  ...actions(),
                  heading(existing ? 'Notes' : 'L’essentiel'),
                  TextField(
                    controller: description,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 12000,
                    decoration: const InputDecoration(
                      labelText: 'Notes et contexte',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...checklistHeading(),
                  ...checklistItems().map(
                    (item) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: item['done'],
                      title: Text(itemLabel(item)),
                      secondary: IconButton(
                        tooltip: 'Retirer',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          t['checklist'] = maps(t['checklist'])
                            ..removeWhere((c) => c['id'] == item['id']);
                          dirty = true;
                        }),
                      ),
                      onChanged: (v) => setState(() {
                        t['checklist'] = maps(t['checklist'])
                            .map(
                              (c) =>
                                  c['id'] == item['id'] ? {...c, 'done': v} : c,
                            )
                            .toList();
                        dirty = true;
                      }),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: addCheck,
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter une étape'),
                  ),
                  if (widget.data['demo'] != true) heading('Images'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: maps(t['images']).map((image) {
                      final key = image['id'].toString();
                      return FutureBuilder<Uint8List>(
                        future: imageCache.putIfAbsent(
                          key,
                          () => api.imageBytes(key),
                        ),
                        builder: (c, s) => s.hasData
                            ? InkWell(
                                onTap: () => showDialog<void>(
                                  context: context,
                                  builder: (c) => Dialog(
                                    child: InteractiveViewer(
                                      child: Image.memory(s.data!),
                                    ),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    s.data!,
                                    width: 120,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              )
                            : SizedBox(
                                width: 120,
                                height: 100,
                                child: Center(
                                  child: s.hasError
                                      ? const Icon(Icons.broken_image)
                                      : const CircularProgressIndicator(),
                                ),
                              ),
                      );
                    }).toList(),
                  ),
                  if (widget.data['demo'] != true)
                    TextButton.icon(
                      onPressed: saving ? null : upload,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Ajouter une image'),
                    ),
                  heading('On en parle'),
                  ...maps(t['comments']).map(
                    (c) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${name(c['authorId'])} · ${timeLabel(c['at'])}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(c['text']),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TextField(
                    controller: comment,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 6000,
                    decoration: const InputDecoration(
                      hintText: 'Une avancée, une question, une décision…',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: saving ? null : postComment,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Commenter'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Tous les réglages'),
                    subtitle: const Text(
                      'Avancement, type, priorité, responsables, dates, tags',
                    ),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: t['stageId'],
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Avancement',
                        ),
                        items: stageItems
                            .map(
                              (s) => DropdownMenuItem(
                                value: s['id'].toString(),
                                child: Text(
                                  s['name'].toString(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() {
                          t['stageId'] = v;
                          dirty = true;
                        }),
                      ),
                      if (t['stageId'] == 'done') ...[
                        heading('Qui l’a réalisé ?'),
                        const Text(
                          'Choix explicite, indépendant des responsables.',
                        ),
                        memberChoices('performers'),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: t['kind'],
                              decoration: const InputDecoration(
                                labelText: 'Type',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'obligation',
                                  child: Text('Obligation'),
                                ),
                                DropdownMenuItem(
                                  value: 'wish',
                                  child: Text('Envie'),
                                ),
                              ],
                              onChanged: (v) => setState(() {
                                t['kind'] = v;
                                dirty = true;
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: t['priority'],
                              decoration: const InputDecoration(
                                labelText: 'Priorité',
                              ),
                              items: ['low', 'normal', 'high', 'urgent']
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(priorityName(p)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() {
                                t['priority'] = v;
                                dirty = true;
                              }),
                            ),
                          ),
                        ],
                      ),
                      heading('Qui s’en occupe ?'),
                      memberChoices('assignees'),
                      heading('Quand ?'),
                      ...['startDate', 'dueDate'].map(
                        (key) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_today_outlined),
                          title: Text(
                            key == 'startDate'
                                ? 'À faire à partir du'
                                : 'Échéance',
                          ),
                          subtitle: Text(
                            t[key] == null ? 'Sans date' : dateLabel(t[key]),
                          ),
                          onTap: () => datePick(key),
                          trailing: t[key] == null
                              ? null
                              : IconButton(
                                  onPressed: () => setState(() {
                                    t[key] = null;
                                    dirty = true;
                                  }),
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                      ),
                      heading('Les tags'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ...tags.map(
                            (tag) => FilterChip(
                              avatar: Icon(
                                Icons.circle,
                                size: 12,
                                color: Color(
                                  int.parse(
                                    tag['color'].toString().replaceFirst(
                                      '#',
                                      'FF',
                                    ),
                                    radix: 16,
                                  ),
                                ),
                              ),
                              label: Text(tag['name']),
                              selected: strings(t['tagIds'])
                                  .contains(tag['id']),
                              onSelected: (v) => setState(() {
                                final list = strings(t['tagIds']);
                                v
                                    ? list.add(tag['id'])
                                    : list.remove(tag['id']);
                                t['tagIds'] = list;
                                dirty = true;
                              }),
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 18),
                            label: const Text('Nouveau tag'),
                            onPressed: addTag,
                          ),
                        ],
                      ),
                    ],
                  ),
                  heading('Le fil de cette tâche'),
                  ...maps(t['history']).reversed.map(
                    (a) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.history, size: 18),
                      title: Text(activityDetail(a)),
                      subtitle: Text(
                        '${name(a['actorId'])} · ${timeLabel(a['at'])}',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ServerAddressDialog extends StatefulWidget {
  const ServerAddressDialog({super.key, required this.initialValue});
  final String initialValue;

  @override
  State<ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<ServerAddressDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _input;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.of(context).pop(_input.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Adresse du serveur'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _input,
        decoration: const InputDecoration(
          labelText: 'https://…',
          errorMaxLines: 4,
        ),
        autofocus: true,
        keyboardType: TextInputType.url,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _submit(),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Saisissez l’adresse du serveur ou choisissez Annuler.';
          }
          try {
            Api.validateServer(value);
            return null;
          } on ApiError catch (e) {
            return e.message;
          }
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
    ],
  );
}
