import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models.dart';
import '../services/auth_service.dart';
import '../services/capture.dart';
import '../services/categorizer.dart';
import '../services/firestore.dart';
import '../services/gemini.dart';
import '../services/native.dart';

class AppAlert {
  AppAlert(this.title, this.body, this.level);
  final String title;
  final String body;
  final String level; // danger | warn | info | good
}

class Forecast {
  Forecast({required this.spentSoFar, required this.projected, required this.pendingInstallments, required this.income});
  final double spentSoFar;
  final double projected;
  final double pendingInstallments;
  final double income;
  double get freeAtEnd => income - projected;
}

/// Preferências de notificação (guardadas no aparelho).
class NotifPrefs {
  bool budget = true;
  bool weekly = true;
  bool debts = true;
  bool capture = true;
  bool payday = true;
}

final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

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
  List<Rule> rules = [];
  List<Debt> debts = [];
  List<Memory> memories = [];
  Profile profile = Profile();
  final List<ChatMsg> chat = [];
  final notif = NotifPrefs();

  DateTime month = monthOf(DateTime.now());

  bool captureEnabled = false;
  bool _syncing = false;
  Timer? _afterChangeTimer;

  String get _u => 'users/${auth.uid}';

  void refresh() => notifyListeners();

  // ---------- ciclo de vida ----------

  Future<void> boot() async {
    gemini.apiKey = AppConfig.embeddedGeminiKey;
    await _loadNotifPrefs();
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
    rules = [];
    debts = [];
    memories = [];
    customCats = [];
    profile = Profile();
    chat.clear();
    gemini.apiKey = AppConfig.embeddedGeminiKey;
    notifyListeners();
  }

  Future<void> loadAll() async {
    if (!auth.signedIn) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final r = await Future.wait([
        fs.getDoc(_u),
        fs.list('$_u/transactions'),
        fs.list('$_u/budgets'),
        fs.list('$_u/investments'),
        _safeList('$_u/categories'),
        _safeList('$_u/rules'),
        _safeList('$_u/debts'),
        _safeList('$_u/memories'),
      ]);
      final p = r[0] as Map<String, dynamic>?;
      profile = p == null ? Profile(name: auth.displayName ?? '') : Profile.fromMap(p);
      if (profile.name.isEmpty) profile.name = auth.displayName ?? '';
      gemini.apiKey = profile.geminiKey.trim().isNotEmpty ? profile.geminiKey.trim() : AppConfig.embeddedGeminiKey;

      customCats = [
        for (final d in r[4] as List<FsDoc>)
          Cat(
            '${d.data['name']}',
            iconChoices['${d.data['icon']}'] ?? Icons.star_rounded,
            Color(((d.data['color'] ?? 0xFF111111) as num).toInt()),
            custom: true,
            id: d.id,
          )
      ];
      txs = (r[1] as List<FsDoc>).map((d) => Tx.fromMap(d.id, d.data)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      budgets = {
        for (final d in r[2] as List<FsDoc>) '${d.data['category'] ?? d.id}': ((d.data['limit'] ?? 0) as num).toDouble()
      };
      investments = (r[3] as List<FsDoc>).map((d) => Investment.fromMap(d.id, d.data)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      rules = (r[5] as List<FsDoc>).map((d) => Rule.fromMap(d.id, d.data)).toList();
      debts = (r[6] as List<FsDoc>).map((d) => Debt.fromMap(d.id, d.data)).toList()
        ..sort((a, b) => a.firstDue.compareTo(b.firstDue));
      memories = (r[7] as List<FsDoc>).map((d) => Memory.fromMap(d.id, d.data)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
    await ensureDebtInstallments();
    unawaited(syncCaptured());
    _scheduleAfterChange();
  }

  /// Coleções novas: se as regras do Firestore ainda não as liberam, não derruba o app.
  Future<List<FsDoc>> _safeList(String path) async {
    try {
      return await fs.list(path);
    } catch (e) {
      error ??= 'Algumas funções novas precisam das regras atualizadas do Firestore (arquivo mobile/firestore.rules).';
      return <FsDoc>[];
    }
  }

  // ---------- categorias e regras ----------

  /// Regras do usuário primeiro, depois palavras-chave.
  String categorize(String description, {bool isIncome = false}) {
    for (final r in rules) {
      if (r.matches(description) && (!isIncome || r.category == 'Renda')) return r.category;
    }
    return guessCategory(description, isIncome: isIncome);
  }

  Future<void> addCategory(String name, String iconKey, Color color) async {
    final n = name.trim();
    if (n.isEmpty || allCats.any((c) => c.name.toLowerCase() == n.toLowerCase())) {
      throw Exception('Já existe uma categoria com esse nome.');
    }
    final id = newId();
    customCats = [...customCats, Cat(n, iconChoices[iconKey] ?? Icons.star_rounded, color, custom: true, id: id)];
    notifyListeners();
    await fs.set('$_u/categories/$id', {'name': n, 'icon': iconKey, 'color': color.toARGB32()});
  }

  Future<void> deleteCategory(Cat c) async {
    customCats = customCats.where((x) => x.id != c.id).toList();
    for (final t in txs.where((t) => t.category == c.name)) {
      t.category = 'Outros';
      unawaited(fs.set('$_u/transactions/${t.id}', t.toMap()));
    }
    notifyListeners();
    if (c.id != null) await fs.delete('$_u/categories/${c.id}');
  }

  Future<Rule> addRule(String pattern, String category) async {
    final rule = Rule(id: newId(), pattern: pattern.trim(), category: category);
    rules = [...rules.where((r) => r.pattern.toLowerCase() != rule.pattern.toLowerCase()), rule];
    notifyListeners();
    await fs.set('$_u/rules/${rule.id}', rule.toMap());
    return rule;
  }

  Future<void> deleteRule(Rule r) async {
    rules = rules.where((x) => x.id != r.id).toList();
    notifyListeners();
    await fs.delete('$_u/rules/${r.id}');
  }

  /// Reaplica as regras em todos os lançamentos. Devolve quantos mudaram.
  Future<int> applyRulesToAll() async {
    var n = 0;
    for (final t in txs) {
      for (final r in rules) {
        if (r.matches(t.description) && t.category != r.category && !t.isIncome) {
          t.category = r.category;
          n++;
          await fs.set('$_u/transactions/${t.id}', t.toMap());
          break;
        }
      }
    }
    notifyListeners();
    _scheduleAfterChange();
    return n;
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
    _scheduleAfterChange();
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
    _scheduleAfterChange();
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
    _scheduleAfterChange();
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

  // ---------- dívidas e parcelas ----------

  Future<void> saveDebt(Debt d) async {
    debts.removeWhere((x) => x.id == d.id);
    debts.add(d);
    debts.sort((a, b) => a.firstDue.compareTo(b.firstDue));
    notifyListeners();
    await fs.set('$_u/debts/${d.id}', d.toMap());
    await ensureDebtInstallments();
    _scheduleAfterChange();
  }

  Future<void> deleteDebt(Debt d, {bool removeLaunched = false}) async {
    debts.removeWhere((x) => x.id == d.id);
    if (removeLaunched) {
      for (final t in txs.where((t) => t.id.startsWith('parc_${d.id}_')).toList()) {
        await deleteTx(t);
      }
    }
    notifyListeners();
    await fs.delete('$_u/debts/${d.id}');
    _scheduleAfterChange();
  }

  /// Lança como gasto cada parcela que já venceu (uma vez só).
  Future<void> ensureDebtInstallments() async {
    final now = DateTime.now();
    for (final d in debts.where((d) => d.autoLaunch)) {
      for (var k = 0; k < d.installments; k++) {
        final due = d.dueOf(k);
        if (due.isAfter(now)) break;
        final id = 'parc_${d.id}_$k';
        if (txs.any((t) => t.id == id)) continue;
        await saveTx(Tx(
          id: id,
          description: '${d.name} (${k + 1}/${d.installments})',
          amount: d.installmentAmount,
          isIncome: false,
          category: d.category,
          date: DateTime(due.year, due.month, due.day, 9),
          source: 'parcela',
        ));
      }
    }
  }

  double commitmentsIn(DateTime m) => debts.fold(0.0, (s, d) => s + d.amountInMonth(m));

  double get totalDebtRemaining => debts.fold(0.0, (s, d) => s + d.remainingAmount());

  // ---------- memória do José ----------

  Future<void> addMemory(String text) async {
    final t = text.trim();
    if (t.isEmpty || memories.any((m) => m.text.toLowerCase() == t.toLowerCase())) return;
    final m = Memory(id: newId(), text: t, createdAt: DateTime.now());
    memories.add(m);
    notifyListeners();
    await fs.set('$_u/memories/${m.id}', m.toMap());
  }

  Future<void> deleteMemory(Memory m) async {
    memories.removeWhere((x) => x.id == m.id);
    notifyListeners();
    await fs.delete('$_u/memories/${m.id}');
  }

  // ---------- perfil ----------

  Future<void> saveProfile(Profile p) async {
    profile = p;
    gemini.apiKey = p.geminiKey.trim().isNotEmpty ? p.geminiKey.trim() : AppConfig.embeddedGeminiKey;
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

  Future<bool> ingestNotification(String title, String text, DateTime when) async {
    final p = parseBankNotification(title, text);
    if (p == null) return false;
    final minute = DateTime(when.year, when.month, when.day, when.hour, when.minute);
    final id = 'nu_${stableHash('$title|$text|${minute.millisecondsSinceEpoch}')}';
    if (txs.any((t) => t.id == id)) return false;
    var category = p.category;
    if (!p.isIncome) {
      final byRule = categorize(p.description);
      if (byRule != 'Outros') category = byRule;
    }
    await saveTx(Tx(
      id: id,
      description: p.description,
      amount: p.amount,
      isIncome: p.isIncome,
      category: category,
      date: when,
      source: 'nubank',
      raw: '$title — $text',
    ));
    return true;
  }

  Future<int> aiCategorizePending() async {
    if (!gemini.configured) return 0;
    final pending = txs.where((t) => t.category == 'Outros' && !t.aiCategorized && !t.isIncome).take(40).toList();
    if (pending.isEmpty) return 0;
    final names = allCats.map((c) => c.name).join(', ');
    final lines = pending.map((t) => '${t.id} | ${t.description} | R\$ ${t.amount.toStringAsFixed(2)}').join('\n');
    try {
      final res = await gemini.generateJson(
        prompt: 'Classifique cada gasto brasileiro abaixo em UMA destas categorias: $names.\n'
            'Responda só um objeto JSON {"id": "Categoria"}.\n\n$lines',
        temperature: 0.1,
        fast: true,
      );
      if (res is! Map) return 0;
      var changed = 0;
      for (final t in pending) {
        final c = res[t.id];
        t.aiCategorized = true;
        if (c is String && allCats.any((x) => x.name == c) && c != t.category) {
          t.category = c;
          changed++;
        }
        await fs.set('$_u/transactions/${t.id}', t.toMap());
      }
      notifyListeners();
      _scheduleAfterChange();
      return changed;
    } catch (_) {
      return 0;
    }
  }

  // ---------- números ----------

  void shiftMonth(int delta) {
    month = DateTime(month.year, month.month + delta);
    notifyListeners();
  }

  List<Tx> txsOf(DateTime m) => txs.where((t) => t.date.year == m.year && t.date.month == m.month).toList();

  double spentIn(DateTime m, {String? category}) => txsOf(m)
      .where((t) => !t.isIncome && spendingCats.contains(t.category))
      .where((t) => category == null || t.category == category)
      .fold(0.0, (s, t) => s + t.amount);

  double spentOnDay(DateTime d) => txs
      .where((t) => !t.isIncome && spendingCats.contains(t.category))
      .where((t) => t.date.year == d.year && t.date.month == d.month && t.date.day == d.day)
      .fold(0.0, (s, t) => s + t.amount);

  double incomeIn(DateTime m) => txsOf(m).where((t) => t.isIncome).fold(0.0, (s, t) => s + t.amount);

  double investedIn(DateTime m) =>
      txsOf(m).where((t) => !t.isIncome && t.category == 'Investimentos').fold(0.0, (s, t) => s + t.amount) +
      investments.where((i) => i.date.year == m.year && i.date.month == m.month).fold(0.0, (s, i) => s + i.amount);

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

  /// Média de gastos dos últimos [n] meses fechados (ignora meses vazios).
  double avgMonthlySpend([int n = 3]) {
    final now = DateTime.now();
    final vals = [
      for (var i = 1; i <= n; i++) spentIn(DateTime(now.year, now.month - i))
    ].where((v) => v > 0).toList();
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  double avgCategorySpend(String category, [int n = 3]) {
    final now = DateTime.now();
    final vals = [for (var i = 1; i <= n; i++) spentIn(DateTime(now.year, now.month - i), category: category)];
    final nonZero = vals.where((v) => v > 0).length;
    if (nonZero == 0) return spentIn(monthOf(now), category: category);
    return vals.reduce((a, b) => a + b) / nonZero;
  }

  /// Renda de referência: entradas do mês, senão do mês anterior, senão a declarada.
  double get referenceIncome {
    final now = DateTime.now();
    final cur = incomeIn(monthOf(now));
    final prev = incomeIn(DateTime(now.year, now.month - 1));
    return [cur, prev, profile.monthlyIncome].reduce(max);
  }

  /// Previsão de quanto o mês atual vai fechar.
  Forecast forecast() {
    final now = DateTime.now();
    final m = monthOf(now);
    final dim = daysInMonth(now.year, now.month);
    final spent = spentIn(m);
    // Gastos do dia a dia (sem parcelas automáticas, que são previsíveis)
    final variable = txsOf(m)
        .where((t) => !t.isIncome && spendingCats.contains(t.category) && t.source != 'parcela')
        .fold(0.0, (s, t) => s + t.amount);
    final linear = variable / now.day * dim;
    final prevAvg = avgMonthlySpend();
    final w = now.day / dim;
    var projectedVariable = prevAvg > 0 ? w * linear + (1 - w) * max(prevAvg - _avgInstallments(), variable) : linear;
    projectedVariable = max(projectedVariable, variable);
    // Parcelas que ainda vão cair este mês
    var pending = 0.0;
    for (final d in debts.where((d) => d.autoLaunch)) {
      for (var k = 0; k < d.installments; k++) {
        final due = d.dueOf(k);
        if (due.year == m.year && due.month == m.month && due.isAfter(now)) pending += d.installmentAmount;
      }
    }
    final launched = spent - variable;
    return Forecast(
      spentSoFar: spent,
      projected: projectedVariable + launched + pending,
      pendingInstallments: pending,
      income: referenceIncome,
    );
  }

  double _avgInstallments() {
    final now = DateTime.now();
    var s = 0.0;
    for (var i = 1; i <= 3; i++) {
      s += commitmentsIn(DateTime(now.year, now.month - i));
    }
    return s / 3;
  }

  /// Gastos que se repetem (assinaturas, contas fixas).
  List<Recurring> recurring() {
    final now = DateTime.now();
    final since = DateTime(now.year, now.month - 4);
    final groups = <String, List<Tx>>{};
    for (final t in txs.where((t) => !t.isIncome && t.date.isAfter(since) && t.source != 'parcela')) {
      final key = t.description.toLowerCase().replaceAll(RegExp(r'[0-9*#()/.\-]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (key.length < 3) continue;
      groups.putIfAbsent(key, () => []).add(t);
    }
    final out = <Recurring>[];
    groups.forEach((key, list) {
      final months = list.map((t) => '${t.date.year}-${t.date.month}').toSet();
      if (months.length < 2) return;
      final amounts = list.map((t) => t.amount).toList();
      final avg = amounts.reduce((a, b) => a + b) / amounts.length;
      final similar = amounts.every((a) => (a - avg).abs() <= max(avg * 0.25, 5));
      if (!similar) return;
      out.add(Recurring(list.first.description, avg, months.length, list.first.category));
    });
    out.sort((a, b) => b.avgAmount.compareTo(a.avgAmount));
    return out;
  }

  /// Quantos meses de gastos o dinheiro investido cobre.
  double get emergencyMonths {
    final avg = avgMonthlySpend();
    if (avg <= 0) return 0;
    return totalInvested / avg;
  }

  List<AppAlert> alerts() {
    final out = <AppAlert>[];
    final now = DateTime.now();
    final cur = monthOf(now);
    final prev = DateTime(now.year, now.month - 1);

    for (final e in budgets.entries) {
      if (e.value <= 0) continue;
      final spent = spentIn(cur, category: e.key);
      final pct = spent / e.value;
      if (pct >= 1) {
        out.add(AppAlert('Meta de ${e.key} estourada', 'Você gastou ${_money.format(spent)} de ${_money.format(e.value)}.', 'danger'));
      } else if (pct >= 0.8) {
        out.add(AppAlert('${e.key} perto do limite',
            '${(pct * 100).round()}% da meta usada. Restam ${_money.format(e.value - spent)}.', 'warn'));
      }
    }

    final f = forecast();
    if (f.income > 0 && f.projected > f.income && now.day >= 5) {
      out.add(AppAlert('O mês pode fechar no vermelho',
          'Previsão de ${_money.format(f.projected)} em gastos para ${_money.format(f.income)} de renda.', 'danger'));
    }

    final prevCats = byCategory(prev);
    final dayFactor = now.day / daysInMonth(now.year, now.month);
    byCategory(cur).forEach((cat, value) {
      final before = prevCats[cat] ?? 0;
      if (before < 50) return;
      final expectedSoFar = before * dayFactor;
      if (value > expectedSoFar * 1.3 && value - expectedSoFar > 50) {
        out.add(AppAlert('Ritmo alto em $cat',
            'Já foram ${_money.format(value)}; no mesmo ponto do mês passado eram ~${_money.format(expectedSoFar)}.', 'warn'));
      }
    });

    for (final d in debts) {
      final next = d.nextDue();
      if (next == null) continue;
      final days = next.difference(DateTime(now.year, now.month, now.day)).inDays;
      if (days >= 0 && days <= 3) {
        out.add(AppAlert('Parcela de ${d.name} vence ${days == 0 ? 'hoje' : 'em $days dia${days > 1 ? 's' : ''}'}',
            '${_money.format(d.installmentAmount)} — parcela ${d.paidCount() + 1} de ${d.installments}.', 'warn'));
      }
    }

    final income = f.income;
    final left = income - spentIn(cur);
    if (income > 0 && left > 100 && investedIn(cur) == 0 && now.day >= 10) {
      out.add(AppAlert('Sobrou ${_money.format(left)} até agora',
          'Pergunte ao ${AppConfig.assistantName} onde investir isso.', 'good'));
    }
    return out;
  }

  // ---------- widget e notificações ----------

  Future<void> _loadNotifPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      notif.budget = p.getBool('notif_budget') ?? true;
      notif.weekly = p.getBool('notif_weekly') ?? true;
      notif.debts = p.getBool('notif_debts') ?? true;
      notif.capture = p.getBool('notif_capture') ?? true;
      notif.payday = p.getBool('notif_payday') ?? true;
    } catch (_) {}
  }

  Future<void> setNotifPref(String key, bool value) async {
    switch (key) {
      case 'budget':
        notif.budget = value;
      case 'weekly':
        notif.weekly = value;
      case 'debts':
        notif.debts = value;
      case 'capture':
        notif.capture = value;
      case 'payday':
        notif.payday = value;
    }
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool('notif_$key', value);
    if (key == 'capture') await NativeBridge.setFlag('notify_capture', value);
    _scheduleAfterChange();
  }

  void _scheduleAfterChange() {
    _afterChangeTimer?.cancel();
    _afterChangeTimer = Timer(const Duration(seconds: 2), () => unawaited(_afterChange()));
  }

  Future<void> _afterChange() async {
    if (!auth.signedIn) return;
    await _updateWidget();
    await _checkBudgetNotifications();
    await _scheduleReminders();
  }

  Future<void> _updateWidget() async {
    final now = DateTime.now();
    final m = monthOf(now);
    final f = forecast();
    final budgetTotal = budgets.values.fold(0.0, (s, v) => s + v);
    final budgetSpent = budgets.keys.fold(0.0, (s, c) => s + spentIn(m, category: c));
    await NativeBridge.updateWidget({
      'today': _money.format(spentOnDay(now)),
      'month': _money.format(spentIn(m)),
      'monthLabel': toBeginningOfSentenceCase(DateFormat('MMMM', 'pt_BR').format(now)),
      'forecast': _money.format(f.projected),
      'budgetLeft': budgetTotal > 0 ? _money.format(budgetTotal - budgetSpent) : '',
      'todayRaw': spentOnDay(now),
      'monthRaw': spentIn(m),
      'day': '${now.year}-${now.month}-${now.day}',
      'monthKey': '${now.year}-${now.month}',
    });
  }

  Future<void> _checkBudgetNotifications() async {
    if (!notif.budget) return;
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final m = monthOf(now);
    for (final e in budgets.entries) {
      if (e.value <= 0) continue;
      final spent = spentIn(m, category: e.key);
      final pct = spent / e.value;
      for (final level in const [100, 80]) {
        if (pct * 100 < level) continue;
        final key = 'notified_${now.year}${now.month}_${stableHash(e.key)}_$level';
        if (p.getBool(key) == true) break;
        await p.setBool(key, true);
        if (level == 80) await p.setBool('notified_${now.year}${now.month}_${stableHash(e.key)}_80', true);
        await NativeBridge.notify(
          1000 + e.key.hashCode.abs() % 500 + level,
          level == 100 ? 'Meta de ${e.key} estourada' : '${e.key}: 80% da meta',
          level == 100
              ? 'Você já gastou ${_money.format(spent)} de ${_money.format(e.value)} este mês.'
              : 'Restam ${_money.format(e.value - spent)} até o fim do mês. Segura a onda!',
        );
        break;
      }
    }
  }

  Future<void> _scheduleReminders() async {
    final now = DateTime.now();
    final items = <Map<String, Object?>>[];
    if (notif.debts) {
      var i = 0;
      for (final d in debts) {
        final next = d.nextDue();
        if (next == null) continue;
        final at = DateTime(next.year, next.month, next.day - 1, 10);
        if (at.isAfter(now)) {
          items.add({
            'id': 2000 + i,
            'at': at.millisecondsSinceEpoch,
            'title': 'Amanhã vence: ${d.name}',
            'body': 'Parcela ${d.paidCount() + 1}/${d.installments} de ${_money.format(d.installmentAmount)}.',
          });
        }
        i++;
      }
    }
    if (notif.weekly) {
      var sunday = DateTime(now.year, now.month, now.day, 19);
      while (sunday.weekday != DateTime.sunday || !sunday.isAfter(now)) {
        sunday = DateTime(sunday.year, sunday.month, sunday.day + 1, 19);
      }
      items.add({
        'id': 3000,
        'at': sunday.millisecondsSinceEpoch,
        'title': 'Seu resumo da semana chegou',
        'body': 'O ${AppConfig.assistantName} fez as contas da sua semana. Toque para ver.',
      });
      final firstOfMonth = DateTime(now.year, now.month + 1, 1, 9);
      items.add({
        'id': 3001,
        'at': firstOfMonth.millisecondsSinceEpoch,
        'title': 'Mês novo, vida nova',
        'body': 'Veja como fechou ${DateFormat('MMMM', 'pt_BR').format(now)} e defina as metas do mês.',
      });
    }
    if (notif.payday && profile.payday > 0) {
      var pay = DateTime(now.year, now.month, min(profile.payday, daysInMonth(now.year, now.month)), 11);
      if (!pay.isAfter(now)) {
        pay = DateTime(now.year, now.month + 1, min(profile.payday, daysInMonth(now.year, now.month + 1)), 11);
      }
      final suggestion = max(0.0, (referenceIncome - avgMonthlySpend()) * 0.5);
      items.add({
        'id': 3002,
        'at': pay.millisecondsSinceEpoch,
        'title': 'Dia de pagamento!',
        'body': suggestion > 50
            ? 'Que tal separar ${_money.format(suggestion)} para investir antes de gastar?'
            : 'Separe uma parte para investir antes de começar a gastar.',
      });
    }
    await NativeBridge.schedule(items);
  }
}
