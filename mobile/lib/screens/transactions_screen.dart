import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'tx_editor.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _query = '';
  String? _cat;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final q = _query.toLowerCase();
        final list = app.txs
            .where((t) => _cat == null || t.category == _cat)
            .where((t) => q.isEmpty || t.description.toLowerCase().contains(q) || t.category.toLowerCase().contains(q))
            .toList();
        final groups = <DateTime, List<Tx>>{};
        for (final t in list) {
          groups.putIfAbsent(DateTime(t.date.year, t.date.month, t.date.day), () => []).add(t);
        }
        final usedCats = cats.where((c) => app.txs.any((t) => t.category == c.name)).toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Lançamentos')),
          floatingActionButton: const AddTxButton(),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Buscar (ex.: ifood, uber)',
                  prefixIcon: Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip('Todas', null),
                  for (final c in usedCats) _chip(c.name, c.name),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Nenhum lançamento encontrado.', style: TextStyle(color: C.muted)),
                      ),
                    )
                  : RefreshIndicator(
                      color: C.ink,
                      onRefresh: app.loadAll,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                        children: [
                          for (final g in groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                              child: Row(children: [
                                Expanded(
                                  child: Text(_dayLabel(g.key),
                                      style: const TextStyle(fontWeight: FontWeight.w700, color: C.muted)),
                                ),
                                Text(
                                  brl(g.value.where((t) => !t.isIncome).fold(0.0, (s, t) => s + t.amount)),
                                  style: const TextStyle(color: C.muted, fontSize: 13),
                                ),
                              ]),
                            ),
                            AppCard(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: Column(children: [
                                for (final t in g.value)
                                  Dismissible(
                                    key: ValueKey(t.id),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 16),
                                      child: const Icon(Icons.delete_outline, color: C.red),
                                    ),
                                    confirmDismiss: (_) => _confirmDelete(context, t),
                                    onDismissed: (_) => app.deleteTx(t),
                                    child: TxTile(t, onTap: () => openTxEditor(context, tx: t)),
                                  ),
                              ]),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ]),
        );
      },
    );
  }

  Widget _chip(String label, String? value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _cat == value,
          showCheckmark: false,
          selectedColor: C.lime,
          backgroundColor: Colors.white,
          side: const BorderSide(color: C.line),
          shape: const StadiumBorder(),
          onSelected: (_) => setState(() => _cat = value),
        ),
      );

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return 'Hoje';
    if (d == today.subtract(const Duration(days: 1))) return 'Ontem';
    return toBeginningOfSentenceCase(DateFormat("EEEE, d 'de' MMM", 'pt_BR').format(d)) ?? '';
  }

  Future<bool> _confirmDelete(BuildContext context, Tx t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text('${t.description} — ${brl(t.amount)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: C.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
