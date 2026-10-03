import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/jose.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

class InvestScreen extends StatefulWidget {
  const InvestScreen({super.key});

  @override
  State<InvestScreen> createState() => _InvestScreenState();
}

class _InvestScreenState extends State<InvestScreen> {
  Map<String, dynamic>? _recs;
  bool _busy = false;
  String? _error;
  final _monthly = TextEditingController();

  @override
  void dispose() {
    _monthly.dispose();
    super.dispose();
  }

  double _suggestedMonthly() {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    final income = app.incomeIn(prev) > 0 ? app.incomeIn(prev) : app.profile.monthlyIncome;
    final left = income - app.spentIn(prev);
    return left > 0 ? (left / 10).floor() * 10.0 : 0;
  }

  Future<void> _generate() async {
    final v = asDouble(_monthly.text.replaceAll('.', '').replaceAll(',', '.'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await Jose(app).recommendations(v > 0 ? v : _suggestedMonthly());
      if (mounted) setState(() => _recs = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setProfile(String field, String value) async {
    final p = app.profile;
    if (field == 'risk') p.risk = value;
    if (field == 'horizon') p.horizon = value;
    if (field == 'knowledge') p.knowledge = value;
    try {
      await app.saveProfile(p);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _addInvestment([Investment? inv]) async {
    final name = TextEditingController(text: inv?.name ?? '');
    final amount = TextEditingController(text: inv == null ? '' : inv.amount.toStringAsFixed(2).replaceAll('.', ','));
    String kind = inv?.kind ?? 'Renda fixa';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(inv == null ? 'Adicionar à carteira' : 'Editar investimento',
                style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Tesouro Selic, Caixinha Nubank')),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor aplicado', prefixText: 'R\$ '),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in const ['Renda fixa', 'Fundos', 'ETF', 'Ações', 'FII', 'Cripto', 'Outro'])
                ChoiceChip(
                  label: Text(k),
                  selected: kind == k,
                  showCheckmark: false,
                  selectedColor: C.lime,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: C.line),
                  shape: const StadiumBorder(),
                  onSelected: (_) => setSheet(() => kind = k),
                ),
            ]),
            const SizedBox(height: 18),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
            if (inv != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: C.red),
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Excluir'),
              ),
          ]),
        ),
      ),
    );
    if (ok == null) return;
    try {
      if (ok) {
        final v = asDouble(amount.text.replaceAll('.', '').replaceAll(',', '.'));
        if (v <= 0 || name.text.trim().isEmpty) return;
        await app.saveInvestment(Investment(
          id: inv?.id ?? newId(),
          name: name.text.trim(),
          kind: kind,
          amount: v,
          date: inv?.date ?? DateTime.now(),
        ));
      } else if (inv != null) {
        await app.deleteInvestment(inv);
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final p = app.profile;
        final suggested = _suggestedMonthly();
        return Scaffold(
          appBar: AppBar(title: const Text('Investir')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              AppCard(
                color: C.ink,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Minha carteira', style: TextStyle(color: Colors.white60)),
                  const SizedBox(height: 4),
                  Text(brl(app.totalInvested),
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${app.investments.length} posições', style: const TextStyle(color: C.lime)),
                ]),
              ),
              const SizedBox(height: 10),
              for (final i in app.investments)
                ListTile(
                  onTap: () => _addInvestment(i),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: const CatIcon('Investimentos', size: 38),
                  title: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(i.kind),
                  trailing: Text(brl(i.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              OutlinedButton.icon(
                onPressed: () => _addInvestment(),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar investimento'),
              ),

              const SectionTitle('Seu perfil de investidor'),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _segment('Risco', 'risk', p.risk,
                      const {'conservador': 'Conservador', 'moderado': 'Moderado', 'arrojado': 'Arrojado'}),
                  const SizedBox(height: 14),
                  _segment('Prazo', 'horizon', p.horizon,
                      const {'curto': 'Até 1 ano', 'medio': '1 a 5 anos', 'longo': '5+ anos'}),
                  const SizedBox(height: 14),
                  _segment('Experiência', 'knowledge', p.knowledge,
                      const {'iniciante': 'Iniciante', 'intermediario': 'Médio', 'avancado': 'Avançado'}),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _monthly,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Quanto quer investir por mês',
                      prefixText: 'R\$ ',
                      hintText: suggested > 0 ? '${suggested.toStringAsFixed(0)} (sobrou no mês passado)' : 'ex.: 300',
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy || !app.gemini.configured ? null : _generate,
                icon: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome),
                label: Text(_busy ? 'O José está analisando...' : 'Recomendações do ${AppConfig.assistantName}'),
              ),
              if (!app.gemini.configured)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Configure a chave do Gemini no Perfil.',
                      textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: const TextStyle(color: C.red)),
                ),
              if (_recs != null) ..._recommendations(_recs!),
            ],
          ),
        );
      },
    );
  }

  Widget _segment(String label, String field, String value, Map<String, String> options) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value))],
          selected: {options.containsKey(value) ? value : options.keys.first},
          onSelectionChanged: (s) => _setProfile(field, s.first),
        ),
      ),
    ]);
  }

  List<Widget> _recommendations(Map<String, dynamic> r) {
    final list = (r['recomendacoes'] as List? ?? const []).whereType<Map>().toList();
    return [
      const SectionTitle('O que o José recomenda'),
      if ('${r['resumo'] ?? ''}'.isNotEmpty)
        AppCard(
          color: C.lime,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const JoseAvatar(size: 34),
            const SizedBox(width: 10),
            Expanded(child: RichMd('${r['resumo']}')),
          ]),
        ),
      if ('${r['reserva_emergencia'] ?? ''}'.isNotEmpty) ...[
        const SizedBox(height: 8),
        AppCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.shield_outlined),
            const SizedBox(width: 10),
            Expanded(child: RichMd('**Reserva de emergência:** ${r['reserva_emergencia']}')),
          ]),
        ),
      ],
      for (final (i, rec) in list.indexed) ...[
        const SizedBox(height: 10),
        _recCard(i + 1, rec),
      ],
      const SizedBox(height: 14),
      const Text(
        'Sugestões geradas por IA com base no seu perfil e histórico. Rentabilidades mudam; '
        'não é recomendação formal de investimento. Confira as condições na sua corretora.',
        style: TextStyle(color: C.muted, fontSize: 12),
      ),
    ];
  }

  Widget _recCard(int n, Map rec) {
    final risk = '${rec['risco'] ?? ''}'.toLowerCase();
    final (Color bg, Color fg) = risk.startsWith('baix')
        ? (const Color(0xFFDCFCE7), C.green)
        : risk.startsWith('alt')
            ? (const Color(0xFFFEE2E2), C.red)
            : (const Color(0xFFFEF3C7), C.amber);
    final rating = asDouble(rec['nota']).clamp(0, 5).toDouble();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 14, backgroundColor: C.ink, child: Text('$n', style: const TextStyle(color: C.lime, fontSize: 12, fontWeight: FontWeight.w800))),
          const SizedBox(width: 10),
          Expanded(child: Text('${rec['nome'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Pill('${rec['tipo'] ?? ''}'),
          Pill('Risco ${rec['risco'] ?? '-'}', bg: bg, fg: fg),
          Pill('★ ${rating.toStringAsFixed(1)}', bg: C.lime),
          if ('${rec['prazo'] ?? ''}'.isNotEmpty) Pill('${rec['prazo']}', icon: Icons.schedule),
        ]),
        const SizedBox(height: 10),
        RichMd('${rec['porque'] ?? ''}', style: const TextStyle(color: C.ink)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('Retorno: ${rec['retorno'] ?? '-'}', style: const TextStyle(color: C.muted, fontSize: 13))),
          if ('${rec['quanto'] ?? ''}'.isNotEmpty)
            Text('${rec['quanto']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ]),
    );
  }
}
