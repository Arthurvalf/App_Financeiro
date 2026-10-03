import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/jose.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  List<Map<String, dynamic>>? _suggestions;
  bool _busy = false;

  Future<void> _suggest() async {
    setState(() => _busy = true);
    try {
      final s = await Jose(app).budgetSuggestions();
      if (mounted) setState(() => _suggestions = s);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(String? category) async {
    String cat = category ?? spendingCats.firstWhere((c) => !app.budgets.containsKey(c), orElse: () => 'Outros');
    final ctrl = TextEditingController(
        text: category == null ? '' : app.budgets[category]!.toStringAsFixed(0));
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(category == null ? 'Nova meta' : 'Editar meta',
                style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: cat,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: [
                for (final n in spendingCats)
                  DropdownMenuItem(value: n, child: Row(children: [CatIcon(n, size: 28), const SizedBox(width: 10), Text(n)])),
              ],
              onChanged: category != null ? null : (v) => setSheet(() => cat = v ?? cat),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Limite por mês', prefixText: 'R\$ '),
            ),
            const SizedBox(height: 8),
            Text('Gasto este mês: ${brl(app.spentIn(_thisMonth(), category: cat))}',
                style: const TextStyle(color: C.muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar meta')),
            if (category != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: C.red),
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Remover meta'),
              ),
          ]),
        ),
      ),
    );
    if (result == null) return;
    try {
      if (result) {
        final v = double.tryParse(ctrl.text.replaceAll('.', '').replaceAll(',', '.'));
        if (v != null && v > 0) await app.setBudget(cat, v);
      } else if (category != null) {
        await app.removeBudget(category);
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  DateTime _thisMonth() => DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final m = _thisMonth();
        final entries = app.budgets.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
        final totalLimit = entries.fold(0.0, (s, e) => s + e.value);
        final totalSpent = entries.fold(0.0, (s, e) => s + app.spentIn(m, category: e.key));
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            backgroundColor: C.ink,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add),
            label: const Text('Nova meta', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
            children: [
              if (entries.isNotEmpty)
                AppCard(
                  color: C.lime,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Total das metas', style: TextStyle(color: C.limeDark, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('${brl(totalSpent)} de ${brl(totalLimit)}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    ProgressLine(value: totalLimit == 0 ? 0 : totalSpent / totalLimit),
                  ]),
                ),
              if (entries.isEmpty)
                const AppCard(
                  child: Text('Defina limites por categoria (ex.: Comida até R\$ 800). Eu te aviso quando chegar perto.',
                      style: TextStyle(color: C.muted)),
                ),
              for (final e in entries) ...[
                const SizedBox(height: 10),
                AppCard(
                  onTap: () => _edit(e.key),
                  child: Builder(builder: (context) {
                    final spent = app.spentIn(m, category: e.key);
                    final pct = e.value == 0 ? 0.0 : spent / e.value;
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        CatIcon(e.key, size: 36),
                        const SizedBox(width: 10),
                        Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700))),
                        Text('${(pct * 100).round()}%',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: pct >= 1 ? C.red : (pct >= .8 ? C.amber : C.ink))),
                      ]),
                      const SizedBox(height: 10),
                      ProgressLine(value: pct, color: catOf(e.key).color),
                      const SizedBox(height: 6),
                      Text(
                        pct >= 1
                            ? 'Passou ${brl(spent - e.value)} do limite de ${brl(e.value)}'
                            : '${brl(spent)} de ${brl(e.value)} — restam ${brl(e.value - spent)}',
                        style: const TextStyle(color: C.muted, fontSize: 13),
                      ),
                    ]);
                  }),
                ),
              ],
              SectionTitle('Sugestões do ${AppConfig.assistantName}'),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_suggestions == null)
                    Row(children: [
                      const JoseAvatar(),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Posso sugerir metas com base no que você gasta de verdade.')),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 16)),
                        onPressed: _busy || !app.gemini.configured ? null : _suggest,
                        child: _busy
                            ? const SizedBox(
                                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Sugerir'),
                      ),
                    ]),
                  if (!app.gemini.configured)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Configure a chave do Gemini no Perfil.', style: TextStyle(color: C.muted)),
                    ),
                  if (_suggestions != null) ...[
                    for (final s in _suggestions!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CatIcon('${s['categoria']}', size: 36),
                        title: Text('${s['categoria']} — ${brl(asDouble(s['limite']))}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${s['motivo'] ?? ''}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () async {
                            final c = '${s['categoria']}';
                            final v = asDouble(s['limite']);
                            if (!cats.any((x) => x.name == c) || v <= 0) return;
                            await app.setBudget(c, v);
                            if (context.mounted) toast(context, 'Meta de $c criada.');
                          },
                        ),
                      ),
                    TextButton(
                      onPressed: () async {
                        for (final s in _suggestions!) {
                          final c = '${s['categoria']}';
                          final v = asDouble(s['limite']);
                          if (cats.any((x) => x.name == c) && v > 0) await app.setBudget(c, v);
                        }
                        if (context.mounted) toast(context, 'Todas as metas aplicadas.');
                      },
                      child: const Text('Aplicar todas'),
                    ),
                  ],
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}
