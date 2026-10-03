import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'categorizer.dart';

class RawNotification {
  RawNotification({required this.pkg, required this.title, required this.text, required this.time});
  final String pkg;
  final String title;
  final String text;
  final DateTime time;

  factory RawNotification.fromMap(Map<String, dynamic> m) => RawNotification(
        pkg: '${m['pkg'] ?? ''}',
        title: '${m['title'] ?? ''}',
        text: '${m['text'] ?? ''}',
        time: DateTime.fromMillisecondsSinceEpoch(((m['time'] ?? 0) as num).toInt()),
      );
}

class ParsedBankTx {
  ParsedBankTx({required this.description, required this.amount, required this.isIncome, required this.category});
  final String description;
  final double amount;
  final bool isIncome;
  final String category;
}

/// Ponte com o serviço Android que escuta as notificações do Nubank.
class CaptureBridge {
  static const _ch = MethodChannel('financa/capture');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isEnabled() async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('openSettings');
    } catch (_) {}
  }

  static Future<void> openAppInfo() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('openAppInfo');
    } catch (_) {}
  }

  /// Retira da fila as notificações capturadas desde a última vez.
  static Future<List<RawNotification>> drain() => _list('drain');

  /// Últimas notificações vistas (para diagnóstico).
  static Future<List<RawNotification>> recent() => _list('recent');

  static Future<List<RawNotification>> _list(String method) async {
    if (!supported) return [];
    try {
      final raw = await _ch.invokeMethod<String>(method);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(RawNotification.fromMap)
          .toList();
    } catch (_) {
      return [];
    }
  }
}

final _amountRe = RegExp(r'R\$\s?-?\s?(\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2})');

const _ignore = [
  'fatura', 'negada', 'recusada', 'não autorizada', 'nao autorizada', 'não aprovada', 'limite disponível',
  'lembrete', 'vence', 'agendad', 'código', 'codigo', 'senha', 'cashback', 'rendeu', 'rendimento',
  'boleto gerado', 'pré-aprovado', 'pre-aprovado', 'empréstimo', 'emprestimo', 'oferta', 'convite',
  'aumentamos', 'cancelad', 'contestação',
];

/// Lê o texto de uma notificação de banco (Nubank) e extrai a transação.
/// Exemplos aceitos:
///  "Compra de R$ 45,90 APROVADA em IFOOD *RESTAURANTE para o cartão com final 1234"
///  "Você enviou uma transferência de R$ 50,00 para Fulano de Tal"
///  "Você recebeu uma transferência de R$ 120,00 de Maria Silva"
ParsedBankTx? parseBankNotification(String title, String text) {
  final full = '${title.trim()}. ${text.trim()}'.replaceAll(RegExp(r'\s+'), ' ');
  final lower = full.toLowerCase();
  if (_ignore.any(lower.contains)) return null;

  final m = _amountRe.firstMatch(full);
  if (m == null) return null;
  final amount = double.tryParse(m.group(1)!.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
  if (amount <= 0) return null;

  final income = RegExp(r'recebe|recebid|depósito|deposito|estorno|reembolso|caiu na sua conta|entrou na sua conta')
      .hasMatch(lower);
  final expense = RegExp(
          r'compra|pagamento|pagou|enviad|enviou|transferência realizada|transferencia realizada|débito|debito|pix para|saque|assinatura')
      .hasMatch(lower);
  if (!income && !expense) return null;

  final after = full.substring(m.end);
  String? who;
  RegExpMatch? w;
  if (income) {
    w = RegExp(r'\bde\s+(.+?)(?:\s+foi|\s+caiu|\s+na sua conta|\s+via|[.!]|$)', caseSensitive: false).firstMatch(after);
  } else {
    w = RegExp(r'\bem\s+(.+?)(?:\s+para o cart|\s+no cart|\s+com o cart|\s+no crédito|\s+no débito|[.!]|$)',
            caseSensitive: false)
        .firstMatch(after);
    w ??= RegExp(r'\bpara\s+(?!o cart)(.+?)(?:\s+foi|\s+com sucesso|\s+via|[.!]|$)', caseSensitive: false)
        .firstMatch(after);
  }
  who = w?.group(1)?.trim();

  var desc = (who != null && who.length >= 2) ? who : title.trim();
  desc = desc.replaceAll(RegExp(r'\s*\*\s*'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (desc.isEmpty) desc = income ? 'Entrada Nubank' : 'Gasto Nubank';
  if (desc.length > 60) desc = desc.substring(0, 60);
  desc = _titleCase(desc);

  String category;
  if (income) {
    category = 'Renda';
  } else {
    category = guessCategory(desc);
    final isPixToPerson = RegExp(r'pix|transferência|transferencia|enviou').hasMatch(lower) && category == 'Outros';
    if (isPixToPerson) category = 'Transferências';
  }
  return ParsedBankTx(description: desc, amount: amount, isIncome: income, category: category);
}

String _titleCase(String s) {
  if (s != s.toUpperCase()) return s;
  return s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
