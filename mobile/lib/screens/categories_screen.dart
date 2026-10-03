import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Categorias próprias e regras automáticas.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Categorias e regras')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            SectionTitle('Suas categorias', action: 'Nova', onAction: () => _newCategory(context)),
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in allCats)
                  Chip(
                    avatar: Icon(c.icon, size: 16, color: c.color),
                    label: Text(c.name),
                    backgroundColor: c.custom ? c.color.withValues(alpha: 0.12) : Colors.white,
                    side: const BorderSide(color: C.line),
                    shape: const StadiumBorder(),
                    onDeleted: c.custom ? () => _confirmDeleteCat(context, c) : null,
                  ),
              ]),
            ),
            const SizedBox(height: 6),
            const Text('As categorias com fundo colorido são suas. Apagar uma move os lançamentos dela para "Outros".',
                style: TextStyle(color: C.muted, fontSize: 12)),

            SectionTitle('Regras automáticas', action: 'Nova', onAction: () => _newRule(context)),
            if (app.rules.isEmpty)
              const AppCard(
                child: Text(
                  'Ex.: tudo que tiver "posto" vira Transporte, ou "petz" vira Pet. As regras valem para a captura do '
                  'Nubank, para o que você lança e para o José. Dica: ao trocar a categoria de um lançamento, o app '
                  'oferece criar a regra sozinho.',
                  style: TextStyle(color: C.muted),
                ),
              ),
            for (final r in app.rules)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CatIcon(r.category, size: 36),
                    title: Text('contém "${r.pattern}"', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('→ ${r.category}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => app.deleteRule(r),
                    ),
                  ),
                ),
              ),
            if (app.rules.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () async {
                  final n = await app.applyRulesToAll();
                  if (context.mounted) toast(context, n == 0 ? 'Tudo já estava certo.' : '$n lançamentos recategorizados.');
                },
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Aplicar regras aos lançamentos antigos'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteCat(BuildContext context, Cat c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Apagar "${c.name}"?'),
        content: const Text('Os lançamentos dessa categoria vão para "Outros".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: C.red),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok == true) await app.deleteCategory(c);
  }

  Future<void> _newCategory(BuildContext context) async {
    final name = TextEditingController();
    var icon = iconChoices.keys.first;
    var color = colorChoices.first;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
                child: Icon(iconChoices[icon], color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => set(() {}),
                  decoration: const InputDecoration(labelText: 'Nome da categoria', hintText: 'Ex.: Pet, Presentes'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            const Text('Ícone', style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in iconChoices.entries)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => set(() => icon = e.key),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: icon == e.key ? C.lime : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: C.line),
                    ),
                    child: Icon(e.value, size: 20),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            const Text('Cor', style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final col in colorChoices)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => set(() => color = col),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: color == col ? Border.all(color: C.ink, width: 3) : null,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Criar categoria')),
          ]),
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await app.addCategory(name.text, icon, color);
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _newRule(BuildContext context) async {
    final pattern = TextEditingController();
    var cat = spendingCats.first;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Nova regra', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: pattern,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Se a descrição contém', hintText: 'Ex.: posto, petz, mãe'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: cat,
              decoration: const InputDecoration(labelText: 'Vira a categoria'),
              items: [
                for (final n in allCats.map((c) => c.name))
                  DropdownMenuItem(value: n, child: Row(children: [CatIcon(n, size: 26), const SizedBox(width: 10), Text(n)])),
              ],
              onChanged: (v) => set(() => cat = v ?? cat),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Criar regra')),
          ]),
        ),
      ),
    );
    if (ok != true || pattern.text.trim().isEmpty) return;
    await app.addRule(pattern.text, cat);
    final n = await app.applyRulesToAll();
    if (context.mounted && n > 0) toast(context, 'Regra criada e aplicada em $n lançamentos.');
  }
}
