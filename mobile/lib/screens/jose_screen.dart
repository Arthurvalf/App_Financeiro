import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/jose.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'can_i_buy_screen.dart';
import 'memory_screen.dart';
import 'profile_screen.dart';

class JoseScreen extends StatefulWidget {
  const JoseScreen({super.key, this.initialMessage, this.standalone = false});
  final String? initialMessage;
  final bool standalone;

  @override
  State<JoseScreen> createState() => _JoseScreenState();
}

class _JoseScreenState extends State<JoseScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _thinking = false;

  static const _suggestions = [
    'Como vai fechar meu mês?',
    'Onde estou gastando demais?',
    'Monte um plano para eu investir R\$ 500 por mês',
    'Quais assinaturas eu deveria cancelar?',
    'Anota: gastei 32 no almoço hoje',
    'Qual dívida eu pago primeiro?',
    'Quanto preciso de reserva de emergência?',
    'Tesouro Selic ou CDB hoje?',
  ];

  @override
  void initState() {
    super.initState();
    final first = widget.initialMessage;
    if (first != null && first.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(first));
    }
  }

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
        _scroll.animateTo(_scroll.position.maxScrollExtent + 300,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  void _push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            titleSpacing: widget.standalone ? 0 : 16,
            title: Row(children: [
              const JoseAvatar(size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppConfig.assistantName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _thinking ? 'pensando...' : 'gênio das suas finanças',
                      key: ValueKey(_thinking),
                      style: TextStyle(
                          color: _thinking ? C.green : C.muted, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
            ]),
            actions: [
              IconButton(
                tooltip: 'O que o José sabe',
                onPressed: () => _push(const MemoryScreen()),
                icon: Badge(
                  isLabelVisible: app.memories.isNotEmpty,
                  label: Text('${app.memories.length}'),
                  backgroundColor: C.ink,
                  textColor: C.lime,
                  child: const Icon(Icons.psychology_outlined),
                ),
              ),
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
                  ? _setupCard()
                  : app.chat.isEmpty
                      ? _welcome()
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                          itemCount: app.chat.length + (_thinking ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == app.chat.length) return _bubble('', fromUser: false, typing: true);
                            final m = app.chat[i];
                            if (m is ChatMsgError) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: AppCard(
                                  color: const Color(0xFFFEF2F2),
                                  padding: const EdgeInsets.all(12),
                                  child: Text(m.text, style: const TextStyle(color: C.red)),
                                ),
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
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  decoration: const BoxDecoration(
                    color: C.bg,
                    border: Border(top: BorderSide(color: C.line)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Pergunte, peça um plano ou anote um gasto...',
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
          const SizedBox(height: 12),
          const Center(child: JoseAvatar(size: 76)),
          const SizedBox(height: 16),
          Text('E aí${app.profile.name.isNotEmpty ? ', ${app.profile.name.split(' ').first}' : ''}! Eu sou o ${AppConfig.assistantName}.',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Enxergo seus gastos, metas, dívidas e investimentos, consulto as taxas do dia e lembro do que você me conta. '
            'Também anoto lançamentos, crio metas, regras e categorias pra você.',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          AppCard(
            onTap: () => _push(const CanIBuyScreen()),
            child: const Row(children: [
              Icon(Icons.shopping_cart_checkout),
              SizedBox(width: 12),
              Expanded(
                child: Text('Posso comprar isso? Me diga o preço que eu faço as contas.',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.chevron_right),
            ]),
          ),
          const SizedBox(height: 18),
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

  Widget _setupCard() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          const Center(child: JoseAvatar(size: 72)),
          const SizedBox(height: 16),
          const Text('O José está sem cérebro (chave do Gemini)',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'No APK oficial a chave já vem embutida. Se você está na versão web ou num build sem a chave, '
            'cole uma chave do aistudio.google.com no Perfil.',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => _push(const ProfileScreen()), child: const Text('Abrir Perfil')),
        ],
      );

  Widget _bubble(String text, {required bool fromUser, bool typing = false}) {
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 250),
        builder: (context, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
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
              ? const _TypingDots()
              : fromUser
                  ? Text(text, style: const TextStyle(color: Colors.white, height: 1.4))
                  : RichMd(text),
        ),
      ),
    );
  }
}

/// Três pontinhos pulando enquanto o José pensa.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(0, -4 * _bounce((_c.value + i * 0.2) % 1)),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: C.ink, shape: BoxShape.circle),
              ),
            ),
        ]),
      ),
    );
  }

  double _bounce(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;
}
