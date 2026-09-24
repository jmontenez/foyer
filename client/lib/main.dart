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
import 'update.dart';

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
Future<void> backgroundMessage(RemoteMessage message) async {}
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await api.initialize();
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
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: selectedPalette,
    builder: (context, paletteId, _) => MaterialApp(
      title: 'Foyer',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messenger,
      theme: buildAppTheme(paletteById(paletteId)),
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
  DateTime? historyFrom, historyTo;
  Timer? timer;
  bool refreshing = false;
  bool pushInitialized = false;
  bool choosingPalette = false;
  AndroidUpdate? update;
  bool updateDismissed = false, installingUpdate = false;
  DateTime? updateCheckedAt;
  StreamSubscription<RemoteMessage>? pushOpen, pushForeground;
  StreamSubscription<String>? tokenRefresh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    timer = Timer.periodic(const Duration(seconds: 12), (_) => checkRevision());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    pushOpen?.cancel();
    pushForeground?.cancel();
    tokenRefresh?.cancel();
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
            selectedPalette.value = paletteById(result['me']['paletteId']).id;
          }
          loading = false;
          error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          if (e.status == 401) {
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
    if (data != null) unawaited(checkUpdate());
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
        message(m.notification?.body ?? 'Nouvelle activité');
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TicketPage(data: data!, ticket: ticket),
      ),
    );
    await refresh();
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
                        const Text(
                          'Démonstration locale · données fictives',
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
    final titles = [
      'Aujourd’hui',
      'Cette semaine',
      'Notre tableau',
      'Le backlog',
      'Notre historique',
    ];
    final subtitles = [
      'Ce qui mérite notre attention.',
      'Un peu de recul sur les prochains jours.',
      'Chacun sait où nous en sommes.',
      'Tout ce qu’on veut garder en tête.',
      'Ce qu’on a fait, et les décisions prises.',
    ];
    final tickets = visible();
    final navIcons = [
      Icons.wb_sunny_outlined,
      Icons.date_range_outlined,
      Icons.view_kanban_outlined,
      Icons.inventory_2_outlined,
      Icons.history,
    ];
    final labels = [
      'Aujourd’hui',
      'Semaine',
      'Tableau',
      'Backlog',
      'Historique',
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cottage_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            SizedBox(width: 10),
            Text('Foyer', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Réglages',
            onPressed: () => settingsDialog(),
            icon: const Icon(Icons.tune),
          ),
          const SizedBox(width: 12),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openTicket(),
        icon: const Icon(Icons.add),
        label: const Text('Une nouvelle tâche'),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: List.generate(
                5,
                (i) => NavigationDestination(
                  icon: Icon(navIcons[i]),
                  label: labels[i],
                ),
              ),
            ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              labelType: NavigationRailLabelType.all,
              destinations: List.generate(
                5,
                (i) => NavigationRailDestination(
                  icon: Icon(navIcons[i]),
                  label: Text(labels[i]),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                wide ? 32 : 18,
                18,
                wide ? 32 : 18,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titles[tab],
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitles[tab],
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 20),
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
                          onPressed: installingUpdate ? null : installUpdate,
                          child: Text(
                            installingUpdate ? 'Téléchargement…' : 'Installer',
                          ),
                        ),
                      ],
                    ),
                  if (data!['maintenance'] == true)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Maintenance en cours : modifications temporairement suspendues.',
                      ),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Tout le foyer'),
                          selected: person == 'all',
                          onSelected: (_) => setState(() => person = 'all'),
                        ),
                        const SizedBox(width: 8),
                        ...maps(data!['members']).map(
                          (m) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                m['id'] == data!['me']['id']
                                    ? 'Moi'
                                    : m['name'],
                              ),
                              selected: person == m['id'],
                              onSelected: (_) =>
                                  setState(() => person = m['id']),
                            ),
                          ),
                        ),
                        ChoiceChip(
                          label: Text(
                            tab == 4 ? 'Sans réalisation' : 'Sans responsable',
                          ),
                          selected: person == 'none',
                          onSelected: (_) => setState(() => person = 'none'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Rechercher dans cette vue…',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                          onChanged: (v) => setState(() => query = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: tag,
                        onChanged: (v) => setState(() => tag = v!),
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('Tous les tags'),
                          ),
                          ...maps(data!['tags']).map(
                            (t) => DropdownMenuItem(
                              value: t['id'] as String,
                              child: Text(t['name']),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (tab == 4)
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.calendar_month),
                          label: Text(
                            historyFrom == null
                                ? 'Depuis…'
                                : dateLabel(historyFrom!.toIso8601String()),
                          ),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDate: historyFrom ?? DateTime.now(),
                            );
                            if (d != null) setState(() => historyFrom = d);
                          },
                        ),
                        TextButton(
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              initialDate: historyTo ?? DateTime.now(),
                            );
                            if (d != null) setState(() => historyTo = d);
                          },
                          child: Text(
                            historyTo == null
                                ? 'Jusqu’au…'
                                : dateLabel(historyTo!.toIso8601String()),
                          ),
                        ),
                        if (historyFrom != null || historyTo != null)
                          TextButton(
                            onPressed: () => setState(() {
                              historyFrom = null;
                              historyTo = null;
                            }),
                            child: const Text('Effacer les dates'),
                          ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: tab == 2
                        ? board(tickets)
                        : tickets.isEmpty
                        ? empty()
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 100),
                            itemCount: tickets.length,
                            itemBuilder: (_, i) => ticketCard(tickets[i]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
  Widget board(List<Map<String, dynamic>> tickets) {
    final stages = maps(data!['stages'])
      ..sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 90),
      children: stages.map((s) {
        final items = tickets.where((t) => t['stageId'] == s['id']).toList();
        return SizedBox(
          width: 310,
          child: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    '${s['name']}  ·  ${items.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(children: items.map(ticketCard).toList()),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget ticketCard(Map<String, dynamic> t) {
    final overdue =
        t['dueDate'] != null &&
        t['dueDate'].toString().compareTo(data!['today'].toString()) < 0 &&
        t['stageId'] != 'done' &&
        t['stageId'] != 'abandoned';
    final check = maps(t['checklist']);
    final names = strings(tab == 4 ? t['performers'] : t['assignees'])
        .map(memberName)
        .join(' + ');
    final stage =
        maps(data!['stages'])
            .where((s) => s['id'] == t['stageId'])
            .map((s) => s['name'])
            .firstOrNull ??
        {
          'backlog': 'Backlog',
          'done': 'Terminé',
          'abandoned': 'Abandonné',
        }[t['stageId']];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => openTicket(t),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'F-${t['number']}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    t['kind'] == 'wish'
                        ? Icons.auto_awesome
                        : Icons.check_circle_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    t['kind'] == 'wish' ? 'Envie' : 'Obligation',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                t['title'],
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 5,
                children: [
                  Text(
                    priorityName(t['priority']),
                    style: TextStyle(
                      color: priorityColor(
                        t['priority'],
                        Theme.of(context).brightness,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (tab != 2)
                    Text(
                      stage?.toString() ?? '',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ...maps(data!['tags'])
                      .where((tag) => strings(t['tagIds']).contains(tag['id']))
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Color(
                              int.parse(
                                tag['color'].toString().replaceFirst('#', 'FF'),
                                radix: 16,
                              ),
                            ).withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tag['name'],
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  Text(
                    names.isEmpty ? 'À attribuer' : names,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                    ),
                  ),
                  if (t['startDate'] != null)
                    Text(
                      'Début ${dateLabel(t['startDate'])}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (t['dueDate'] != null)
                    Text(
                      '${overdue ? 'En retard · ' : ''}Échéance ${dateLabel(t['dueDate'])}',
                      style: TextStyle(
                        fontSize: 12,
                        color: overdue
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (check.isNotEmpty)
                    Text(
                      '${check.where((c) => c['done'] == true).length}/${check.length} étapes',
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (maps(t['comments']).isNotEmpty)
                    Text(
                      '${maps(t['comments']).length} commentaires',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> appearanceDialog() async {
    if (choosingPalette) return;
    choosingPalette = true;
    try {
      final choice = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .85,
          child: const PalettePicker(),
        ),
      );
      if (choice != null) {
        final me = await api.call('PUT', '/api/v1/appearance', {
          'paletteId': choice,
        });
        if (mounted && data != null) setState(() => data!['me'] = me);
      }
    } catch (e) {
      message(e);
    } finally {
      choosingPalette = false;
      selectedPalette.value = paletteById(data?['me']?['paletteId']).id;
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
                      'Notification à ${me['digestTime']} · Europe/Paris',
                    ),
                    value: me['digestEnabled'],
                    onChanged: (v) => change(() => me['digestEnabled'] = v),
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
                    title: const Text('Couleurs de l’application'),
                    subtitle: Text(paletteById(me['paletteId']).name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(c);
                      appearanceDialog();
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
          title: Text(
            t['id'] == null ? 'Une nouvelle tâche' : 'F-${t['number']}',
          ),
          actions: [
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
                TextField(
                  controller: title,
                  maxLength: 160,
                  textCapitalization: TextCapitalization.sentences,
                  autofocus: t['id'] == null,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Qu’est-ce qu’on a en tête ?',
                    counterText: '',
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
                  heading('L’essentiel'),
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
                    decoration: const InputDecoration(labelText: 'Avancement'),
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
                          decoration: const InputDecoration(labelText: 'Type'),
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
                        key == 'startDate' ? 'À faire à partir du' : 'Échéance',
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
                                tag['color'].toString().replaceFirst('#', 'FF'),
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
                  heading('Une étape à la fois'),
                  ...maps(t['checklist']).map(
                    (item) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: item['done'],
                      title: Text(item['text']),
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
                  heading('Images'),
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
                  TextButton.icon(
                    onPressed: saving ? null : upload,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Ajouter une image'),
                  ),
                ],
                if (t['id'] != null) ...[
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
