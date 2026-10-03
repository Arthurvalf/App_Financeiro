import 'package:flutter/material.dart';

import '../config.dart';
import '../state/app.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    final pass = _pass.text;
    String? err;
    if (!email.contains('@') || !email.contains('.')) err = 'Digite um e-mail válido.';
    if (err == null && pass.length < 6) err = 'A senha precisa ter pelo menos 6 caracteres.';
    if (err == null && _register && pass != _pass2.text) err = 'As senhas não conferem.';
    if (err == null && _register && _name.text.trim().isEmpty) err = 'Como podemos te chamar?';
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await app.signUp(email, pass, _name.text);
      } else {
        await app.signIn(email, pass);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Digite seu e-mail acima para receber o link.');
      return;
    }
    try {
      await app.auth.sendPasswordReset(email);
      if (mounted) toast(context, 'Enviamos um link de redefinição para $email.');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: const Text('R\$', style: TextStyle(color: C.lime, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 10),
                    Text('Finança', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  ]),
                  const SizedBox(height: 40),
                  Text(_register ? 'Crie sua conta' : 'Boas vindas!',
                      style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2)),
                  const SizedBox(height: 8),
                  Text(
                    _register
                        ? 'Seus gastos do Nubank anotados sozinhos e o ${AppConfig.assistantName} te ajudando a gastar melhor.'
                        : 'Tudo o que entra e sai, organizado e fazendo sentido.',
                    style: t.bodyLarge?.copyWith(color: C.muted, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  if (_register) ...[
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Seu nome', prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _register ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  if (_register) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass2,
                      obscureText: _hide,
                      onSubmitted: (_) => _submit(),
                      decoration:
                          const InputDecoration(labelText: 'Confirmar senha', prefixIcon: Icon(Icons.lock_outline)),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(_error!, style: const TextStyle(color: C.red)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(_register ? 'Criar conta' : 'Entrar'),
                  ),
                  if (!_register)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TextButton(onPressed: _forgot, child: const Text('Esqueci minha senha')),
                    ),
                  const SizedBox(height: 18),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(_register ? 'Já tem conta?' : 'Ainda não tem conta?', style: const TextStyle(color: C.muted)),
                    TextButton(
                      onPressed: () => setState(() {
                        _register = !_register;
                        _error = null;
                      }),
                      child: Text(_register ? 'Entrar' : 'Criar conta'),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.verified_user_outlined, size: 16, color: C.muted),
                    SizedBox(width: 6),
                    Text('Login protegido pelo Firebase', style: TextStyle(color: C.muted, fontSize: 12)),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
