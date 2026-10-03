import 'dart:convert';

/// Configuração pública do app.
///
/// A chave web do Firebase é pública por design (vai dentro de qualquer app
/// cliente); quem protege os dados são as regras do Firestore.
///
/// A chave do Gemini NÃO fica no código: o GitHub Actions lê o segredo
/// GEMINI_API_KEY, embaralha e injeta no APK na hora do build
/// (--dart-define=GEMINI_KEY_X=...). O app desembaralha só em memória.
class AppConfig {
  static const firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyDByf_O_uxFNloqTN22A-UTwprVaiZB9Vw',
  );
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'app-financeiro-5e4a0',
  );

  static const _keyX = String.fromEnvironment('GEMINI_KEY_X');
  static const _mask = 'jose-pinto-financa';

  /// Chave do Gemini embutida no build (vazia se o segredo não foi configurado).
  static String get embeddedGeminiKey {
    if (_keyX.isEmpty) return '';
    try {
      final bytes = base64.decode(_keyX);
      final m = utf8.encode(_mask);
      return utf8.decode([for (var i = 0; i < bytes.length; i++) bytes[i] ^ m[i % m.length]]);
    } catch (_) {
      return '';
    }
  }

  static bool get hasEmbeddedKey => _keyX.isNotEmpty;

  /// Cérebro principal do José (conversas, análises, investimentos).
  static const smartModels = <String>[
    'gemini-3.8-flash',
    'gemini-flash-latest',
    'gemini-3.7-flash',
    'gemini-3.5-flash',
    'gemini-3.1-flash-lite',
  ];

  /// Tarefas rápidas e baratas (categorizar gastos).
  static const fastModels = <String>[
    'gemini-3.1-flash-lite',
    'gemini-flash-lite-latest',
    'gemini-3.5-flash-lite',
    'gemini-flash-latest',
    'gemini-3.5-flash',
  ];

  static const assistantName = 'José Pinto';
}
