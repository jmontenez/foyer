import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api.dart';

class AndroidUpdate {
  final int versionCode;
  final String versionName;
  final String sha256;
  final int size;
  const AndroidUpdate({
    required this.versionCode,
    required this.versionName,
    required this.sha256,
    required this.size,
  });
  factory AndroidUpdate.fromJson(Map<dynamic, dynamic> json) => AndroidUpdate(
    versionCode: (json['versionCode'] as num).toInt(),
    versionName: json['versionName'].toString(),
    sha256: json['sha256'].toString(),
    size: (json['size'] as num).toInt(),
  );
}

// Mises à jour hors store, Android uniquement : le serveur Foyer distribue l’APK signé
// aux membres connectés ; le téléchargement, les vérifications et l’appel à l’installateur
// sont faits côté natif (MainActivity.kt).
class Updater {
  static const channel = MethodChannel('fr.foyer/update');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<int> installedVersion() async {
    final info = await channel.invokeMapMethod<String, dynamic>('info');
    return (info!['versionCode'] as num).toInt();
  }

  /// versionCode installé, ou null hors Android ou si le canal natif ne répond pas.
  static Future<int?> installedVersionOrNull() async {
    if (!supported) return null;
    try {
      return await installedVersion();
    } catch (_) {
      return null;
    }
  }

  /// Version plus récente publiée par le serveur, sinon null (y compris si rien n’est publié).
  static Future<AndroidUpdate?> available(Api api, int installed) async {
    final dynamic body;
    try {
      body = await api.call('GET', '/api/v1/app/android');
    } on ApiError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
    final update = AndroidUpdate.fromJson(body as Map);
    return update.versionCode > installed ? update : null;
  }

  /// true si l’installation a démarré (confirmation Android éventuelle, puis Foyer se ferme),
  /// false s’il faut d’abord autoriser Foyer à installer des applications.
  /// Lève PlatformException avec un message affichable.
  static Future<bool> install(Api api, AndroidUpdate update) async {
    final outcome = await channel.invokeMethod<String>('install', {
      'url': api.uri('/api/v1/app/android.apk').toString(),
      'headers': api.headers,
      'sha256': update.sha256,
      'size': update.size,
      'versionCode': update.versionCode,
    });
    return outcome == 'started';
  }

  static Future<void> openPermission() => channel.invokeMethod('permission');
}
