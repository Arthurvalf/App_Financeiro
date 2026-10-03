import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Login com e-mail e senha usando a API REST do Firebase Authentication.
/// Cada usuário tem sua própria conta; a sessão fica salva no aparelho.
class AuthService {
  String? uid;
  String? email;
  String? displayName;
  String? _idToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  bool get signedIn => uid != null && _refreshToken != null;

  static const _prefsKey = 'financa_session_v1';
  static final _identity = 'https://identitytoolkit.googleapis.com/v1/accounts';

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      uid = m['uid'] as String?;
      email = m['email'] as String?;
      displayName = m['displayName'] as String?;
      _idToken = m['idToken'] as String?;
      _refreshToken = m['refreshToken'] as String?;
      final exp = m['expiresAt'] as String?;
      _expiresAt = exp == null ? null : DateTime.tryParse(exp);
    } catch (_) {
      await prefs.remove(_prefsKey);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'idToken': _idToken,
        'refreshToken': _refreshToken,
        'expiresAt': _expiresAt?.toIso8601String(),
      }),
    );
  }

  Future<Map<String, dynamic>> _post(String action, Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$_identity:$action?key=${AppConfig.firebaseApiKey}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw AuthException('Sem conexão. Verifique sua internet e tente de novo.');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final code = ((data['error'] as Map?)?['message'] ?? '').toString();
      throw AuthException(_friendly(code));
    }
    return data;
  }

  String _friendly(String code) {
    if (code.startsWith('EMAIL_EXISTS')) return 'Já existe uma conta com esse e-mail.';
    if (code.startsWith('INVALID_LOGIN_CREDENTIALS') ||
        code.startsWith('INVALID_PASSWORD') ||
        code.startsWith('EMAIL_NOT_FOUND')) {
      return 'E-mail ou senha incorretos.';
    }
    if (code.startsWith('WEAK_PASSWORD')) return 'A senha precisa ter pelo menos 6 caracteres.';
    if (code.startsWith('INVALID_EMAIL')) return 'E-mail inválido.';
    if (code.startsWith('TOO_MANY_ATTEMPTS')) return 'Muitas tentativas. Espere alguns minutos.';
    if (code.startsWith('USER_DISABLED')) return 'Esta conta foi desativada.';
    if (code.startsWith('OPERATION_NOT_ALLOWED')) {
      return 'Login por e-mail/senha não está ativado no Firebase (Authentication > Sign-in method).';
    }
    if (code.contains('API key not valid') || code.contains('API_KEY')) {
      return 'Chave do Firebase inválida. Confira o arquivo lib/config.dart.';
    }
    return 'Erro de autenticação ($code).';
  }

  void _applyTokens(Map<String, dynamic> d) {
    uid = (d['localId'] ?? d['user_id'] ?? uid) as String?;
    email = (d['email'] ?? email) as String?;
    final dn = d['displayName'];
    if (dn is String && dn.isNotEmpty) displayName = dn;
    _idToken = (d['idToken'] ?? d['id_token']) as String?;
    _refreshToken = (d['refreshToken'] ?? d['refresh_token'] ?? _refreshToken) as String?;
    final secs = int.tryParse('${d['expiresIn'] ?? d['expires_in'] ?? 3600}') ?? 3600;
    _expiresAt = DateTime.now().add(Duration(seconds: secs - 120));
  }

  Future<void> signUp(String email, String password, String name) async {
    final d = await _post('signUp', {
      'email': email.trim(),
      'password': password,
      'returnSecureToken': true,
    });
    _applyTokens(d);
    if (name.trim().isNotEmpty) {
      try {
        await _post('update', {
          'idToken': _idToken,
          'displayName': name.trim(),
          'returnSecureToken': false,
        });
        displayName = name.trim();
      } catch (_) {}
    }
    await _persist();
  }

  Future<void> signIn(String email, String password) async {
    final d = await _post('signInWithPassword', {
      'email': email.trim(),
      'password': password,
      'returnSecureToken': true,
    });
    _applyTokens(d);
    await _persist();
  }

  Future<void> sendPasswordReset(String email) async {
    await _post('sendOobCode', {'requestType': 'PASSWORD_RESET', 'email': email.trim()});
  }

  Future<void> signOut() async {
    uid = null;
    email = null;
    displayName = null;
    _idToken = null;
    _refreshToken = null;
    _expiresAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Devolve um token válido, renovando quando necessário.
  Future<String> validIdToken({bool forceRefresh = false}) async {
    if (_refreshToken == null) throw AuthException('Sessão encerrada. Entre novamente.');
    final fresh = _idToken != null && _expiresAt != null && DateTime.now().isBefore(_expiresAt!);
    if (fresh && !forceRefresh) return _idToken!;
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('https://securetoken.googleapis.com/v1/token?key=${AppConfig.firebaseApiKey}'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'grant_type=refresh_token&refresh_token=${Uri.encodeQueryComponent(_refreshToken!)}',
          )
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw AuthException('Sem conexão.');
    }
    if (res.statusCode != 200) {
      await signOut();
      throw AuthException('Sua sessão expirou. Entre novamente.');
    }
    _applyTokens(jsonDecode(res.body) as Map<String, dynamic>);
    await _persist();
    return _idToken!;
  }
}
