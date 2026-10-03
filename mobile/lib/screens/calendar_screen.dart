import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'tx_editor.dart';

/// Mapa de calor dos gastos por dia do mês.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _month = monthOf(DateTime.now());
  DateTime? _selected = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final dim = daysInMonth(_month.year, _month.month);
        final values = [for (var d = 1; d <= dim; d++) app.spentOnDay(DateTime(_month.year, _month.month, d))];
        final maxV = values.isEmpty ? 0.0 : values.reduce(max);
        final total = values.fold(0.0, (s, v) => s + v);
        final daysWithSpend = values.where((v) => v > 0).length;
        final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7; // domingo = 0
        final now = DateTime.now();
        final isCurrent = _month.year == now.year && _month.month == now.month;

        // Dia da semana em que mais gasta
        final byWeekday = List<double>.filled(7, 0);
        for (var d = 1; d <= dim; d++) {
          byWeekday[DateTime(_month.year, _month.month, d).weekday % 7] += values[d - 1];
        }
        final topWd = byWeekday.indexOf(byWeekday.reduce(max));
        const wdNames = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];

        final dayTxs = _selected == null
            ? <Tx>[]
            : app.txs
                .where((t) =>
                    t.date.year == _selected!.year && t.date.month == _selected!.month && t.date.day == _selected!.day)
                .toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Calendário de gastos')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              AppCard(
                child: Column(children: [
                  Row(children: [
                    IconButton(
                      onPressed: () => setState(() {
                        _month = DateTime(_month.year, _month.month - 1);
                        _selected = null;
                      }),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        toBeginningOfSentenceCase(DateFormat('MMMM y', 'pt_BR').format(_month)) ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      onPressed: isCurrent
                          ? null
                          : () => setState(() {
                                _month = DateTime(_month.year, _month.month + 1);
                                _selected = null;
                              }),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (final w in const ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'])
                      Expanded(
                        child: Center(
                          child: Text(w, style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      for (var i = 0; i < firstWeekday; i++) const SizedBox(),
                      for (var d = 1; d <= dim; d++) _dayCell(d, values[d - 1], maxV),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('menos', style: TextStyle(fontSize: 11, color: C.muted)),
                    const SizedBox(width: 6),
                    for (final a in const [0.12, 0.35, 0.6, 0.85, 1.0])
                      Container(
                        width: 16,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Color.lerp(const Color(0xFFF1F5D8), const Color(0xFF3F4F00), a),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    const SizedBox(width: 6),
                    const Text('mais', style: TextStyle(fontSize: 11, color: C.muted)),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _stat('Total do mês', brl(total))),
                const SizedBox(width: 8),
                Expanded(child: _stat('Média por dia', brl(total / (isCurrent ? now.day : dim)))),
                const SizedBox(width: 8),
                Expanded(child: _stat('Dias sem gastar', '${(isCurrent ? now.day : dim) - daysWithSpend}')),
              ]),
              if (total > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: AppCard(
                    color: C.lime,
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const Icon(Icons.insights),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Você gasta mais às ${wdNames[topWd]}s: ${brl(byWeekday[topWd])} neste mês.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  ),
                ),
              if (_selected != null) ...[
                SectionTitle(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_selected!)),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: dayTxs.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Nenhum lançamento neste dia.', style: TextStyle(color: C.muted)),
                        )
                      : Column(children: [
                          for (final t in dayTxs) TxTile(t, onTap: () => openTxEditor(context, tx: t)),
                        ]),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _dayCell(int d, double v, double maxV) {
    final date = DateTime(_month.year, _month.month, d);
    final future = date.isAfter(DateTime.now());
    final a = maxV <= 0 || v <= 0 ? 0.0 : 0.15 + 0.85 * (v / maxV);
    final bg = v <= 0 ? (future ? Colors.transparent : C.soft) : Color.lerp(const Color(0xFFF1F5D8), const Color(0xFF3F4F00), a)!;
    final selected = _selected != null && _selected!.day == d && _selected!.month == _month.month;
    final dark = a > 0.55;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selected = date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: C.ink, width: 2) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$d',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: future ? C.muted.withValues(alpha: 0.5) : (dark ? Colors.white : C.ink),
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ]),
      );
}
