import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models.dart';

class GeminiException implements Exception {
  GeminiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GeminiSource {
  GeminiSource(this.title, this.url);
  final String title;
  final String url;
}

class GeminiReply {
  GeminiReply(this.text, this.sources, this.model);
  final String text;
  final List<GeminiSource> sources;
  final String model;
}

/// Cliente do Gemini (Google).
/// - `fast`: usa modelos leves (categorizar gastos).
/// - `search`: deixa o José pesquisar no Google (taxas, cotações, notícias).
/// Tenta os modelos em ordem e memoriza o primeiro que funcionar.
class Gemini {
  String apiKey = '';
  String? _smartModel;
  String? _fastModel;
  bool _searchUnavailable = false;

  String? get workingModel => _smartModel ?? _fastModel;
  bool get configured => apiKey.trim().isNotEmpty;

  Future<String> generate({
    String? system,
    required List<ChatMsg> messages,
    bool json = false,
    double temperature = 0.6,
    bool fast = false,
    bool search = false,
  }) async {
    final r = await generateFull(
        system: system, messages: messages, json: json, temperature: temperature, fast: fast, search: search);
    return r.text;
  }

  Future<GeminiReply> generateFull({
    String? system,
    required List<ChatMsg> messages,
    bool json = false,
    double temperature = 0.6,
    bool fast = false,
    bool search = false,
  }) async {
    if (!configured) {
      throw GeminiException(
          'O ${AppConfig.assistantName} está sem chave do Gemini. Cole uma em Perfil ou configure o segredo GEMINI_API_KEY no GitHub.');
    }
    final remembered = fast ? _fastModel : _smartModel;
    final list = fast ? AppConfig.fastModels : AppConfig.smartModels;
    final models = <String>[if (remembered != null) remembered, ...list.where((m) => m != remembered)];
    final useSearch = search && !json && !_searchUnavailable;

    GeminiException? last;
    for (final model in models) {
      var withTools = useSearch;
      for (var attempt = 0; attempt < 2; attempt++) {
        final body = jsonEncode({
          if (system != null)
            'systemInstruction': {
              'parts': [
                {'text': system}
              ]
            },
          'contents': _turns(messages),
          if (withTools)
            'tools': [
              {'google_search': <String, dynamic>{}}
            ],
          'generationConfig': {
            'temperature': temperature,
            if (json) 'responseMimeType': 'application/json',
          },
        });
        final base = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';
        http.Response res;
        try {
          res = await _post(Uri.parse(base), body, headerKey: true);
          if (res.statusCode == 401 || res.statusCode == 403) {
            final alt = await _post(Uri.parse('$base?key=${Uri.encodeQueryComponent(apiKey.trim())}'), body,
                headerKey: false);
            if (alt.statusCode == 200 || alt.statusCode == 404 || alt.statusCode == 429) res = alt;
          }
        } catch (_) {
          throw GeminiException('Sem conexão com o Gemini. Verifique sua internet.');
        }

        if (res.statusCode == 200) {
          if (fast) {
            _fastModel = model;
          } else {
            _smartModel = model;
          }
          return _parse(res.body, model);
        }
        final msg = _errorMessage(res.body);
        final lower = msg.toLowerCase();
        // Se a busca no Google não for aceita, tenta de novo sem ela.
        if (withTools && (res.statusCode == 400 || res.statusCode == 403 || res.statusCode == 429) &&
            (lower.contains('tool') || lower.contains('search') || lower.contains('ground') || res.statusCode == 429)) {
          withTools = false;
          if (res.statusCode != 429) _searchUnavailable = true;
          continue;
        }
        if (res.statusCode == 404 || (res.statusCode == 400 && lower.contains('model'))) {
          last = GeminiException('Modelo $model indisponível.');
          break;
        }
        if (res.statusCode == 429) {
          last = GeminiException('O limite gratuito do Gemini acabou por agora. Tente de novo em alguns minutos.');
          break;
        }
        if (res.statusCode == 400 && (lower.contains('api key') || lower.contains('api_key'))) {
          throw GeminiException('A chave do Gemini foi recusada ($msg).');
        }
        if (res.statusCode == 401 || res.statusCode == 403) {
          throw GeminiException('A chave do Gemini não tem permissão ($msg).');
        }
        last = GeminiException('Gemini respondeu ${res.statusCode}: $msg');
        break;
      }
    }
    throw last ?? GeminiException('Nenhum modelo do Gemini respondeu.');
  }

  /// Junta mensagens seguidas do mesmo lado e garante que começa pelo usuário.
  List<Map<String, dynamic>> _turns(List<ChatMsg> messages) {
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      if (m.isNote || m is ChatMsgError || m.text.trim().isEmpty) continue;
      final role = m.fromUser ? 'user' : 'model';
      if (out.isEmpty && role == 'model') continue;
      if (out.isNotEmpty && out.last['role'] == role) {
        (out.last['parts'] as List).add({'text': m.text});
      } else {
        out.add({
          'role': role,
          'parts': [
            {'text': m.text}
          ],
        });
      }
    }
    return out;
  }

  Future<http.Response> _post(Uri uri, String body, {required bool headerKey}) {
    return http
        .post(uri,
            headers: {
              'Content-Type': 'application/json',
              if (headerKey) 'x-goog-api-key': apiKey.trim(),
            },
            body: body)
        .timeout(const Duration(seconds: 120));
  }

  GeminiReply _parse(String body, String model) {
    final m = jsonDecode(body) as Map<String, dynamic>;
    final candidates = (m['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) {
      throw GeminiException('O Gemini não retornou resposta (talvez bloqueio de segurança).');
    }
    final cand = candidates.first as Map<String, dynamic>;
    final content = cand['content'] as Map<String, dynamic>?;
    final parts = (content?['parts'] as List?) ?? const [];
    final text = parts
        .whereType<Map<String, dynamic>>()
        .where((p) => p['thought'] != true && p['text'] is String)
        .map((p) => p['text'] as String)
        .join();
    if (text.trim().isEmpty) throw GeminiException('Resposta vazia do Gemini.');

    final sources = <GeminiSource>[];
    final chunks = ((cand['groundingMetadata'] as Map<String, dynamic>?)?['groundingChunks'] as List?) ?? const [];
    for (final c in chunks.whereType<Map<String, dynamic>>()) {
      final web = c['web'] as Map<String, dynamic>?;
      if (web == null) continue;
      final url = '${web['uri'] ?? ''}';
      if (url.isEmpty || sources.any((s) => s.url == url)) continue;
      sources.add(GeminiSource('${web['title'] ?? 'fonte'}', url));
    }
    return GeminiReply(text.trim(), sources, model);
  }

  String _errorMessage(String body) {
    try {
      return '${((jsonDecode(body) as Map<String, dynamic>)['error'] as Map<String, dynamic>)['message']}';
    } catch (_) {
      return body.length > 200 ? body.substring(0, 200) : body;
    }
  }

  /// Pede JSON e já devolve decodificado.
  Future<dynamic> generateJson({
    String? system,
    required String prompt,
    double temperature = 0.4,
    bool fast = false,
  }) async {
    final text = await generate(
      system: system,
      messages: [ChatMsg(prompt, fromUser: true)],
      json: true,
      temperature: temperature,
      fast: fast,
    );
    return decodeLooseJson(text);
  }
}

/// Lê JSON mesmo vindo com ```json ... ``` ou texto em volta.
dynamic decodeLooseJson(String text) {
  var clean = text.trim();
  if (clean.startsWith('```')) {
    clean = clean.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '').replaceFirst(RegExp(r'\s*```$'), '');
  }
  try {
    return jsonDecode(clean);
  } catch (_) {
    final start = clean.indexOf(RegExp(r'[\[{]'));
    final end = clean.lastIndexOf(RegExp(r'[\]}]'));
    if (start >= 0 && end > start) return jsonDecode(clean.substring(start, end + 1));
    throw GeminiException('Não entendi a resposta do Gemini.');
  }
}
