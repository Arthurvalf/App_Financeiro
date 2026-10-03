import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/market.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'jose_screen.dart';

class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key, this.showAppBar = false});
  final bool showAppBar;

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _Product {
  const _Product(this.key, this.label, this.ir, this.note);
  final String key;
  final String label;
  final bool ir;
  final String note;
}

const _products = [
  _Product('poupanca', 'Poupança', false, 'Isenta de IR, rende menos quando a Selic está alta.'),
  _Product('cdi', 'Tesouro Selic / CDB 100%', true, 'Baixo risco, liquidez diária. IR regressivo.'),
  _Product('ipca', 'Tesouro IPCA+', true, 'Protege da inflação (IPCA + ~6% a.a.). Melhor para longo prazo.'),
  _Product('acoes', 'Ações / ETFs', true, 'Hipotético 12% a.a. — oscila bastante no curto prazo.'),
  _Product('custom', 'Taxa própria', true, 'Digite a taxa anual que quiser testar.'),
];

class _SimulatorScreenState extends State<SimulatorScreen> {
  MarketRates _rates = Market.fallback;
  int _mode = 0;

  // Modo "investir todo mês"
  final _initial = TextEditingController(text: '0');
  final _monthly = TextEditingController(text: '300');
  final _custom = TextEditingController(text: '10');
  double _years = 5;
  String _product = 'cdi';
  bool _ir = true;

  // Modo "e se eu cortar"
  String? _cutCat;
  double _cutPct = 30;
  double _cutYears = 5;

  @override
  void initState() {
    super.initState();
    Market.rates().then((r) {
      if (mounted) setState(() => _rates = r);
    });
    final byCat = app.byCategory(DateTime(DateTime.now().year, DateTime.now().month - 1));
    _cutCat = byCat.keys.isNotEmpty ? byCat.keys.first : (spendingCats.isNotEmpty ? spendingCats.first : null);
  }

  @override
  void dispose() {
    _initial.dispose();
    _monthly.dispose();
    _custom.dispose();
    super.dispose();
  }

  double _annualRate(String key) => switch (key) {
        'poupanca' => _rates.poupanca,
        'cdi' => _rates.cdi,
        'ipca' => ((1 + _rates.ipca12m / 100) * 1.06 - 1) * 100,
        'acoes' => 12.0,
        _ => asDouble(_custom.text),
      };

  /// Simula aportes mensais. Devolve (série anual do total, série anual do investido, final bruto, final líquido).
  ({List<double> total, List<double> invested, double gross, double net, double put}) _simulate(
      double initial, double monthly, double years, double annualPct, bool ir) {
    final months = (years * 12).round();
    final rm = pow(1 + annualPct / 100, 1 / 12).toDouble() - 1;
    var v = initial;
    var put = initial;
    final total = <double>[initial];
    final inv = <double>[initial];
    for (var m = 1; m <= months; m++) {
      v = v * (1 + rm) + monthly;
      put += monthly;
      if (m % 12 == 0 || m == months) {
        total.add(v);
        inv.add(put);
      }
    }
    var net = v;
    if (ir && v > put) {
      final rate = months <= 6 ? 0.225 : months <= 12 ? 0.20 : months <= 24 ? 0.175 : 0.15;
      net = v - (v - put) * rate;
    }
    return (total: total, invested: inv, gross: v, net: net, put: put);
  }

  void _askJose(String text) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => JoseScreen(initialMessage: text, standalone: true)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('Simulador "e se"')) : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Investir todo mês'), icon: Icon(Icons.savings_outlined)),
              ButtonSegment(value: 1, label: Text('E se eu cortar...'), icon: Icon(Icons.content_cut)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(_rates.live ? Icons.verified : Icons.info_outline, size: 15, color: _rates.live ? C.green : C.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${_rates.live ? 'Banco Central${_rates.asOf != null ? ' (${_rates.asOf})' : ''}' : 'Taxas estimadas'}: '
                'Selic ${_rates.selic.toStringAsFixed(2)}% • CDI ${_rates.cdi.toStringAsFixed(2)}% • IPCA ${_rates.ipca12m.toStringAsFixed(2)}%',
                style: const TextStyle(fontSize: 12, color: C.muted),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (_mode == 0) ..._investMode() else ..._cutMode(),
        ],
      ),
    );
  }

  List<Widget> _investMode() {
    final initial = asDouble(_initial.text);
    final monthly = asDouble(_monthly.text);
    final rate = _annualRate(_product);
    final p = _products.firstWhere((x) => x.key == _product);
    final r = _simulate(initial, monthly, _years, rate, _ir && p.ir);
    final realFactor = pow(1 + _rates.ipca12m / 100, _years).toDouble();
    final labels = [for (var i = 0; i < r.total.length; i++) i == 0 ? 'hoje' : '${i}a'];
    final shown = labels.length > 7
        ? [labels.first, labels[labels.length ~/ 2], labels.last]
        : labels;

    return [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _monthly,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Todo mês', prefixText: 'R\$ '),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _initial,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Já tenho', prefixText: 'R\$ '),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text('Por ${_years.round()} ${_years.round() == 1 ? 'ano' : 'anos'}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Slider(
            value: _years,
            min: 1,
            max: 30,
            divisions: 29,
            activeColor: C.ink,
            inactiveColor: C.soft,
            onChanged: (v) => setState(() => _years = v),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final x in _products)
              ChoiceChip(
                label: Text(x.label),
                selected: _product == x.key,
                showCheckmark: false,
                selectedColor: C.lime,
                backgroundColor: Colors.white,
                side: const BorderSide(color: C.line),
                shape: const StadiumBorder(),
                onSelected: (_) => setState(() => _product = x.key),
              ),
          ]),
          if (_product == 'custom') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _custom,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Taxa ao ano', suffixText: '% a.a.'),
            ),
          ],
          const SizedBox(height: 8),
          Text('${p.note} Taxa usada: ${rate.toStringAsFixed(2)}% a.a.', style: const TextStyle(color: C.muted, fontSize: 12.5)),
          if (p.ir)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _ir,
              onChanged: (v) => setState(() => _ir = v),
              title: const Text('Descontar Imposto de Renda'),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: heroDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Em ${_years.round()} anos você teria', style: const TextStyle(color: Colors.white60)),
          AnimatedMoney(r.net,
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
          const SizedBox(height: 6),
          Text('Você colocou ${brl(r.put)} • rendeu ${brl(r.net - r.put)}',
              style: const TextStyle(color: C.lime, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Em poder de compra de hoje: ~${brl(r.net / realFactor)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          const SizedBox(height: 16),
          SimpleLineChart(
            height: 150,
            series: [
              LineSeries(r.total, C.lime, fill: true),
              LineSeries(r.invested, Colors.white38),
            ],
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final l in shown) Text(l, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        ]),
      ),
      const SectionTitle('Mesmo plano em outros investimentos'),
      AppCard(
        child: Column(children: [
          for (final x in _products.where((x) => x.key != 'custom'))
            Builder(builder: (context) {
              final rr = _simulate(initial, monthly, _years, _annualRate(x.key), _ir && x.ir);
              final best = x.key == _product;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: Text(x.label,
                        style: TextStyle(fontWeight: best ? FontWeight.w800 : FontWeight.w500)),
                  ),
                  Text(brl(rr.net), style: TextStyle(fontWeight: FontWeight.w800, color: best ? C.ink : C.muted)),
                ]),
              );
            }),
        ]),
      ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: () => _askJose(
            'Simulei investir ${brl(monthly)} por mês (já tenho ${brl(initial)}) por ${_years.round()} anos em ${p.label} '
            'a ${rate.toStringAsFixed(2)}% a.a., chegando a ~${brl(r.net)}. Esse é o melhor caminho para mim? '
            'O que você mudaria considerando meu perfil e meus objetivos?'),
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Perguntar ao José sobre este plano'),
      ),
    ];
  }

  List<Widget> _cutMode() {
    final cat = _cutCat;
    final avg = cat == null ? 0.0 : app.avgCategorySpend(cat);
    final saving = avg * _cutPct / 100;
    final r = _simulate(0, saving, _cutYears, _rates.cdi, true);
    return [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            initialValue: cat,
            decoration: const InputDecoration(labelText: 'Cortar gastos de'),
            items: [
              for (final n in spendingCats)
                DropdownMenuItem(value: n, child: Row(children: [CatIcon(n, size: 26), const SizedBox(width: 10), Text(n)])),
            ],
            onChanged: (v) => setState(() => _cutCat = v),
          ),
          const SizedBox(height: 8),
          Text('Você gasta em média ${brl(avg)} por mês nisso.', style: const TextStyle(color: C.muted)),
          const SizedBox(height: 14),
          Text('Cortar ${_cutPct.round()}% (${brl(saving)} por mês)', style: const TextStyle(fontWeight: FontWeight.w700)),
          Slider(
            value: _cutPct,
            min: 10,
            max: 100,
            divisions: 9,
            activeColor: C.ink,
            inactiveColor: C.soft,
            onChanged: (v) => setState(() => _cutPct = v),
          ),
          Text('E investir isso por ${_cutYears.round()} anos', style: const TextStyle(fontWeight: FontWeight.w700)),
          Slider(
            value: _cutYears,
            min: 1,
            max: 30,
            divisions: 29,
            activeColor: C.ink,
            inactiveColor: C.soft,
            onChanged: (v) => setState(() => _cutYears = v),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: heroDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Se você cortar ${_cutPct.round()}% de ${cat ?? '...'}', style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 2),
          AnimatedMoney(r.net,
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
          const SizedBox(height: 4),
          Text('em ${_cutYears.round()} anos no Tesouro Selic/CDB (líquido de IR)',
              style: const TextStyle(color: C.lime, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${brl(saving * 12)} economizados por ano', style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          const SizedBox(height: 16),
          SimpleLineChart(height: 130, series: [LineSeries(r.total, C.lime, fill: true), LineSeries(r.invested, Colors.white38)]),
        ]),
      ),
      const SizedBox(height: 14),
      if (cat != null)
        OutlinedButton.icon(
          onPressed: () => _askJose(
              'Quero cortar ${_cutPct.round()}% dos meus gastos com $cat (hoje ~${brl(avg)}/mês) e investir a diferença. '
              'Me dê um plano prático para conseguir cortar e onde investir esses ${brl(saving)} por mês.'),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Pedir um plano ao José'),
        ),
    ];
  }
}
