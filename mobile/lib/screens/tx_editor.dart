import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../state/app.dart';
import '../theme.dart';

/// Abre o formulário de gasto/entrada. Passe [tx] para editar.
Future<void> openTxEditor(BuildContext context, {Tx? tx}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _TxEditor(tx: tx),
    ),
  );
}

class _TxEditor extends StatefulWidget {
  const _TxEditor({this.tx});
  final Tx? tx;

  @override
  State<_TxEditor> createState() => _TxEditorState();
}

class _TxEditorState extends State<_TxEditor> {
  late final _desc = TextEditingController(text: widget.tx?.description ?? '');
  late final _amount = TextEditingController(
      text: widget.tx == null ? '' : widget.tx!.amount.toStringAsFixed(2).replaceAll('.', ','));
  late bool _income = widget.tx?.isIncome ?? false;
  late String? _cat = widget.tx?.category;
  late DateTime _date = widget.tx?.date ?? DateTime.now();
  bool _catTouched = false;
  String? _error;
  int _installments = 1; // 1 = à vista
  late final String? _originalCat = widget.tx?.category;

  @override
  void initState() {
    super.initState();
    _catTouched = widget.tx != null;
    _desc.addListener(() {
      if (!_catTouched && _desc.text.trim().length > 2) {
        final g = app.categorize(_desc.text, isIncome: _income);
        if (g != _cat) setState(() => _cat = g);
      }
    });
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = double.tryParse(_amount.text.replaceAll('R\$', '').replaceAll('.', '').replaceAll(',', '.').trim());
    if (v == null || v <= 0) {
      setState(() => _error = 'Informe um valor maior que zero.');
      return;
    }
    if (_desc.text.trim().isEmpty) {
      setState(() => _error = 'Dê uma descrição (ex.: Mercado).');
      return;
    }
    final cat = _cat ?? app.categorize(_desc.text, isIncome: _income);
    final t = widget.tx ??
        Tx(id: newId(), description: '', amount: 0, isIncome: _income, category: cat, date: _date);
    t
      ..description = _desc.text.trim()
      ..amount = v
      ..isIncome = _income
      ..category = _income ? (cat == 'Outros' ? 'Renda' : cat) : cat
      ..date = _date
      ..aiCategorized = _catTouched || t.aiCategorized;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);

    // Compra parcelada: vira uma dívida e cada parcela é lançada no seu mês.
    if (!_income && _installments > 1) {
      if (widget.tx != null) await app.deleteTx(widget.tx!);
      await app.saveDebt(Debt(
        id: newId(),
        name: t.description,
        kind: 'cartao',
        installmentAmount: double.parse((v / _installments).toStringAsFixed(2)),
        installments: _installments,
        firstDue: _date,
        autoLaunch: true,
        category: t.category,
      ));
      messenger.showSnackBar(SnackBar(
          content: Text('Parcelado em ${_installments}x de ${brl(v / _installments)}. Veja em Planos → Dívidas.')));
      return;
    }

    await app.saveTx(t);
    if (t.category == 'Outros') app.aiCategorizePending();

    // Trocou a categoria? Oferece criar uma regra para as próximas.
    final changed = _originalCat != null && _originalCat != t.category && !t.isIncome;
    if (changed) {
      final pattern = _rulePattern(t.description);
      if (pattern.isNotEmpty && !app.rules.any((r) => r.pattern.toLowerCase() == pattern)) {
        messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('Sempre colocar "$pattern" em ${t.category}?'),
          action: SnackBarAction(
            label: 'Criar regra',
            textColor: C.lime,
            onPressed: () async {
              await app.addRule(pattern, t.category);
              await app.applyRulesToAll();
            },
          ),
        ));
      }
    }
  }

  /// Primeira palavra significativa da descrição (ex.: "Posto Shell 123" -> "posto shell").
  String _rulePattern(String description) {
    final words = description
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zà-ú0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && int.tryParse(w) == null)
        .toList();
    if (words.isEmpty) return '';
    return words.take(2).join(' ');
  }

  Future<void> _delete() async {
    Navigator.pop(context);
    await app.deleteTx(widget.tx!);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final visibleCats = cats.where((c) => _income ? true : c.name != 'Renda').toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.tx == null ? 'Novo lançamento' : 'Editar lançamento',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Gasto'), icon: Icon(Icons.arrow_upward_rounded)),
              ButtonSegment(value: true, label: Text('Entrada'), icon: Icon(Icons.arrow_downward_rounded)),
            ],
            selected: {_income},
            onSelectionChanged: (s) => setState(() {
              _income = s.first;
              if (_income && !_catTouched) _cat = 'Renda';
              if (!_income && _cat == 'Renda') _cat = app.categorize(_desc.text);
            }),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            autofocus: widget.tx == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Descrição', hintText: 'Ex.: iFood, Uber, Netflix'),
          ),
          const SizedBox(height: 14),
          Text('Categoria', style: t.labelLarge?.copyWith(color: C.muted)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in visibleCats)
              ChoiceChip(
                avatar: Icon(c.icon, size: 16, color: c.color),
                label: Text(c.name),
                selected: _cat == c.name,
                showCheckmark: false,
                selectedColor: C.lime,
                backgroundColor: Colors.white,
                side: const BorderSide(color: C.line),
                shape: const StadiumBorder(),
                onSelected: (_) => setState(() {
                  _cat = c.name;
                  _catTouched = true;
                }),
              ),
          ]),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(DateFormat("d 'de' MMMM 'de' y", 'pt_BR').format(_date)),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
            },
          ),
          if (!_income) ...[
            const SizedBox(height: 14),
            Text('Pagamento', style: t.labelLarge?.copyWith(color: C.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in const [1, 2, 3, 4, 5, 6, 10, 12])
                ChoiceChip(
                  label: Text(n == 1 ? 'À vista' : '${n}x'),
                  selected: _installments == n,
                  showCheckmark: false,
                  selectedColor: C.lime,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: C.line),
                  shape: const StadiumBorder(),
                  onSelected: (_) => setState(() => _installments = n),
                ),
            ]),
            if (_installments > 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('O valor acima é o total. Cada parcela entra no mês dela.',
                    style: TextStyle(color: C.muted, fontSize: 12)),
              ),
          ],
          if (widget.tx?.raw != null) ...[
            const SizedBox(height: 10),
            Text('Notificação original: ${widget.tx!.raw}', style: const TextStyle(color: C.muted, fontSize: 12)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: C.red)),
          ],
          const SizedBox(height: 18),
          FilledButton(onPressed: _save, child: const Text('Salvar')),
          if (widget.tx != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: C.red),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Usado pelo botão "+": atalho para o editor.
class AddTxButton extends StatelessWidget {
  const AddTxButton({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: null,
      backgroundColor: C.ink,
      foregroundColor: Colors.white,
      shape: const StadiumBorder(),
      onPressed: () => openTxEditor(context),
      icon: const Icon(Icons.add),
      label: const Text('Lançar', style: TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
