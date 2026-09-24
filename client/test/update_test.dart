import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foyer/api.dart';
import 'package:foyer/update.dart';

class FakeApi extends Api {
  final Object Function(String path) respond;
  final calls = <String>[];
  FakeApi(this.respond) {
    base = 'https://foyer.test';
  }
  @override
  Future<dynamic> call(String method, String path, [Object? body]) async {
    calls.add('$method $path');
    final value = respond(path);
    if (value is ApiError) throw value;
    return value;
  }
}

const published = {
  'versionCode': 2108,
  'versionName': '1.0.0',
  'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'size': 19841603,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Version plus récente publiée : mise à jour proposée', () async {
    final api = FakeApi((_) => published);
    final update = await Updater.available(api, 2107);
    expect(update?.versionCode, 2108);
    expect(update?.size, 19841603);
    expect(api.calls, ['GET /api/v1/app/android']);
  });

  test('Même version ou plus ancienne : rien à proposer', () async {
    expect(await Updater.available(FakeApi((_) => published), 2108), isNull);
    expect(await Updater.available(FakeApi((_) => published), 2200), isNull);
  });

  test(
    'Build installé : lu sur Android, null ailleurs ou si le natif échoue',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(Updater.channel, null);
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await Updater.installedVersionOrNull(), isNull);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(
        Updater.channel,
        (call) async => {'versionCode': 2116, 'versionName': '1.0.0'},
      );
      expect(await Updater.installedVersionOrNull(), 2116);
      messenger.setMockMethodCallHandler(
        Updater.channel,
        (call) async => throw PlatformException(code: 'x'),
      );
      expect(await Updater.installedVersionOrNull(), isNull);
    },
  );

  test('Rien de publié sur le serveur (404) : pas d’erreur', () async {
    final api = FakeApi((_) => ApiError('Introuvable', 404));
    expect(await Updater.available(api, 2107), isNull);
  });

  test('Autre erreur serveur : remontée à l’appelant', () async {
    final api = FakeApi((_) => ApiError('Session expirée', 401));
    expect(() => Updater.available(api, 2107), throwsA(isA<ApiError>()));
  });

  test(
    'Installation : URL, empreinte et version transmises au natif',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Updater.channel, (call) async {
            received = call;
            return 'permission';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(Updater.channel, null),
      );
      final api = FakeApi((_) => published);
      final started = await Updater.install(
        api,
        AndroidUpdate.fromJson(published),
      );
      expect(started, isFalse);
      expect(received?.method, 'install');
      final args = Map<String, dynamic>.from(received!.arguments as Map);
      expect(args['url'], 'https://foyer.test/api/v1/app/android.apk');
      expect(args['sha256'], published['sha256']);
      expect(args['versionCode'], 2108);
      expect(args['size'], 19841603);
    },
  );
}
