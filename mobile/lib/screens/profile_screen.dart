import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models.dart';
import '../services/capture.dart';
import '../services/native.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'categories_screen.dart';
import 'memory_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  late final _name = TextEditingController(text: app.profile.name);
  late final _income = TextEditingController(
      text: app.profile.monthlyIncome > 0 ? app.profile.monthlyIncome.toStringAsFixed(0) : '');
  late final _payday = TextEditingController(text: app.profile.payday > 0 ? '${app.profile.payday}' : '');
  late final _goals = TextEditingController(text: app.profile.goals);
  late final _key = TextEditingController(text: app.profile.geminiKey);
  bool _hideKey = true;
  bool _saving = false;
  bool _testing = false;
  bool _notifAllowed = true;
  String? _keyStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _income.dispose();
    _payday.dispose();
    _goals.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    await app.refreshCaptureStatus();
    final allowed = await NativeBridge.notificationsAllowed();
    if (mounted) setState(() => _notifAllowed = allowed || !NativeBridge.supported);
  }

  Profile _current() {
    final p = app.profile;
    final day = int.tryParse(_payday.text.trim()) ?? 0;
    return Profile(
      name: _name.text.trim(),
      risk: p.risk,
      horizon: p.horizon,
      knowledge: p.knowledge,
      monthlyIncome: asDouble(_income.text),
      payday: day < 0 ? 0 : (day > 31 ? 31 : day),
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
    final typed = _key.text.trim();
    app.gemini.apiKey = typed.isNotEmpty ? typed : AppConfig.embeddedGeminiKey;
    try {
      final r = await app.gemini.generate(messages: [ChatMsg('Responda só: ok', fromUser: true)], temperature: 0);
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
                  const Text('Últimas notificações do Nubank', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
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

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Perfil')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: heroDecoration(),
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: C.lime,
                  child: Text(
                    (app.profile.name.isNotEmpty ? app.profile.name[0] : (app.auth.email ?? '?')[0]).toUpperCase(),
                    style: const TextStyle(color: C.ink, fontWeight: FontWeight.w800, fontSize: 22),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.profile.name.isEmpty ? 'Sem nome' : app.profile.name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
                    Text(app.auth.email ?? '', style: const TextStyle(color: Colors.white60)),
                  ]),
                ),
              ]),
            ),

            const SectionTitle('Personalizar'),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Categorias e regras', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${customCats.length} suas • ${app.rules.length} regras'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(const CategoriesScreen()),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.psychology_outlined),
                  title: const Text('Memória do José', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${app.memories.length} coisas que ele sabe sobre você'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(const MemoryScreen()),
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
                if (CaptureBridge.supported && !app.captureEnabled) ...[
                  const SizedBox(height: 12),
                  FilledButton(onPressed: CaptureBridge.openSettings, child: const Text('Ativar acesso às notificações')),
                  const SizedBox(height: 8),
                  const Text(
                    'Na lista, ative "Finança". Se aparecer "configuração restrita" (Android 13+), toque em '
                    '"Liberar configurações restritas", use o menu ⋮ e escolha "Permitir configurações restritas". '
                    'Depois volte e ative de novo.',
                    style: TextStyle(fontSize: 12, color: C.muted, height: 1.4),
                  ),
                  TextButton(onPressed: CaptureBridge.openAppInfo, child: const Text('Liberar configurações restritas')),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: _simulate, child: const Text('Simular compra'))),
                  if (CaptureBridge.supported) ...[
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(onPressed: _showRecent, child: const Text('Ver capturas'))),
                  ],
                ]),
              ]),
            ),

            // ---------- Notificações ----------
            const SectionTitle('Notificações'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Column(children: [
                if (!_notifAllowed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 6),
                    child: Row(children: [
                      const Expanded(
                        child: Text('As notificações do app estão bloqueadas.', style: TextStyle(color: C.red)),
                      ),
                      TextButton(
                        onPressed: () async {
                          await NativeBridge.requestNotificationPermission();
                          await Future<void>.delayed(const Duration(seconds: 2));
                          await _refreshStatus();
                        },
                        child: const Text('Permitir'),
                      ),
                    ]),
                  ),
                _switch('Gasto capturado do Nubank', 'Avisa na hora, com o valor', app.notif.capture, 'capture'),
                _switch('Metas', 'Quando chegar a 80% e 100%', app.notif.budget, 'budget'),
                _switch('Parcelas', 'Um dia antes do vencimento', app.notif.debts, 'debts'),
                _switch('Resumo da semana e do mês', 'Domingo à noite e todo dia 1º', app.notif.weekly, 'weekly'),
                _switch('Dia do salário', 'Lembrete para investir primeiro', app.notif.payday, 'payday'),
              ]),
            ),

            // ---------- Widget ----------
            const SectionTitle('Widget na tela inicial'),
            const AppCard(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.widgets_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Segure o dedo num espaço vazio da tela inicial → Widgets → Finança. Ele mostra quanto você gastou '
                    'hoje e no mês, e se atualiza sozinho a cada compra capturada do Nubank.',
                    style: TextStyle(height: 1.4),
                  ),
                ),
              ]),
            ),

            // ---------- Gemini ----------
            SectionTitle('Cérebro do ${AppConfig.assistantName} (Gemini)'),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(AppConfig.hasEmbeddedKey ? Icons.lock : Icons.key_off,
                      color: AppConfig.hasEmbeddedKey ? C.green : C.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppConfig.hasEmbeddedKey
                          ? 'Chave pessoal embutida e protegida neste app.'
                          : 'Este build não tem chave embutida. Cole uma abaixo.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: _key,
                  obscureText: _hideKey,
                  decoration: InputDecoration(
                    labelText: AppConfig.hasEmbeddedKey ? 'Outra chave (opcional)' : 'Chave da API do Gemini',
                    hintText: 'aistudio.google.com',
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
                  label: const Text('Testar o José'),
                ),
                if (_keyStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(_keyStatus!,
                      style: TextStyle(color: _keyStatus!.startsWith('Funcionando') ? C.green : C.red, fontSize: 13)),
                ],
              ]),
            ),

            // ---------- dados pessoais ----------
            const SectionTitle('Sobre você'),
            AppCard(
              child: Column(children: [
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nome')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _income,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Renda mensal', prefixText: 'R\$ '),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _payday,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Dia do salário'),
                    ),
                  ),
                ]),
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

  Widget _switch(String title, String subtitle, bool value, String key) => SwitchListTile(
        contentPadding: const EdgeInsets.only(right: 4),
        value: value,
        onChanged: (v) => app.setNotifPref(key, v),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5)),
      );
}
