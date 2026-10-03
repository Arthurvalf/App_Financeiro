import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// O que o José Pinto lembra sobre você.
class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Memória do José')),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: null,
          backgroundColor: C.ink,
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
          onPressed: () => _add(context),
          icon: const Icon(Icons.add),
          label: const Text('Ensinar algo', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            AppCard(
              color: C.lime,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const JoseAvatar(size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tudo aqui eu levo em conta em todas as conversas. Eu anoto sozinho quando você me conta algo '
                    'importante, mas você pode ensinar ou apagar o que quiser.',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            if (app.memories.isEmpty)
              const AppCard(
                child: Text(
                  'Ainda não sei nada sobre você. Exemplos: "Recebo dia 5", "Estou juntando para um PC novo", '
                  '"Pago a faculdade até 2028", "Prefiro investimentos sem risco".',
                  style: TextStyle(color: C.muted),
                ),
              ),
            for (final m in app.memories.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bookmark_outline),
                    title: Text(m.text),
                    subtitle: Text(DateFormat("d 'de' MMM 'de' y", 'pt_BR').format(m.createdAt),
                        style: const TextStyle(fontSize: 12)),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => app.deleteMemory(m)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('O que o ${AppConfig.assistantName} deve saber?',
              style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Ex.: Quero comprar um carro de R\$ 60 mil em 3 anos'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ]),
      ),
    );
    if (ok == true) await app.addMemory(ctrl.text);
  }
}
