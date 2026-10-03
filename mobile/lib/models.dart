import 'dart:math';

import 'package:flutter/material.dart';

class Cat {
  const Cat(this.name, this.icon, this.color, {this.custom = false, this.id});
  final String name;
  final IconData icon;
  final Color color;
  final bool custom;
  final String? id;
}

const builtinCats = <Cat>[
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
  Cat('Dívidas', Icons.credit_card_rounded, Color(0xFFB91C1C)),
  Cat('Renda', Icons.payments_rounded, Color(0xFF16A34A)),
  Cat('Outros', Icons.more_horiz_rounded, Color(0xFF9CA3AF)),
];

/// Ícones disponíveis para categorias criadas pelo usuário.
/// (Precisam ser constantes para o build do Android não remover os ícones.)
const iconChoices = <String, IconData>{
  'pet': Icons.pets_rounded,
  'presente': Icons.card_giftcard_rounded,
  'familia': Icons.family_restroom_rounded,
  'bebe': Icons.child_friendly_rounded,
  'academia': Icons.fitness_center_rounded,
  'beleza': Icons.content_cut_rounded,
  'roupa': Icons.checkroom_rounded,
  'tech': Icons.devices_rounded,
  'games': Icons.sports_esports_rounded,
  'viagem': Icons.flight_rounded,
  'carro': Icons.build_rounded,
  'bar': Icons.local_bar_rounded,
  'cafe': Icons.local_cafe_rounded,
  'mercado': Icons.local_grocery_store_rounded,
  'trabalho': Icons.work_rounded,
  'doacao': Icons.volunteer_activism_rounded,
  'igreja': Icons.church_rounded,
  'musica': Icons.music_note_rounded,
  'livro': Icons.menu_book_rounded,
  'impostos': Icons.account_balance_rounded,
  'celular': Icons.smartphone_rounded,
  'estrela': Icons.star_rounded,
};

const colorChoices = <Color>[
  Color(0xFFF97316), Color(0xFFEAB308), Color(0xFF84CC16), Color(0xFF10B981),
  Color(0xFF14B8A6), Color(0xFF0EA5E9), Color(0xFF6366F1), Color(0xFFA855F7),
  Color(0xFFEC4899), Color(0xFFF43F5E), Color(0xFF78716C), Color(0xFF111111),
];

/// Categorias criadas pelo usuário (carregadas do Firestore).
List<Cat> customCats = [];

List<Cat> get allCats => [
      ...builtinCats.where((c) => c.name != 'Outros'),
      ...customCats,
      builtinCats.last,
    ];

/// Mantém compatibilidade com o código que usa `cats`.
List<Cat> get cats => allCats;

/// Categorias que contam como "gasto" no mês.
List<String> get spendingCats =>
    allCats.map((c) => c.name).where((n) => n != 'Renda' && n != 'Investimentos').toList();

Cat catOf(String name) => allCats.firstWhere((c) => c.name == name, orElse: () => builtinCats.last);

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

DateTime monthOf(DateTime d) => DateTime(d.year, d.month);
int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

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
  String source; // manual | nubank | jose | parcela
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

/// Regra do usuário: se a descrição contém [pattern], vira [category].
class Rule {
  Rule({required this.id, required this.pattern, required this.category});
  final String id;
  String pattern;
  String category;

  bool matches(String description) =>
      pattern.trim().isNotEmpty && description.toLowerCase().contains(pattern.trim().toLowerCase());

  Map<String, dynamic> toMap() => {'pattern': pattern, 'category': category};

  factory Rule.fromMap(String id, Map<String, dynamic> m) =>
      Rule(id: id, pattern: '${m['pattern'] ?? ''}', category: '${m['category'] ?? 'Outros'}');
}

/// Dívida, financiamento ou compra parcelada.
class Debt {
  Debt({
    required this.id,
    required this.name,
    required this.kind,
    required this.installmentAmount,
    required this.installments,
    required this.firstDue,
    this.interestMonthly = 0,
    this.autoLaunch = true,
    this.category = 'Dívidas',
  });

  final String id;
  String name;
  String kind; // cartao | emprestimo | financiamento | outro
  double installmentAmount;
  int installments;
  DateTime firstDue; // vencimento da 1ª parcela
  double interestMonthly; // % ao mês (informativo)
  bool autoLaunch; // lança cada parcela como gasto no mês
  String category;

  DateTime dueOf(int k) {
    final m = DateTime(firstDue.year, firstDue.month + k);
    final d = min(firstDue.day, daysInMonth(m.year, m.month));
    return DateTime(m.year, m.month, d);
  }

  /// Parcelas já vencidas até hoje (consideradas pagas).
  int paidCount([DateTime? now]) {
    final today = now ?? DateTime.now();
    var n = 0;
    for (var k = 0; k < installments; k++) {
      if (!dueOf(k).isAfter(today)) n++;
    }
    return n;
  }

  int remainingCount([DateTime? now]) => installments - paidCount(now);
  double get total => installmentAmount * installments;
  double remainingAmount([DateTime? now]) => remainingCount(now) * installmentAmount;
  bool get finished => remainingCount() == 0;

  DateTime? nextDue([DateTime? now]) {
    final p = paidCount(now);
    return p >= installments ? null : dueOf(p);
  }

  /// Quanto desta dívida cai no mês [m].
  double amountInMonth(DateTime m) {
    var s = 0.0;
    for (var k = 0; k < installments; k++) {
      final d = dueOf(k);
      if (d.year == m.year && d.month == m.month) s += installmentAmount;
    }
    return s;
  }

  String get kindLabel => switch (kind) {
        'cartao' => 'Parcelado no cartão',
        'emprestimo' => 'Empréstimo',
        'financiamento' => 'Financiamento',
        _ => 'Outra dívida',
      };

  Map<String, dynamic> toMap() => {
        'name': name,
        'kind': kind,
        'installmentAmount': installmentAmount,
        'installments': installments,
        'firstDue': firstDue,
        'interestMonthly': interestMonthly,
        'autoLaunch': autoLaunch,
        'category': category,
      };

  factory Debt.fromMap(String id, Map<String, dynamic> m) => Debt(
        id: id,
        name: '${m['name'] ?? ''}',
        kind: '${m['kind'] ?? 'outro'}',
        installmentAmount: ((m['installmentAmount'] ?? 0) as num).toDouble(),
        installments: ((m['installments'] ?? 1) as num).toInt(),
        firstDue: (m['firstDue'] is DateTime) ? m['firstDue'] as DateTime : DateTime.now(),
        interestMonthly: ((m['interestMonthly'] ?? 0) as num).toDouble(),
        autoLaunch: (m['autoLaunch'] ?? true) as bool,
        category: '${m['category'] ?? 'Dívidas'}',
      );
}

/// Algo que o José lembra sobre o usuário.
class Memory {
  Memory({required this.id, required this.text, required this.createdAt});
  final String id;
  String text;
  DateTime createdAt;

  Map<String, dynamic> toMap() => {'text': text, 'createdAt': createdAt};

  factory Memory.fromMap(String id, Map<String, dynamic> m) => Memory(
        id: id,
        text: '${m['text'] ?? ''}',
        createdAt: (m['createdAt'] is DateTime) ? m['createdAt'] as DateTime : DateTime.now(),
      );
}

class Profile {
  Profile({
    this.name = '',
    this.risk = 'moderado',
    this.horizon = 'medio',
    this.knowledge = 'iniciante',
    this.monthlyIncome = 0,
    this.payday = 0,
    this.goals = '',
    this.geminiKey = '',
  });

  String name;
  String risk; // conservador | moderado | arrojado
  String horizon; // curto | medio | longo
  String knowledge; // iniciante | intermediario | avancado
  double monthlyIncome;
  int payday; // dia do salário (0 = não informado)
  String goals;
  String geminiKey; // opcional: sobrescreve a chave embutida

  Map<String, dynamic> toMap() => {
        'name': name,
        'risk': risk,
        'horizon': horizon,
        'knowledge': knowledge,
        'monthlyIncome': monthlyIncome,
        'payday': payday,
        'goals': goals,
        'geminiKey': geminiKey,
      };

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        name: (m['name'] ?? '') as String,
        risk: (m['risk'] ?? 'moderado') as String,
        horizon: (m['horizon'] ?? 'medio') as String,
        knowledge: (m['knowledge'] ?? 'iniciante') as String,
        monthlyIncome: ((m['monthlyIncome'] ?? 0) as num).toDouble(),
        payday: ((m['payday'] ?? 0) as num).toInt(),
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
  ChatMsgError(super.text) : super(fromUser: false);
}

/// Gasto que se repete todo mês (detectado automaticamente).
class Recurring {
  Recurring(this.name, this.avgAmount, this.months, this.category);
  final String name;
  final double avgAmount;
  final int months;
  final String category;
}
