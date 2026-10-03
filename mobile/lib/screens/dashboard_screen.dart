import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models.dart';
import '../services/capture.dart';
import '../services/jose.dart';
import '../state/app.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'calendar_screen.dart';
import 'can_i_buy_screen.dart';
import 'debts_screen.dart';
import 'profile_screen.dart';
import 'simulator_screen.dart';
import 'tx_editor.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onNavigate});
  final void Function(int tab) onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, String>>? _insights;
  bool _loadingInsights = false;
  String? _insightError;

  Future<void> _loadInsights() async {
    setState(() {
      _loadingInsights = true;
      _insightError = null;
    });
    try {
      final r = await Jose(app).insights();
      if (mounted) setState(() => _insights = r);
    } catch (e) {
      if (mounted) setState(() => _insightError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loadingInsights = false);
    }
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        final m = app.month;
        final now = DateTime.now();
        final isCurrent = m.year == now.year && m.month == now.month;
        final spent = app.spentIn(m);
        final income = app.incomeIn(m);
        final invested = app.investedIn(m);
        final byCat = app.byCategory(m);
        final prevSpent = app.spentIn(DateTime(m.year, m.month - 1));
        final recent = app.txsOf(m).take(5).toList();
        final alerts = isCurrent ? app.alerts() : <AppAlert>[];
        final firstName = app.profile.name.split(' ').first;
        final upcoming = app.debts.where((d) => d.nextDue() != null).toList()
          ..sort((a, b) => a.nextDue()!.compareTo(b.nextDue()!));

        return Scaffold(
          floatingActionButton: const AddTxButton(),
          body: RefreshIndicator(
            color: C.ink,
            onRefresh: app.loadAll,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 16),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${_greeting()}${firstName.isEmpty ? '' : ', $firstName'}',
                              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8)),
                          Text('Seu dinheiro, em ordem.', style: t.bodyMedium?.copyWith(color: C.muted)),
                        ]),
                      ),
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(backgroundColor: Colors.white, side: const BorderSide(color: C.line)),
                        onPressed: () => _push(const ProfileScreen()),
                        icon: const Icon(Icons.person_outline),
                      ),
                    ]),
                  ),
                ),
                if (app.error != null) _errorBanner(app.error!),
                if (CaptureBridge.supported && !app.captureEnabled) _captureBanner(),

                // Cartão principal
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: heroDecoration(),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      _monthButton(Icons.chevron_left, () => app.shiftMonth(-1)),
                      Expanded(
                        child: Text(
                          toBeginningOfSentenceCase(DateFormat('MMMM y', 'pt_BR').format(m)) ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                        ),
                      ),
                      _monthButton(Icons.chevron_right, isCurrent ? null : () => app.shiftMonth(1)),
                    ]),
                    const SizedBox(height: 14),
                    const Text('Gastos do mês', style: TextStyle(color: Colors.white60)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedMoney(spent,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.6)),
                    ),
                    if (prevSpent > 0) ...[
                      const SizedBox(height: 6),
                      _deltaPill(spent, prevSpent),
                    ],
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(child: _miniStat('Entradas', income, C.lime)),
                      Expanded(child: _miniStat('Investido', invested, Colors.white)),
                      Expanded(child: _miniStat('Saldo', income - spent - invested, Colors.white)),
                    ]),
                  ]),
                ),

                // Atalhos
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: QuickAction(icon: Icons.add, label: 'Lançar', highlight: true, onTap: () => openTxEditor(context))),
                  Expanded(child: QuickAction(icon: Icons.shopping_cart_checkout, label: 'Posso\ncomprar?', onTap: () => _push(const CanIBuyScreen()))),
                  Expanded(child: QuickAction(icon: Icons.calendar_month_outlined, label: 'Calendário', onTap: () => _push(const CalendarScreen()))),
                  Expanded(child: QuickAction(icon: Icons.auto_graph, label: 'E se...?', onTap: () => _push(const SimulatorScreen(showAppBar: true)))),
                  Expanded(child: QuickAction(icon: Icons.credit_card, label: 'Dívidas', onTap: () => _push(const DebtsScreen(showAppBar: true)))),
                ]),

                if (isCurrent) ...[
                  const SectionTitle('Previsão do mês'),
                  _forecastCard(),
                ],

                if (alerts.isNotEmpty) ...[
                  const SectionTitle('Alertas'),
                  for (final a in alerts) _alertCard(a),
                ],

                const SectionTitle('Para onde foi o dinheiro'),
                AppCard(
                  child: byCat.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Text('Nenhum gasto neste mês ainda. Toque em "Lançar" ou ative a captura do Nubank.',
                              style: TextStyle(color: C.muted)),
                        )
                      : Row(children: [
                          Donut(
                            values: byCat,
                            size: 132,
                            center: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('${byCat.length}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                              const Text('categorias', style: TextStyle(color: C.muted, fontSize: 11)),
                            ]),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(children: [
                              for (final e in byCat.entries.take(5))
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(children: [
                                    Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(color: catOf(e.key).color, shape: BoxShape.circle)),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    Text(brl(e.value), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                  ]),
                                ),
                            ]),
                          ),
                        ]),
                ),

                if (upcoming.isNotEmpty) ...[
                  SectionTitle('Próximas parcelas', action: 'Ver dívidas', onAction: () => _push(const DebtsScreen(showAppBar: true))),
                  AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Column(children: [
                      for (final d in upcoming.take(3))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CatIcon('Dívidas', size: 38),
                          title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              'Parcela ${d.paidCount() + 1}/${d.installments} • ${DateFormat("d 'de' MMM", 'pt_BR').format(d.nextDue()!)}'),
                          trailing: Text(brl(d.installmentAmount), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  ),
                ],

                SectionTitle('${AppConfig.assistantName} analisou seu mês'),
                _insightsCard(),

                SectionTitle('Últimos lançamentos', action: 'Ver todos', onAction: () => widget.onNavigate(1)),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: recent.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Nada por aqui ainda.', style: TextStyle(color: C.muted)),
                        )
                      : Column(children: [
                          for (final tx in recent) TxTile(tx, onTap: () => openTxEditor(context, tx: tx)),
                        ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _forecastCard() {
    final f = app.forecast();
    final ratio = f.income > 0 ? f.projected / f.income : 0.0;
    final ok = f.income <= 0 || f.projected <= f.income;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Nesse ritmo você fecha o mês em', style: TextStyle(color: C.muted, fontSize: 13)),
              const SizedBox(height: 2),
              AnimatedMoney(f.projected, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
            ]),
          ),
          Pill(
            f.income <= 0 ? 'sem renda' : (ok ? 'sobra ${brl(f.freeAtEnd)}' : 'falta ${brl(-f.freeAtEnd)}'),
            bg: ok ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
            fg: ok ? C.green : C.red,
          ),
        ]),
        const SizedBox(height: 12),
        if (f.income > 0) ProgressLine(value: ratio, color: C.ink),
        const SizedBox(height: 8),
        Text(
          f.income > 0
              ? 'Renda de referência ${brl(f.income)} • já gasto ${brl(f.spentSoFar)}'
                  '${f.pendingInstallments > 0 ? ' • ${brl(f.pendingInstallments)} em parcelas a vencer' : ''}'
              : 'Informe sua renda no Perfil (ou lance o salário) para ver quanto vai sobrar.',
          style: const TextStyle(color: C.muted, fontSize: 12.5),
        ),
      ]),
    );
  }

  Widget _monthButton(IconData icon, VoidCallback? onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: onTap == null ? Colors.white24 : Colors.white),
        visualDensity: VisualDensity.compact,
      );

  Widget _miniStat(String label, double value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(value, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      );

  Widget _deltaPill(double now, double before) {
    final pct = ((now - before) / before * 100).round();
    final up = pct > 0;
    return Pill(
      '${up ? '+' : ''}$pct% vs mês anterior',
      bg: up ? const Color(0x33DC2626) : const Color(0x33D4F84B),
      fg: up ? const Color(0xFFFCA5A5) : C.lime,
      icon: up ? Icons.north_east : Icons.south_east,
    );
  }

  Widget _errorBanner(String msg) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          color: const Color(0xFFFEF2F2),
          child: Row(children: [
            const Icon(Icons.cloud_off, color: C.red),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: const TextStyle(color: C.red))),
            IconButton(onPressed: app.loadAll, icon: const Icon(Icons.refresh, color: C.red)),
          ]),
        ),
      );

  Widget _captureBanner() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppCard(
          color: const Color(0xFFF1E6FF),
          onTap: () => _push(const ProfileScreen()),
          child: const Row(children: [
            Icon(Icons.notifications_active_outlined, color: Color(0xFF820AD1)),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ative a captura do Nubank', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF4A0478))),
                SizedBox(height: 2),
                Text('Cada compra aprovada vira um gasto aqui, sozinho.',
                    style: TextStyle(color: Color(0xFF6B2A99), fontSize: 13)),
              ]),
            ),
            Icon(Icons.chevron_right, color: Color(0xFF820AD1)),
          ]),
        ),
      );

  Widget _alertCard(AppAlert a) {
    final (Color bg, Color fg, IconData icon) = switch (a.level) {
      'danger' => (const Color(0xFFFEF2F2), C.red, Icons.error_outline),
      'warn' => (const Color(0xFFFFF7ED), C.amber, Icons.warning_amber_rounded),
      'good' => (const Color(0xFFF0FDF4), C.green, Icons.savings_outlined),
      _ => (Colors.white, C.ink, Icons.info_outline),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        color: bg,
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title, style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
              const SizedBox(height: 2),
              Text(a.body, style: const TextStyle(color: C.ink, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _insightsCard() {
    if (!app.gemini.configured) {
      return AppCard(
        onTap: () => _push(const ProfileScreen()),
        child: const Row(children: [
          JoseAvatar(),
          SizedBox(width: 12),
          Expanded(child: Text('O José está sem chave do Gemini. Toque para configurar.')),
          Icon(Icons.chevron_right),
        ]),
      );
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_insights == null && !_loadingInsights)
          Row(children: [
            const JoseAvatar(),
            const SizedBox(width: 12),
            const Expanded(child: Text('Quer que eu olhe seu mês e aponte onde dá pra melhorar?')),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 16)),
              onPressed: _loadInsights,
              child: const Text('Analisar'),
            ),
          ]),
        if (_loadingInsights)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Row(children: [
              JoseAvatar(),
              SizedBox(width: 12),
              Expanded(child: Text('Fazendo as contas...')),
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: C.ink)),
            ]),
          ),
        if (_insightError != null) Text(_insightError!, style: const TextStyle(color: C.red)),
        if (_insights != null)
          for (final i in _insights!)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  i['tipo'] == 'alerta'
                      ? Icons.warning_amber_rounded
                      : i['tipo'] == 'elogio'
                          ? Icons.emoji_events_outlined
                          : Icons.lightbulb_outline,
                  color: i['tipo'] == 'alerta' ? C.amber : (i['tipo'] == 'elogio' ? C.green : C.ink),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i['titulo'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(i['texto'] ?? '', style: const TextStyle(color: C.muted, height: 1.35)),
                  ]),
                ),
              ]),
            ),
        if (_insights != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => widget.onNavigate(2),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Conversar com o José'),
            ),
          ),
      ]),
    );
  }
}
