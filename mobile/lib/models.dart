import 'dart:math';

import 'package:flutter/material.dart';

class Cat {
  const Cat(this.name, this.icon, this.color);
  final String name;
  final IconData icon;
  final Color color;
}

const cats = <Cat>[
  Cat('Comida', Icons.restaurant_rounded, Color(0xFFF97316)),
  Cat('Transporte', Icons.directions_car_rounded, Color(0xFF3B82F6)),
  Cat('Casa', Icons.home_rounded, Color(0xFF8B5CF6)),
  Cat('Lazer', Icons.celebration_rounded, Color(0xFFEC4899)),
  Cat('Mensalidades', Icons.autorenew_rounded, Color(0xFF0891B2)),
  Cat('Saúde', Icons.favorite_rounded, Color(0xFFEF4444)),
  Cat('Educação', Icons.school_rounded, Color(0xFF6366F1)),
  Cat('Compras', Icons.shopping_bag_rounded, Color(0xFFD97706)),
  Cat('Investimentos', Icons.trending_up_rounded, Color(0xFF059669)),
  Cat('Transferências', Icons.swap_horiz_rounded, Color(0xFF64748B)),
  Cat('Renda', Icons.payments_rounded, Color(0xFF16A34A)),
  Cat('Outros', Icons.more_horiz_rounded, Color(0xFF9CA3AF)),
];

/// Categorias que contam como "gasto" no mês.
final spendingCats = cats.map((c) => c.name).where((n) => n != 'Renda' && n != 'Investimentos').toList();

Cat catOf(String name) => cats.firstWhere((c) => c.name == name, orElse: () => cats.last);

String newId() {
  final r = Random();
  return DateTime.now().microsecondsSinceEpoch.toRadixString(36) + r.nextInt(1 << 30).toRadixString(36);
}

/// Hash FNV-1a estável (String.hashCode não é garantido entre execuções).
String stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(36);
}

class Tx {
  Tx({
    required this.id,
    required this.description,
    required this.amount,
    required this.isIncome,
    required this.category,
    required this.date,
    this.source = 'manual',
    this.raw,
    this.aiCategorized = false,
  });

  final String id;
  String description;
  double amount;
  bool isIncome;
  String category;
  DateTime date;
  String source; // manual | nubank | jose
  String? raw;
  bool aiCategorized;

  Map<String, dynamic> toMap() => {
        'description': description,
        'amount': amount,
        'isIncome': isIncome,
        'category': category,
        'date': date,
        'source': source,
        'raw': raw,
        'aiCategorized': aiCategorized,
      };

  factory Tx.fromMap(String id, Map<String, dynamic> m) => Tx(
        id: id,
        description: (m['description'] ?? '') as String,
        amount: ((m['amount'] ?? 0) as num).toDouble(),
        isIncome: (m['isIncome'] ?? false) as bool,
        category: (m['category'] ?? 'Outros') as String,
        date: (m['date'] is DateTime) ? m['date'] as DateTime : DateTime.now(),
        source: (m['source'] ?? 'manual') as String,
        raw: m['raw'] as String?,
        aiCategorized: (m['aiCategorized'] ?? false) as bool,
      );
}

class Investment {
  Investment({required this.id, required this.name, required this.kind, required this.amount, required this.date});
  final String id;
  String name;
  String kind;
  double amount;
  DateTime date;

  Map<String, dynamic> toMap() => {'name': name, 'kind': kind, 'amount': amount, 'date': date};

  factory Investment.fromMap(String id, Map<String, dynamic> m) => Investment(
        id: id,
        name: (m['name'] ?? '') as String,
        kind: (m['kind'] ?? 'Renda fixa') as String,
        amount: ((m['amount'] ?? 0) as num).toDouble(),
        date: (m['date'] is DateTime) ? m['date'] as DateTime : DateTime.now(),
      );
}

class Profile {
  Profile({
    this.name = '',
    this.risk = 'moderado',
    this.horizon = 'medio',
    this.knowledge = 'iniciante',
    this.monthlyIncome = 0,
    this.goals = '',
    this.geminiKey = '',
  });

  String name;
  String risk; // conservador | moderado | arrojado
  String horizon; // curto | medio | longo
  String knowledge; // iniciante | intermediario | avancado
  double monthlyIncome;
  String goals;
  String geminiKey;

  Map<String, dynamic> toMap() => {
        'name': name,
        'risk': risk,
        'horizon': horizon,
        'knowledge': knowledge,
        'monthlyIncome': monthlyIncome,
        'goals': goals,
        'geminiKey': geminiKey,
      };

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        name: (m['name'] ?? '') as String,
        risk: (m['risk'] ?? 'moderado') as String,
        horizon: (m['horizon'] ?? 'medio') as String,
        knowledge: (m['knowledge'] ?? 'iniciante') as String,
        monthlyIncome: ((m['monthlyIncome'] ?? 0) as num).toDouble(),
        goals: (m['goals'] ?? '') as String,
        geminiKey: (m['geminiKey'] ?? '') as String,
      );
}

class ChatMsg {
  ChatMsg(this.text, {required this.fromUser, this.isNote = false});
  final String text;
  final bool fromUser;
  final bool isNote; // confirmação de ação feita pelo José
}

/// Mensagem de erro exibida no chat (não vai para o Gemini).
class ChatMsgError extends ChatMsg {
  ChatMsgError(String text) : super(text, fromUser: false);
}
