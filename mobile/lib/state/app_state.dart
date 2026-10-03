import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models.dart';
import '../services/auth_service.dart';
import '../services/capture.dart';
import '../services/firestore.dart';
import '../services/gemini.dart';

class AppAlert {
  AppAlert(this.title, this.body, this.level);
  final String title;
  final String body;
  final String level; // danger | warn | info | good
}

/// Estado global do app.
class AppState extends ChangeNotifier {
  final auth = AuthService();
  late final Firestore fs = Firestore(auth);
  final gemini = Gemini();

  bool booting = true;
  bool loading = false;
  String? error;

  List<Tx> txs = [];
  Map<String, double> budgets = {};
  List<Investment> investments = [];
  Profile profile = Profile();
  final List<ChatMsg> chat = [];

  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  bool captureEnabled = false;
  bool _syncing = false;

  String get _u => 'users/${auth.uid}';

  void refresh() => notifyListeners();

  // ---------- ciclo de vida ----------

  Future<void> boot() async {
    await auth.restore();
    if (auth.signedIn) {
      await loadAll();
    }
    booting = false;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    await auth.signIn(email, password);
    await loadAll();
  }

  Future<void> signUp(String email, String password, String name) async {
    await auth.signUp(email, password, name);
    profile = Profile(name: name.trim());
    try {
      await fs.set(_u, {...profile.toMap(), 'email': auth.email, 'createdAt': DateTime.now()});
    } catch (e) {
      error = '$e';
    }
    await loadAll();
  }

  Future<void> signOut() async {
    await auth.signOut();
    txs = [];
    budgets = {};
    investments = [];
    profile = Profile();
    chat.clear();
    gemini.apiKey = '';
    notifyListeners();
  }

  Future<void> loadAll() async {
    if (!auth.signedIn) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        fs.getDoc(_u),
        fs.list('$_u/transactions'),
        fs.list('$_u/budgets'),
        fs.list('$_u/investments'),
      ]);
      final p = results[0] as Map<String, dynamic>?;
      profile = p == null ? Profile(name: auth.displayName ?? '') : Profile.fromMap(p);
      if (profile.name.isEmpty) profile.name = auth.displayName ?? '';
      gemini.apiKey = profile.geminiKey;
      txs = (results[1] as List<FsDoc>).map((d) => Tx.fromMap(d.id, d.data)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      budgets = {
        for (final d in results[2] as List<FsDoc>)
          '${d.data['category'] ?? d.id}': ((d.data['limit'] ?? 0) as num).toDouble()
      };
      investments = (results[3] as List<FsDoc>).map((d) => Investment.fromMap(d.id, d.data)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
    unawaited(syncCaptured());
  }

  // ---------- transações ----------

  Future<void> saveTx(Tx t) async {
    final i = txs.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      txs[i] = t;
    } else {
      txs.add(t);
    }
    txs.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    try {
      await fs.set('$_u/transactions/${t.id}', t.toMap());
    } catch (e) {
      error = 'Não salvou na nuvem: $e';
      notifyListeners();
    }
  }

  Future<void> deleteTx(Tx t) async {
    txs.removeWhere((x) => x.id == t.id);
    notifyListeners();
    try {
      await fs.delete('$_u/transactions/${t.id}');
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  // ---------- metas ----------

  Future<void> setBudget(String category, double limit) async {
    budgets[category] = limit;
    notifyListeners();
    await fs.set('$_u/budgets/${stableHash(category)}', {'category': category, 'limit': limit});
  }

  Future<void> removeBudget(String category) async {
    budgets.remove(category);
    notifyListeners();
    await fs.delete('$_u/budgets/${stableHash(category)}');
  }

  // ---------- investimentos ----------

  Future<void> saveInvestment(Investment inv) async {
    investments.removeWhere((x) => x.id == inv.id);
    investments.insert(0, inv);
    notifyListeners();
    await fs.set('$_u/investments/${inv.id}', inv.toMap());
  }

  Future<void> deleteInvestment(Investment inv) async {
    investments.removeWhere((x) => x.id == inv.id);
    notifyListeners();
    await fs.delete('$_u/investments/${inv.id}');
  }

  // ---------- perfil ----------

  Future<void> saveProfile(Profile p) async {
    profile = p;
    gemini.apiKey = p.geminiKey;
    notifyListeners();
    await fs.merge(_u, {...p.toMap(), 'email': auth.email});
  }

  // ---------- captura do Nubank ----------

  Future<void> refreshCaptureStatus() async {
    final on = await CaptureBridge.isEnabled();
    if (on != captureEnabled) {
      captureEnabled = on;
      notifyListeners();
    }
  }

  /// Puxa as notificações capturadas e vira transações. Devolve quantas entraram.
  Future<int> syncCaptured() async {
    if (_syncing || !auth.signedIn || !CaptureBridge.supported) return 0;
    _syncing = true;
    var added = 0;
    try {
      final items = await CaptureBridge.drain();
      for (final n in items) {
        if (await ingestNotification(n.title, n.text, n.time)) added++;
      }
      if (added > 0) unawaited(aiCategorizePending());
    } finally {
      _syncing = false;
    }
    return added;
  }

  /// Usado pela captura real e pelo botão "Simular notificação".
  Future<bool> ingestNotification(String title, String text, DateTime when) async {
    final p = parseBankNotification(title, text);
    if (p == null) return false;
    final minute = DateTime(when.year, when.month, when.day, when.hour, when.minute);
    final id = 'nu_${stableHash('$title|$text|${minute.millisecondsSinceEpoch}')}';
    if (txs.any((t) => t.id == id)) return false;
    await saveTx(Tx(
      id: id,
      description: p.description,
      amount: p.amount,
      isIncome: p.isIncome,
      category: p.category,
      date: when,
      source: 'nubank',
      raw: '$title — $text',
    ));
    return true;
  }

  /// Manda pro José tudo que ficou em "Outros".
  Future<int> aiCategorizePending() async {
    if (!gemini.configured) return 0;
    final pending = txs.where((t) => t.category == 'Outros' && !t.aiCategorized && !t.isIncome).take(40).toList();
    if (pending.isEmpty) return 0;
    final names = cats.map((c) => c.name).join(', ');
    final lines = pending.map((t) => '${t.id} | ${t.description} | R\$ ${t.amount.toStringAsFixed(2)}').join('\n');
    try {
      final res = await gemini.generateJson(
        prompt: 'Classifique cada gasto brasileiro abaixo em UMA destas categorias: $names.\n'
            'Responda só um objeto JSON {"id": "Categoria"}.\n\n$lines',
        temperature: 0.1,
      );
      if (res is! Map) return 0;
      var changed = 0;
      for (final t in pending) {
        final c = res[t.id];
        t.aiCategorized = true;
        if (c is String && cats.any((x) => x.name == c) && c != t.category) {
          t.category = c;
          changed++;
        }
        await fs.set('$_u/transactions/${t.id}', t.toMap());
      }
      notifyListeners();
      return changed;
    } catch (_) {
      return 0;
    }
  }

  // ---------- números do mês ----------

  void shiftMonth(int delta) {
    month = DateTime(month.year, month.month + delta);
    notifyListeners();
  }

  List<Tx> txsOf(DateTime m) =>
      txs.where((t) => t.date.year == m.year && t.date.month == m.month).toList();

  double spentIn(DateTime m, {String? category}) => txsOf(m)
      .where((t) => !t.isIncome && spendingCats.contains(t.category))
      .where((t) => category == null || t.category == category)
      .fold(0.0, (s, t) => s + t.amount);

  double incomeIn(DateTime m) => txsOf(m).where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);

  double investedIn(DateTime m) =>
      txsOf(m).where((t) => !t.isIncome && t.category == 'Investimentos').fold(0.0, (s, t) => s + t.amount) +
      investments
          .where((i) => i.date.year == m.year && i.date.month == m.month)
          .fold(0.0, (s, i) => s + i.amount);

  Map<String, double> byCategory(DateTime m) {
    final out = <String, double>{};
    for (final t in txsOf(m)) {
      if (t.isIncome || !spendingCats.contains(t.category)) continue;
      out[t.category] = (out[t.category] ?? 0) + t.amount;
    }
    final sorted = out.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in sorted) e.key: e.value};
  }

  double get totalInvested => investments.fold(0.0, (s, i) => s + i.amount);

  List<AppAlert> alerts() {
    final out = <AppAlert>[];
    final now = DateTime.now();
    final cur = DateTime(now.year, now.month);
    final prev = DateTime(now.year, now.month - 1);
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    for (final e in budgets.entries) {
      if (e.value <= 0) continue;
      final spent = spentIn(cur, category: e.key);
      final pct = spent / e.value;
      if (pct >= 1) {
        out.add(AppAlert('Meta de ${e.key} estourada',
            'Você gastou ${money.format(spent)} de ${money.format(e.value)}.', 'danger'));
      } else if (pct >= 0.8) {
        out.add(AppAlert('${e.key} perto do limite',
            '${(pct * 100).round()}% da meta usada. Restam ${money.format(e.value - spent)}.', 'warn'));
      }
    }

    final prevCats = byCategory(prev);
    final dayFactor = now.day / _daysInMonth(now.year, now.month);
    byCategory(cur).forEach((cat, value) {
      final before = prevCats[cat] ?? 0;
      if (before < 50) return;
      final expectedSoFar = before * dayFactor;
      if (value > expectedSoFar * 1.3 && value - expectedSoFar > 50) {
        out.add(AppAlert('Ritmo alto em $cat',
            'Já foram ${money.format(value)}; no mesmo ponto do mês passado eram ~${money.format(expectedSoFar)}.',
            'warn'));
      }
    });

    final income = incomeIn(cur) > 0 ? incomeIn(cur) : profile.monthlyIncome;
    final left = income - spentIn(cur);
    if (income > 0 && left > 100 && investedIn(cur) == 0) {
      out.add(AppAlert('Sobrou ${money.format(left)} este mês',
          'Pergunte ao ${AppConfig.assistantName} onde investir isso.', 'good'));
    }
    return out;
  }

  /// Resumo financeiro que vai junto em toda conversa com o José Pinto.
  String financialContext() {
    final now = DateTime.now();
    final cur = DateTime(now.year, now.month);
    final prev = DateTime(now.year, now.month - 1);
    final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final df = DateFormat('dd/MM');
    final b = StringBuffer();
    b.writeln('Nome: ${profile.name.isEmpty ? 'não informado' : profile.name}');
    b.writeln('Perfil de investidor: risco ${profile.risk}, horizonte ${profile.horizon}, conhecimento ${profile.knowledge}');
    if (profile.monthlyIncome > 0) b.writeln('Renda mensal declarada: ${f.format(profile.monthlyIncome)}');
    if (profile.goals.isNotEmpty) b.writeln('Objetivos: ${profile.goals}');
    b.writeln('\nMês atual (${DateFormat('MM/yyyy').format(cur)}, dia ${now.day}): gastos ${f.format(spentIn(cur))}, '
        'entradas ${f.format(incomeIn(cur))}, investido ${f.format(investedIn(cur))}');
    byCategory(cur).forEach((k, v) => b.writeln('  • $k: ${f.format(v)}${budgets[k] != null ? ' (meta ${f.format(budgets[k]!)})' : ''}'));
    b.writeln('Mês anterior: gastos ${f.format(spentIn(prev))}, entradas ${f.format(incomeIn(prev))}');
    byCategory(prev).forEach((k, v) => b.writeln('  • $k: ${f.format(v)}'));
    final metasSemGasto = budgets.keys.where((k) => !byCategory(cur).containsKey(k));
    if (metasSemGasto.isNotEmpty) b.writeln('Outras metas: ${metasSemGasto.map((k) => '$k ${f.format(budgets[k]!)}').join(', ')}');
    if (investments.isNotEmpty) {
      b.writeln('\nCarteira (total ${f.format(totalInvested)}):');
      for (final i in investments.take(15)) {
        b.writeln('  • ${i.name} (${i.kind}): ${f.format(i.amount)}');
      }
    }
    final recent = txs.take(40);
    if (recent.isNotEmpty) {
      b.writeln('\nÚltimas transações:');
      for (final t in recent) {
        b.writeln('  • ${df.format(t.date)} ${t.isIncome ? '+' : '-'}${f.format(t.amount)} ${t.description} [${t.category}]');
      }
    }
    return b.toString();
  }
}

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;
