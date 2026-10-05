import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'http_client.dart';

class ApiError implements Exception {
  final String message;
  final int status;
  ApiError(this.message, this.status);
  @override
  String toString() => message;
}

class Api {
  final _storage = const FlutterSecureStorage();
  final http.Client _client = createClient();
  String base = kIsWeb
      ? Uri.base.origin
      : const String.fromEnvironment('API_URL');
  String? _token;
  Future<void> initialize() async {
    if (!kIsWeb) {
      base = await _storage.read(key: 'server') ?? base;
      _token = await _storage.read(key: 'session');
    }
  }

  static Uri validateServer(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ApiError(
        'Saisissez une adresse HTTPS sans chemin, par exemple https://foyer.jmops.fr',
        400,
      );
    }
    return uri;
  }

  Future<void> setServer(String value) async {
    final uri = validateServer(value);
    await clearSession();
    base = uri.origin;
    await _storage.write(key: 'server', value: base);
  }

  Future<void> setSession(String token) async {
    _token = token;
    if (!kIsWeb) await _storage.write(key: 'session', value: token);
  }

  Future<void> clearSession() async {
    _token = null;
    if (!kIsWeb) await _storage.delete(key: 'session');
  }

  Uri uri(String path) => Uri.parse('$base$path');
  Map<String, String> get headers => {
    'X-Foyer-CSRF': '1',
    if (!kIsWeb && _token != null) 'Authorization': 'Bearer $_token',
  };
  Future<dynamic> call(String method, String path, [Object? body]) async {
    if (base.isEmpty) throw ApiError('Configurez l’adresse du serveur.', 400);
    final request = http.Request(method, uri(path));
    request.headers.addAll({...headers, 'Content-Type': 'application/json'});
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 20)),
      );
      return _decode(response);
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(
        'Serveur injoignable. Vérifiez votre connexion et celle du serveur.',
        0,
      );
    }
  }

  dynamic _decode(http.Response r) {
    dynamic value;
    try {
      value = r.body.isEmpty ? null : jsonDecode(r.body);
    } catch (_) {
      value = null;
    }
    if (r.statusCode >= 400) {
      throw ApiError(
        value is Map
            ? value['error']?.toString() ?? 'Erreur serveur (${r.statusCode}).'
            : 'Erreur serveur (${r.statusCode}).',
        r.statusCode,
      );
    }
    return value;
  }

  Future<void> image(String ticket, List<int> bytes, String name) =>
      _upload('/api/v1/tickets/$ticket/images', bytes, name);

  /// Photo d’un ingrédient du catalogue des courses (créé au besoin par le serveur).
  Future<void> ingredientImage(
    String ingredient,
    List<int> bytes,
    String name,
  ) => _upload(
    '/api/v1/shopping/ingredients/${Uri.encodeComponent(ingredient)}/image',
    bytes,
    name,
  );

  Future<void> _upload(String path, List<int> bytes, String name) async {
    final request = http.MultipartRequest('POST', uri(path));
    request.headers.addAll(headers);
    request.files.add(
      http.MultipartFile.fromBytes('image', bytes, filename: name),
    );
    _decode(
      await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 60)),
      ),
    );
  }

  Future<Uint8List> imageBytes(String id) async {
    final response = await _client.get(
      uri('/api/v1/images/$id'),
      headers: headers,
    );
    if (response.statusCode != 200) {
      throw ApiError('Image inaccessible.', response.statusCode);
    }
    return response.bodyBytes;
  }
}
