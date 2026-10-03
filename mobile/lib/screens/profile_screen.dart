import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models.dart';
import '../services/capture.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final _name = TextEditingController(text: app.profile.name);
  late final _income = TextEditingController(
      text: app.profile.monthlyIncome > 0 ? app.profile.monthlyIncome.toStringAsFixed(0) : '');
  late final _goals = TextEditingController(text: app.profile.goals);
  late final _key = TextEditingController(text: app.profile.geminiKey);
  bool _hideKey = true;
  bool _saving = false;
  bool _testing = false;
  String? _keyStatus;

  @override
  void initState() {
    super.initState();
    app.refreshCaptureStatus();
  }

  @override
  void dispose() {
    _name.dispose();
    _income.dispose();
    _goals.dispose();
    _key.dispose();
    super.dispose();
  }

  Profile _current() {
    final p = app.profile;
    return Profile(
      name: _name.text.trim(),
      risk: p.risk,
      horizon: p.horizon,
      knowledge: p.knowledge,
      monthlyIncome: asDouble(_income.text),
      goals: _goals.text.trim(),
      geminiKey: _key.text.trim(),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await app.saveProfile(_current());
      if (mounted) toast(context, 'Perfil salvo.');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testKey() async {
    setState(() {
      _testing = true;
      _keyStatus = null;
    });
    app.gemini.apiKey = _key.text.trim();
    try {
      final r = await app.gemini.generate(
        messages: [ChatMsg('Responda só: ok', fromUser: true)],
        temperature: 0,
      );
      _keyStatus = 'Funcionando! Modelo: ${app.gemini.workingModel} (resposta: "${r.length > 20 ? r.substring(0, 20) : r}")';
      await app.saveProfile(_current());
    } catch (e) {
      _keyStatus = 'Falhou: ${friendlyError(e)}';
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _simulate() async {
    final samples = [
      ('Compra no crédito aprovada', 'Compra de R\$ 38,90 APROVADA em IFOOD *RESTAURANTE para o cartão com final 1234.'),
      ('Compra no débito aprovada', 'Compra de R\$ 24,50 APROVADA em UBER *TRIP no débito.'),
      ('Transferência enviada', 'Você enviou uma transferência de R\$ 50,00 para Maria Souza.'),
    ];
    final s = samples[DateTime.now().second % samples.length];
    final ok = await app.ingestNotification(s.$1, s.$2, DateTime.now());
    if (mounted) {
      toast(context, ok ? 'Notificação simulada virou lançamento: ${s.$2}' : 'Essa já tinha sido anotada.');
    }
  }

  Future<void> _showRecent() async {
    final list = await CaptureBridge.recent();
    if (!mounted) return;
    final df = DateFormat('dd/MM HH:mm');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SizedBox(
        height: MediaQuery.of(c).size.height * 0.7,
        child: list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhuma notificação do Nubank vista ainda. Faça uma compra ou Pix e volte aqui.',
                      textAlign: TextAlign.center),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Últimas notificações do Nubank',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 4),
                  const Text('Se alguma não virou lançamento, me mande o texto para eu ajustar o leitor.',
                      style: TextStyle(color: C.muted)),
                  for (final n in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(parseBankNotification(n.title, n.text) == null
                          ? Icons.help_outline
                          : Icons.check_circle_outline),
                      title: Text(n.title),
                      subtitle: Text('${n.text}\n${df.format(n.time)}'),
                      isThreeLine: true,
                    ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Perfil')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            AppCard(
              child: Row(children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: C.ink,
                  child: Text(
                    (app.profile.name.isNotEmpty ? app.profile.name[0] : (app.auth.email ?? '?')[0]).toUpperCase(),
                    style: const TextStyle(color: C.lime, fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.profile.name.isEmpty ? 'Sem nome' : app.profile.name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    Text(app.auth.email ?? '', style: const TextStyle(color: C.muted)),
                  ]),
                ),
              ]),
            ),

            // ---------- Nubank ----------
            const SectionTitle('Captura automática do Nubank'),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: const Color(0xFF820AD1), borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: const Text('nu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      !CaptureBridge.supported
                          ? 'Disponível só no app Android'
                          : app.captureEnabled
                              ? 'Ativa — compras e Pix entram sozinhos'
                              : 'Desativada',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(app.captureEnabled ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: app.captureEnabled ? C.green : C.muted),
                ]),
                const SizedBox(height: 12),
                const Text(
                  'O app lê as notificações do Nubank no seu celular (compras aprovadas, Pix enviados e recebidos) '
                  'e cria os lançamentos na hora, já categorizados. Nada de senha do banco: só o texto da notificação.',
                  style: TextStyle(color: C.muted, height: 1.4),
                ),
                if (CaptureBridge.supported && !app.captureEnabled) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: CaptureBridge.openSettings,
                    child: const Text('Ativar acesso às notificações'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Na lista, ative "Finança". Se aparecer "configuração restrita" (Android 13+), toque em '
                    '"Liberar configurações restritas" abaixo, use o menu ⋮ e escolha "Permitir configurações restritas". '
                    'Depois volte e ative de novo.',
                    style: TextStyle(fontSize: 12, color: C.muted, height: 1.4),
                  ),
                  TextButton(onPressed: CaptureBridge.openAppInfo, child: const Text('Liberar configurações restritas')),
                ],
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(onPressed: _simulate, child: const Text('Simular compra')),
                  ),
                  if (CaptureBridge.supported) ...[
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(onPressed: _showRecent, child: const Text('Ver capturas'))),
                  ],
                ]),
                const SizedBox(height: 6),
                const Text(
                  'Dica: no Nubank, deixe as notificações de compras e Pix ligadas, e tire o Finança da economia de bateria.',
                  style: TextStyle(fontSize: 12, color: C.muted),
                ),
              ]),
            ),

            // ---------- Gemini ----------
            SectionTitle('Cérebro do ${AppConfig.assistantName} (Gemini)'),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _key,
                  obscureText: _hideKey,
                  decoration: InputDecoration(
                    labelText: 'Chave da API do Gemini',
                    hintText: 'Cole aqui (aistudio.google.com)',
                    suffixIcon: IconButton(
                      icon: Icon(_hideKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hideKey = !_hideKey),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _testing ? null : _testKey,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bolt),
                  label: const Text('Testar e salvar chave'),
                ),
                if (_keyStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(_keyStatus!,
                      style: TextStyle(color: _keyStatus!.startsWith('Funcionando') ? C.green : C.red, fontSize: 13)),
                ],
                const SizedBox(height: 8),
                const Text(
                  'A chave fica salva só na sua conta (protegida pelas regras do Firebase) e é usada direto do seu aparelho.',
                  style: TextStyle(fontSize: 12, color: C.muted),
                ),
              ]),
            ),

            // ---------- dados pessoais ----------
            const SectionTitle('Sobre você'),
            AppCard(
              child: Column(children: [
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome')),
                const SizedBox(height: 12),
                TextField(
                  controller: _income,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Renda mensal (aprox.)', prefixText: 'R\$ '),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _goals,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Seus objetivos',
                    hintText: 'Ex.: juntar 10 mil para um carro em 2 anos, sair do cheque especial...',
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Salvando...' : 'Salvar perfil')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).popUntil((r) => r.isFirst);
                await app.signOut();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sair da conta'),
            ),
          ],
        ),
      ),
    );
  }
}
