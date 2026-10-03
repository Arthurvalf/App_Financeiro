import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models.dart';
import '../services/jose.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key, this.showAppBar = false});
  final bool showAppBar;

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  String? _advice;
  bool _busy = false;

  Future<void> _askAdvice() async {
    setState(() => _busy = true);
    try {
      final a = await Jose(app).debtAdvice();
      if (mounted) setState(() => _advice = a);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final now = DateTime.now();
        final active = app.debts.where((d) => !d.finished).toList();
        final done = app.debts.where((d) => d.finished).toList();
        final months = [for (var i = 0; i < 6; i++) DateTime(now.year, now.month + i)];
        final commit = [for (final m in months) app.commitmentsIn(m)];
        final income = app.referenceIncome;
        final thisMonth = commit.first;

        return Scaffold(
          appBar: widget.showAppBar ? AppBar(title: const Text('Dívidas e parcelas')) : null,
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            backgroundColor: C.ink,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            onPressed: () => openDebtEditor(context),
            icon: const Icon(Icons.add),
            label: const Text('Nova dívida', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: heroDecoration(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Falta pagar', style: TextStyle(color: Colors.white60)),
                  AnimatedMoney(app.totalDebtRemaining,
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
                  const SizedBox(height: 8),
                  Text(
                    'Este mês: ${brl(thisMonth)} em parcelas'
                    '${income > 0 ? ' • ${(thisMonth / income * 100).toStringAsFixed(0)}% da renda' : ''}',
                    style: const TextStyle(color: C.lime, fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
              if (active.isNotEmpty) ...[
                const SectionTitle('Comprometido nos próximos meses'),
                AppCard(
                  child: MiniBars(
                    values: commit,
                    labels: [for (final m in months) DateFormat('MMM', 'pt_BR').format(m)],
                  ),
                ),
              ],
              const SectionTitle('Ativas'),
              if (active.isEmpty)
                const AppCard(
                  child: Text(
                    'Nenhuma dívida ou parcela ativa. Cadastre compras parceladas, empréstimos e financiamentos '
                    'para saber quanto já está comprometido nos próximos meses.',
                    style: TextStyle(color: C.muted),
                  ),
                ),
              for (final d in active) ...[
                _debtCard(d),
                const SizedBox(height: 10),
              ],
              if (active.isNotEmpty) ...[
                SectionTitle('Estratégia do ${AppConfig.assistantName}'),
                AppCard(
                  child: _advice == null
                      ? Row(children: [
                          const JoseAvatar(),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Quer saber qual dívida atacar primeiro e quanto dá pra economizar?')),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 16)),
                            onPressed: _busy || !app.gemini.configured ? null : _askAdvice,
                            child: _busy
                                ? const SizedBox(
                                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Analisar'),
                          ),
                        ])
                      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const JoseAvatar(size: 34),
                          const SizedBox(width: 10),
                          Expanded(child: RichMd(_advice!)),
                        ]),
                ),
              ],
              if (done.isNotEmpty) ...[
                const SectionTitle('Quitadas'),
                for (final d in done)
                  ListTile(
                    onTap: () => openDebtEditor(context, debt: d),
                    leading: const Icon(Icons.verified, color: C.green),
                    title: Text(d.name),
                    subtitle: Text('${d.installments}x de ${brl(d.installmentAmount)}'),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _debtCard(Debt d) {
    final paid = d.paidCount();
    final next = d.nextDue();
    final pct = d.installments == 0 ? 0.0 : paid / d.installments;
    return AppCard(
      onTap: () => openDebtEditor(context, debt: d),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CatIcon(d.category, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(d.kindLabel, style: const TextStyle(color: C.muted, fontSize: 13)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(brl(d.installmentAmount), style: const TextStyle(fontWeight: FontWeight.w800)),
            const Text('por mês', style: TextStyle(color: C.muted, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 12),
        ProgressLine(value: pct, color: C.green),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text('$paid de ${d.installments} pagas • faltam ${brl(d.remainingAmount())}',
                style: const TextStyle(color: C.muted, fontSize: 13)),
          ),
          if (next != null)
            Pill('vence ${DateFormat('dd/MM').format(next)}', icon: Icons.event),
        ]),
        if (d.interestMonthly > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Juros de ${d.interestMonthly.toStringAsFixed(2)}% ao mês',
                style: const TextStyle(color: C.red, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}

/// Formulário de dívida/parcelamento.
Future<void> openDebtEditor(BuildContext context, {Debt? debt}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _DebtEditor(debt: debt),
    ),
  );
}

class _DebtEditor extends StatefulWidget {
  const _DebtEditor({this.debt});
  final Debt? debt;

  @override
  State<_DebtEditor> createState() => _DebtEditorState();
}

class _DebtEditorState extends State<_DebtEditor> {
  late final _name = TextEditingController(text: widget.debt?.name ?? '');
  late final _amount = TextEditingController(
      text: widget.debt == null ? '' : widget.debt!.installmentAmount.toStringAsFixed(2).replaceAll('.', ','));
  late final _count = TextEditingController(text: widget.debt == null ? '' : '${widget.debt!.installments}');
  late final _interest = TextEditingController(
      text: widget.debt == null || widget.debt!.interestMonthly == 0 ? '' : '${widget.debt!.interestMonthly}');
  late String _kind = widget.debt?.kind ?? 'cartao';
  late DateTime _first = widget.debt?.firstDue ?? DateTime.now();
  late bool _auto = widget.debt?.autoLaunch ?? true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _count.dispose();
    _interest.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = asDouble(_amount.text);
    final n = int.tryParse(_count.text.trim()) ?? 0;
    if (_name.text.trim().isEmpty || v <= 0 || n <= 0) {
      setState(() => _error = 'Preencha nome, valor da parcela e número de parcelas.');
      return;
    }
    final d = Debt(
      id: widget.debt?.id ?? newId(),
      name: _name.text.trim(),
      kind: _kind,
      installmentAmount: v,
      installments: n,
      firstDue: DateTime(_first.year, _first.month, _first.day),
      interestMonthly: asDouble(_interest.text),
      autoLaunch: _auto,
    );
    Navigator.pop(context);
    await app.saveDebt(d);
  }

  @override
  Widget build(BuildContext context) {
    final v = asDouble(_amount.text);
    final n = int.tryParse(_count.text.trim()) ?? 0;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.debt == null ? 'Nova dívida ou parcelamento' : 'Editar',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in const {
              'cartao': 'Parcelado no cartão',
              'emprestimo': 'Empréstimo',
              'financiamento': 'Financiamento',
              'outro': 'Outro',
            }.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _kind == e.key,
                showCheckmark: false,
                selectedColor: C.lime,
                backgroundColor: Colors.white,
                side: const BorderSide(color: C.line),
                shape: const StadiumBorder(),
                onSelected: (_) => setState(() {
                  _kind = e.key;
                  if (widget.debt == null) _auto = e.key == 'cartao';
                }),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Notebook, Financiamento do carro'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _amount,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor da parcela', prefixText: 'R\$ '),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _count,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Parcelas'),
              ),
            ),
          ]),
          if (v > 0 && n > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Total: ${brl(v * n)}', style: const TextStyle(color: C.muted)),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.event, size: 18),
            label: Text('1ª parcela: ${DateFormat("d 'de' MMMM 'de' y", 'pt_BR').format(_first)}'),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _first,
                firstDate: DateTime(2015),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (d != null) setState(() => _first = d);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _interest,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Juros ao mês (opcional)', suffixText: '%'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _auto,
            onChanged: (x) => setState(() => _auto = x),
            title: const Text('Lançar cada parcela como gasto'),
            subtitle: const Text('Desligue se a parcela já entra pelo Nubank (boleto/Pix), para não contar duas vezes.'),
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: C.red)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('Salvar')),
          if (widget.debt != null)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: C.red),
              onPressed: () async {
                Navigator.pop(context);
                await app.deleteDebt(widget.debt!);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir dívida'),
            ),
        ]),
      ),
    );
  }
}
