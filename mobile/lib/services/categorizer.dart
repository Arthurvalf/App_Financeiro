/// Categorização instantânea por palavras-chave (funciona offline).
/// O que cair em "Outros" é enviado depois para o José Pinto (Gemini).
const _rules = <String, List<String>>{
  'Comida': [
    'ifood', 'i food', 'rappi', 'restaurante', 'lanchonete', 'padaria', 'mercado', 'supermercado',
    'burger', 'mcdonald', 'mc donald', 'pizza', 'acai', 'açaí', 'sushi', 'cafe', 'café', 'cafeteria',
    'assai', 'atacadao', 'atacadão', 'carrefour', 'pao de acucar', 'pão de açúcar', 'hortifruti',
    'ze delivery', 'zé delivery', 'outback', 'subway', 'habib', 'bobs', 'giraffas', 'starbucks',
    'churrascaria', 'pastel', 'sorvete', 'doceria', 'emporio', 'empório', 'acougue', 'açougue',
  ],
  'Transporte': [
    'uber', '99app', '99 app', '99pop', '99 taxi', 'cabify', 'posto', 'shell', 'ipiranga', 'petrobras',
    'br mania', 'combustivel', 'combustível', 'estacionamento', 'metro', 'metrô', 'onibus', 'ônibus',
    'bilhete unico', 'sem parar', 'veloe', 'conectcar', 'pedagio', 'pedágio', 'buser', 'latam', 'gol linhas',
    'azul linhas', 'blablacar',
  ],
  'Mensalidades': [
    'netflix', 'spotify', 'amazon prime', 'prime video', 'disney', 'hbo', 'youtube premium', 'youtube',
    'apple.com', 'icloud', 'google one', 'google storage', 'deezer', 'globoplay', 'paramount', 'crunchyroll',
    'academia', 'smartfit', 'smart fit', 'bluefit', 'mensalidade', 'assinatura', 'chatgpt', 'openai',
    'anthropic', 'claude.ai', 'github', 'microsoft 365', 'adobe', 'canva', 'gympass', 'wellhub', 'twitch',
  ],
  'Casa': [
    'aluguel', 'condominio', 'condomínio', 'enel', 'sabesp', 'cemig', 'copel', 'coelba', 'celesc',
    'energia', 'conta de luz', 'conta de agua', 'comgas', 'comgás', 'gas ', 'claro', 'vivo', 'tim ',
    'internet', 'leroy', 'telhanorte', 'tok&stok', 'tok stok', 'casas bahia', 'iptu',
  ],
  'Saúde': [
    'farmacia', 'farmácia', 'drogasil', 'droga raia', 'drogaria', 'pague menos', 'panvel', 'hospital',
    'clinica', 'clínica', 'laboratorio', 'laboratório', 'unimed', 'amil', 'hapvida', 'dentista', 'odonto',
    'psicolog', 'consulta', 'exame',
  ],
  'Educação': [
    'curso', 'udemy', 'alura', 'escola', 'faculdade', 'universidade', 'livraria', 'livro', 'rocketseat',
    'coursera', 'duolingo', 'kindle', 'estacio', 'estácio', 'anhanguera', 'unip', 'fiap',
  ],
  'Lazer': [
    'cinema', 'cinemark', 'ingresso', 'sympla', 'eventim', 'steam', 'playstation', 'psn', 'xbox',
    'nintendo', 'riot', 'epic games', 'show', 'teatro', 'parque', 'boliche', 'balada', 'bar ', 'boteco',
    'cervejaria', 'airbnb', 'booking', 'hotel', 'viagem',
  ],
  'Compras': [
    'amazon', 'mercado livre', 'mercadolivre', 'mercadopago', 'shopee', 'aliexpress', 'magalu',
    'magazine luiza', 'americanas', 'shein', 'renner', 'riachuelo', 'c&a', 'zara', 'kabum', 'centauro',
    'netshoes', 'nike', 'adidas', 'decathlon', 'temu', 'loja',
  ],
  'Investimentos': [
    'investimento', 'aplicação', 'aplicacao', 'tesouro', 'cdb', 'corretora', 'nuinvest', 'caixinha',
    'xp invest', 'btg', 'rico invest', 'clear corretora', 'binance', 'bitcoin',
  ],
  'Transferências': ['pix', 'transferência', 'transferencia', 'ted ', 'doc '],
};

String guessCategory(String description, {bool isIncome = false}) {
  if (isIncome) return 'Renda';
  final d = ' ${description.toLowerCase()} ';
  for (final entry in _rules.entries) {
    for (final k in entry.value) {
      if (d.contains(k)) return entry.key;
    }
  }
  return 'Outros';
}
