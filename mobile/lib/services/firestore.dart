import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'auth_service.dart';

class FirestoreException implements Exception {
  FirestoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FsDoc {
  FsDoc(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

/// Cliente mínimo da API REST do Firestore. Usa o token do usuário,
/// então as regras de segurança (cada um só vê os próprios dados) valem.
class Firestore {
  Firestore(this.auth);
  final AuthService auth;

  String get _base =>
      'https://firestore.googleapis.com/v1/projects/${AppConfig.firebaseProjectId}/databases/(default)/documents';

  Future<http.Response> _send(String method, Uri uri, {Object? body}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await auth.validIdToken(forceRefresh: attempt == 1);
      final req = http.Request(method, uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Content-Type'] = 'application/json';
      if (body != null) req.body = jsonEncode(body);
      final http.Response res;
      try {
        res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 30)));
      } catch (_) {
        throw FirestoreException('Sem conexão com o banco de dados.');
      }
      if (res.statusCode == 401 && attempt == 0) continue;
      return res;
    }
    throw FirestoreException('Sessão expirada.');
  }

  void _check(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String msg = 'Erro ${res.statusCode}';
    try {
      final err = (jsonDecode(res.body) as Map<String, dynamic>)['error'] as Map<String, dynamic>;
      final status = '${err['status']}';
      msg = '${err['message']}';
      if (status == 'PERMISSION_DENIED') {
        msg = 'Sem permissão no Firestore. Publique as regras do arquivo mobile/firestore.rules no console do Firebase.';
      } else if (status == 'NOT_FOUND' && msg.contains('database')) {
        msg = 'O Firestore ainda não foi criado neste projeto Firebase.';
      }
    } catch (_) {}
    throw FirestoreException(msg);
  }

  Future<Map<String, dynamic>?> getDoc(String path) async {
    final res = await _send('GET', Uri.parse('$_base/$path'));
    if (res.statusCode == 404) return null;
    _check(res);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return decodeFields((m['fields'] as Map<String, dynamic>?) ?? {});
  }

  Future<List<FsDoc>> list(String collectionPath) async {
    final out = <FsDoc>[];
    String? pageToken;
    do {
      final q = <String, String>{'pageSize': '300'};
      if (pageToken != null) q['pageToken'] = pageToken;
      final uri = Uri.parse('$_base/$collectionPath').replace(queryParameters: q);
      final res = await _send('GET', uri);
      if (res.statusCode == 404) return out;
      _check(res);
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      for (final d in (m['documents'] as List? ?? const [])) {
        final doc = d as Map<String, dynamic>;
        final name = doc['name'] as String;
        out.add(FsDoc(name.split('/').last, decodeFields((doc['fields'] as Map<String, dynamic>?) ?? {})));
      }
      pageToken = m['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return out;
  }

  /// Cria ou substitui o documento inteiro.
  Future<void> set(String path, Map<String, dynamic> data) async {
    final res = await _send('PATCH', Uri.parse('$_base/$path'), body: {'fields': encodeFields(data)});
    _check(res);
  }

  /// Atualiza só os campos informados.
  Future<void> merge(String path, Map<String, dynamic> data) async {
    final uri = Uri.parse('$_base/$path').replace(
      queryParameters: {'updateMask.fieldPaths': data.keys.toList()},
    );
    final res = await _send('PATCH', uri, body: {'fields': encodeFields(data)});
    _check(res);
  }

  Future<void> delete(String path) async {
    final res = await _send('DELETE', Uri.parse('$_base/$path'));
    if (res.statusCode == 404) return;
    _check(res);
  }
}

Map<String, dynamic> encodeFields(Map<String, dynamic> m) =>
    m.map((k, v) => MapEntry(k, encodeValue(v)));

Map<String, dynamic> encodeValue(dynamic v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': v.toString()};
  if (v is double) return {'doubleValue': v};
  if (v is num) return {'doubleValue': v.toDouble()};
  if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
  if (v is String) return {'stringValue': v};
  if (v is List) return {'arrayValue': {'values': v.map(encodeValue).toList()}};
  if (v is Map) return {'mapValue': {'fields': encodeFields(Map<String, dynamic>.from(v))}};
  return {'stringValue': v.toString()};
}

Map<String, dynamic> decodeFields(Map<String, dynamic> fields) =>
    fields.map((k, v) => MapEntry(k, decodeValue(v as Map<String, dynamic>)));

dynamic decodeValue(Map<String, dynamic> v) {
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('integerValue')) return int.tryParse('${v['integerValue']}') ?? 0;
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('booleanValue')) return v['booleanValue'] as bool;
  if (v.containsKey('timestampValue')) return DateTime.parse(v['timestampValue'] as String).toLocal();
  if (v.containsKey('arrayValue')) {
    final values = ((v['arrayValue'] as Map<String, dynamic>)['values'] as List?) ?? const [];
    return values.map((e) => decodeValue(e as Map<String, dynamic>)).toList();
  }
  if (v.containsKey('mapValue')) {
    return decodeFields(((v['mapValue'] as Map<String, dynamic>)['fields'] as Map<String, dynamic>?) ?? {});
  }
  return null;
}
