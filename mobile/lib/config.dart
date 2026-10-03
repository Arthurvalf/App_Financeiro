/// Configuração pública do app.
///
/// A chave web do Firebase é pública por design (vai dentro de qualquer app
/// cliente); quem protege os dados são as regras do Firestore.
/// A chave do Gemini NÃO fica aqui: o usuário cola no app (Perfil) e ela é
/// salva só na conta dele.
class AppConfig {
  static const firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyDByf_O_uxFNloqTN22A-UTwprVaiZB9Vw',
  );
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'app-financeiro-5e4a0',
  );

  /// Modelos tentados em ordem. O primeiro que responder fica memorizado.
  static const geminiModels = <String>[
    'gemini-flash-latest',
    'gemini-3.5-flash',
    'gemini-3.1-flash-lite',
    'gemini-3.8-flash',
    'gemini-flash-lite-latest',
  ];

  static const assistantName = 'José Pinto';
}
