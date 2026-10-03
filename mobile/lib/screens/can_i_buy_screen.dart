import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/jose.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CanIBuyScreen extends StatefulWidget {
  const CanIBuyScreen({super.key});

  @override
  State<CanIBuyScreen> createState() => _CanIBuyScreenState();
}

class _CanIBuyScreenState extends State<CanIBuyScreen> {
  final _item = TextEditingController();
  final _price = TextEditingController();
  int _installments = 1;
  String _cat = 'Compras';
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _item.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    FocusScope.of(context).unfocus();
    final price = asDouble(_price.text);
    if (_item.text.trim().isEmpty || price <= 0) {
      setState(() => _error = 'Diga o que é e quanto custa.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await Jose(app).canIBuy(
        item: _item.text.trim(),
        price: price,
        installments: _installments,
        category: _cat,
      );
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = asDouble(_price.text);
    final f = app.forecast();
    final budget = app.budgets[_cat];
    final spentCat = app.spentIn(monthOf(DateTime.now()), category: _cat);
    final parcela = price > 0 ? price / _installments : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Posso comprar isso?')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _item,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'O que você quer comprar?', hintText: 'Ex.: tênis, fone, PS5'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                decoration: const InputDecoration(labelText: 'Preço', prefixText: 'R\$ '),
              ),
              const SizedBox(height: 14),
              const Text('Como vai pagar?', style: TextStyle(color: C.muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final n in const [1, 2, 3, 6, 10, 12])
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
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _cat,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: [
                  for (final n in spendingCats)
                    DropdownMenuItem(value: n, child: Row(children: [CatIcon(n, size: 26), const SizedBox(width: 10), Text(n)])),
                ],
                onChanged: (v) => setState(() => _cat = v ?? _cat),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // Números na hora, antes mesmo do José responder
          if (price > 0)
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Na ponta do lápis', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _line('Sobra prevista do mês', brl(f.freeAtEnd), f.freeAtEnd >= 0 ? C.green : C.red),
                _line('Depois da compra', brl(f.freeAtEnd - parcela), f.freeAtEnd - parcela >= 0 ? C.green : C.red),
                if (_installments > 1) _line('Parcela', '${_installments}x de ${brl(parcela)}', C.ink),
                if (budget != null)
                  _line('Meta de $_cat', '${brl(spentCat + parcela)} de ${brl(budget)}', spentCat + parcela > budget ? C.red : C.ink),
                _line('Peso na renda', f.income > 0 ? '${(price / f.income * 100).toStringAsFixed(0)}% de um mês' : '—', C.ink),
              ]),
            ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _busy ? null : _ask,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.psychology_alt_outlined),
            label: Text(_busy ? 'O José está pensando...' : 'Perguntar ao ${AppConfig.assistantName}'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: C.red)),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            _verdict(_result!),
          ],
        ],
      ),
    );
  }

  Widget _line(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: C.muted))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  Widget _verdict(Map<String, dynamic> r) {
    final v = '${r['veredito'] ?? ''}'.toLowerCase();
    final (Color bg, Color fg, IconData icon, String label) = v.startsWith('sim')
        ? (const Color(0xFFDCFCE7), C.green, Icons.check_circle, 'Pode comprar')
        : v.contains('cuidado')
            ? (const Color(0xFFFEF3C7), C.amber, Icons.error_outline, 'Com cuidado')
            : (const Color(0xFFFEE2E2), C.red, Icons.block, 'Melhor não agora');
    final nota = asDouble(r['nota']).clamp(0, 10).toDouble();
    final pontos = (r['pontos'] as List? ?? const []).map((e) => '$e').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        color: bg,
        child: Row(children: [
          Icon(icon, color: fg, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 20)),
              Text('Nota ${nota.toStringAsFixed(0)}/10 do José', style: TextStyle(color: fg)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const JoseAvatar(size: 34),
            const SizedBox(width: 10),
            Expanded(child: RichMd('${r['resumo'] ?? ''}')),
          ]),
          if ('${r['impacto'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Impacto', style: TextStyle(fontWeight: FontWeight.w700)),
            RichMd('${r['impacto']}', style: const TextStyle(color: C.muted)),
          ],
          if (pontos.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final p in pontos)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('•  ', style: TextStyle(fontWeight: FontWeight.w800)),
                  Expanded(child: RichMd(p)),
                ]),
              ),
          ],
          if ('${r['alternativa'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.soft, borderRadius: BorderRadius.circular(16)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(child: RichMd('${r['alternativa']}')),
              ]),
            ),
          ],
          if ('${r['quando'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.event_available, size: 18, color: C.muted),
              const SizedBox(width: 6),
              Expanded(child: Text('${r['quando']}', style: const TextStyle(color: C.muted))),
            ]),
          ],
        ]),
      ),
    ]);
  }
}
