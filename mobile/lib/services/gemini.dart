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

/// Cliente do Gemini (Google). Tenta os modelos de [AppConfig.geminiModels]
/// em ordem e memoriza o primeiro que funcionar.
class Gemini {
  String apiKey = '';
  String? workingModel;

  bool get configured => apiKey.trim().isNotEmpty;

  Future<String> generate({
    String? system,
    required List<ChatMsg> messages,
    bool json = false,
    double temperature = 0.6,
  }) async {
    if (!configured) {
      throw GeminiException('Configure sua chave do Gemini em Perfil para conversar com o ${AppConfig.assistantName}.');
    }
    final models = <String>[
      if (workingModel != null) workingModel!,
      ...AppConfig.geminiModels.where((m) => m != workingModel),
    ];
    final body = jsonEncode({
      if (system != null) 'systemInstruction': {
        'parts': [
          {'text': system}
        ]
      },
      'contents': _turns(messages),
      'generationConfig': {
        'temperature': temperature,
        if (json) 'responseMimeType': 'application/json',
      },
    });

    GeminiException? last;
    for (final model in models) {
      final base = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';
      http.Response res;
      try {
        res = await _post(Uri.parse(base), body, headerKey: true);
        // Algumas chaves só funcionam via parâmetro na URL.
        if (res.statusCode == 401 || res.statusCode == 403) {
          final alt = await _post(Uri.parse('$base?key=${Uri.encodeQueryComponent(apiKey.trim())}'), body,
              headerKey: false);
          if (alt.statusCode == 200 || alt.statusCode == 404 || alt.statusCode == 429) res = alt;
        }
      } catch (_) {
        throw GeminiException('Sem conexão com o Gemini. Verifique sua internet.');
      }

      if (res.statusCode == 200) {
        workingModel = model;
        return _extractText(res.body);
      }
      final msg = _errorMessage(res.body);
      final lower = msg.toLowerCase();
      if (res.statusCode == 404 || (res.statusCode == 400 && lower.contains('model'))) {
        last = GeminiException('Modelo $model indisponível.');
        continue;
      }
      if (res.statusCode == 429) {
        last = GeminiException('Limite gratuito do Gemini atingido por agora. Tente de novo em alguns minutos.');
        continue;
      }
      if (res.statusCode == 400 && (lower.contains('api key') || lower.contains('api_key'))) {
        throw GeminiException('A chave do Gemini foi recusada ($msg). Gere uma nova em aistudio.google.com.');
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw GeminiException('A chave do Gemini não tem permissão ($msg).');
      }
      last = GeminiException('Gemini respondeu ${res.statusCode}: $msg');
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
        final parts = out.last['parts'] as List;
        parts.add({'text': m.text});
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
        .timeout(const Duration(seconds: 90));
  }

  String _extractText(String body) {
    final m = jsonDecode(body) as Map<String, dynamic>;
    final candidates = (m['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) {
      throw GeminiException('O Gemini não retornou resposta (talvez bloqueio de segurança).');
    }
    final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
    final parts = (content?['parts'] as List?) ?? const [];
    final text = parts
        .whereType<Map<String, dynamic>>()
        .where((p) => p['thought'] != true && p['text'] is String)
        .map((p) => p['text'] as String)
        .join();
    if (text.trim().isEmpty) throw GeminiException('Resposta vazia do Gemini.');
    return text.trim();
  }

  String _errorMessage(String body) {
    try {
      return '${((jsonDecode(body) as Map<String, dynamic>)['error'] as Map<String, dynamic>)['message']}';
    } catch (_) {
      return body.length > 200 ? body.substring(0, 200) : body;
    }
  }

  /// Pede JSON e já devolve decodificado.
  Future<dynamic> generateJson({String? system, required String prompt, double temperature = 0.4}) async {
    final text = await generate(
      system: system,
      messages: [ChatMsg(prompt, fromUser: true)],
      json: true,
      temperature: temperature,
    );
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
}
