import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/jose.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile_screen.dart';

class JoseScreen extends StatefulWidget {
  const JoseScreen({super.key});

  @override
  State<JoseScreen> createState() => _JoseScreenState();
}

class _JoseScreenState extends State<JoseScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _thinking = false;

  static const _suggestions = [
    'Onde estou gastando demais?',
    'Anota: gastei 32 no almoço hoje',
    'Onde invisto R\$ 300 por mês?',
    'Cria uma meta de 400 para Lazer',
    'Quanto gastei com comida esse mês?',
    'Me ajuda a montar uma reserva de emergência',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _thinking) return;
    _input.clear();
    setState(() => _thinking = true);
    _toBottom();
    try {
      final notes = await Jose(app).send(text);
      if (notes.isNotEmpty && mounted) toast(context, notes.first);
    } catch (e) {
      app.chat.add(ChatMsgError(friendlyError(e)));
      app.refresh();
    } finally {
      if (mounted) setState(() => _thinking = false);
      _toBottom();
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Row(children: [
              const JoseAvatar(size: 36),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppConfig.assistantName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                Text(_thinking ? 'digitando...' : 'seu assistente financeiro',
                    style: const TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w500)),
              ]),
            ]),
            actions: [
              if (app.chat.isNotEmpty)
                IconButton(
                  tooltip: 'Nova conversa',
                  onPressed: () {
                    app.chat.clear();
                    app.refresh();
                  },
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: !app.gemini.configured
                  ? _setupCard(context)
                  : app.chat.isEmpty
                      ? _welcome()
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                          itemCount: app.chat.length + (_thinking ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == app.chat.length) return _bubble('...', fromUser: false, typing: true);
                            final m = app.chat[i];
                            if (m is ChatMsgError) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Text(m.text, style: const TextStyle(color: C.red)),
                              );
                            }
                            if (m.isNote) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Center(child: Pill(m.text, bg: C.lime, icon: Icons.check_circle)),
                              );
                            }
                            return _bubble(m.text, fromUser: m.fromUser);
                          },
                        ),
            ),
            if (app.gemini.configured)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Pergunte ou peça para anotar um gasto...',
                          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: C.ink, minimumSize: const Size(50, 50)),
                      onPressed: _thinking ? null : () => _send(),
                      icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                    ),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }

  Widget _welcome() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          const Center(child: JoseAvatar(size: 72)),
          const SizedBox(height: 16),
          Text('E aí! Eu sou o ${AppConfig.assistantName}.',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Vejo seus gastos, metas e investimentos. Posso anotar lançamentos, criar metas e te dizer onde investir.',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted, height: 1.4),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final s in _suggestions)
                ActionChip(
                  label: Text(s),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: C.line),
                  shape: const StadiumBorder(),
                  onPressed: () => _send(s),
                ),
            ],
          ),
        ],
      );

  Widget _setupCard(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          const Center(child: JoseAvatar(size: 72)),
          const SizedBox(height: 16),
          const Text('Falta só a chave do Gemini',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Gere uma chave gratuita em aistudio.google.com (Get API key) e cole no Perfil. '
            'Ela fica salva só na sua conta.',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            child: const Text('Abrir Perfil'),
          ),
        ],
      );

  Widget _bubble(String text, {required bool fromUser, bool typing = false}) {
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: fromUser ? C.ink : Colors.white,
          border: fromUser ? null : Border.all(color: C.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(fromUser ? 20 : 6),
            bottomRight: Radius.circular(fromUser ? 6 : 20),
          ),
        ),
        child: typing
            ? const SizedBox(
                width: 32,
                height: 16,
                child: Center(child: LinearProgressIndicator(color: C.ink, backgroundColor: C.soft)),
              )
            : fromUser
                ? Text(text, style: const TextStyle(color: Colors.white, height: 1.4))
                : RichMd(text),
      ),
    );
  }
}
