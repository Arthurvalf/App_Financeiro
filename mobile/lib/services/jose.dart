import 'dart:convert';

import 'package:intl/intl.dart';

import '../config.dart';
import '../models.dart';
import '../state/app_state.dart';
import 'categorizer.dart';

/// O cérebro do José Pinto: persona, contexto financeiro e ações.
class Jose {
  Jose(this.app);
  final AppState app;

  String _system() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final names = cats.map((c) => c.name).join(', ');
    return '''
Você é ${AppConfig.assistantName}, o assistente financeiro pessoal dentro do app Finança.
Fale em português do Brasil, com tom próximo, direto e com um toque de bom humor, sem jargão.
Você enxerga a vida financeira real do usuário (contexto abaixo). Use esses números; nunca invente transações.

Como ajudar:
• Gastos: aponte padrões, exageros e cortes concretos (com valores em R\$).
• Metas: sugira limites realistas por categoria com base no histórico.
• Investimentos: considere o perfil de risco, horizonte e quanto sobra por mês. Sugira opções reais do mercado
  brasileiro (Tesouro Selic, Tesouro IPCA+, CDB de liquidez diária, LCI/LCA, fundos, ETFs como BOVA11/IVVB11,
  FIIs, ações) e explique o risco de cada uma. Primeiro reserva de emergência, depois o resto.
  Avise que taxas mudam e que isso não é recomendação formal de investimento.
• Seja breve: até ~150 palavras, a não ser que peçam detalhe. Listas curtas com "•". Sem tabelas e sem títulos com #.

AÇÕES: quando o usuário pedir para anotar um gasto/entrada ou criar uma meta, faça e, NO FINAL da resposta,
escreva uma linha por ação exatamente assim (JSON numa linha só):
ACAO: {"tipo":"transacao","descricao":"Almoço","valor":32.5,"entrada":false,"categoria":"Comida","data":"$today"}
ACAO: {"tipo":"meta","categoria":"Lazer","limite":300}
Categorias válidas: $names.
Hoje é $today.

=== CONTEXTO FINANCEIRO DO USUÁRIO ===
${app.financialContext()}
''';
  }

  /// Envia a mensagem, executa ações pedidas e devolve as notas de confirmação.
  Future<List<String>> send(String userText) async {
    app.chat.add(ChatMsg(userText, fromUser: true));
    app.refresh();
    final history = app.chat.length > 20 ? app.chat.sublist(app.chat.length - 20) : List.of(app.chat);
    final reply = await app.gemini.generate(system: _system(), messages: history, temperature: 0.7);

    final notes = <String>[];
    final visible = <String>[];
    for (final line in reply.split('\n')) {
      final t = line.trim();
      if (t.toUpperCase().startsWith('ACAO:') || t.toUpperCase().startsWith('AÇÃO:')) {
        final note = await _runAction(t.substring(t.indexOf(':') + 1).trim());
        if (note != null) notes.add(note);
      } else {
        visible.add(line);
      }
    }
    app.chat.add(ChatMsg(visible.join('\n').trim(), fromUser: false));
    for (final n in notes) {
      app.chat.add(ChatMsg(n, fromUser: false, isNote: true));
    }
    app.refresh();
    return notes;
  }

  Future<String?> _runAction(String raw) async {
    try {
      var s = raw.replaceAll('`', '').trim();
      final a = jsonDecode(s) as Map<String, dynamic>;
      final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
      if (a['tipo'] == 'transacao') {
        final valor = (a['valor'] as num).toDouble().abs();
        if (valor <= 0) return null;
        final entrada = a['entrada'] == true;
        final desc = '${a['descricao'] ?? 'Lançamento'}';
        var cat = '${a['categoria'] ?? ''}';
        if (!cats.any((c) => c.name == cat)) cat = guessCategory(desc, isIncome: entrada);
        final date = DateTime.tryParse('${a['data'] ?? ''}') ?? DateTime.now();
        final now = DateTime.now();
        final when = DateTime(date.year, date.month, date.day, now.hour, now.minute);
        await app.saveTx(Tx(
          id: newId(),
          description: desc,
          amount: valor,
          isIncome: entrada,
          category: cat,
          date: when,
          source: 'jose',
        ));
        return 'Anotado: ${entrada ? 'entrada' : 'gasto'} de ${f.format(valor)} em $cat ($desc).';
      }
      if (a['tipo'] == 'meta') {
        final cat = '${a['categoria']}';
        final lim = (a['limite'] as num).toDouble();
        if (!cats.any((c) => c.name == cat) || lim <= 0) return null;
        await app.setBudget(cat, lim);
        return 'Meta criada: $cat até ${f.format(lim)} por mês.';
      }
    } catch (_) {}
    return null;
  }

  /// 3 insights curtos sobre o mês.
  Future<List<Map<String, String>>> insights() async {
    final res = await app.gemini.generateJson(
      system: _system(),
      prompt: 'Analise meu mês e me dê exatamente 3 insights práticos e específicos (com valores). '
          'Responda JSON: {"insights":[{"titulo":"até 6 palavras","texto":"até 35 palavras","tipo":"alerta|dica|elogio"}]}',
    );
    final list = (res is Map ? res['insights'] : res) as List? ?? const [];
    return list
        .whereType<Map>()
        .map((m) => {
              'titulo': '${m['titulo'] ?? ''}',
              'texto': '${m['texto'] ?? ''}',
              'tipo': '${m['tipo'] ?? 'dica'}',
            })
        .toList();
  }

  /// Recomendações de investimento com nota (rating) e risco.
  Future<Map<String, dynamic>> recommendations(double monthly) async {
    final f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final res = await app.gemini.generateJson(
      system: _system(),
      prompt: 'Monte recomendações de investimento para mim. Posso investir cerca de ${f.format(monthly)} por mês. '
          'Siga meu perfil (risco ${app.profile.risk}, horizonte ${app.profile.horizon}, conhecimento ${app.profile.knowledge}). '
          'Dê de 4 a 6 opções ordenadas pela prioridade. '
          'Responda JSON: {"resumo":"2 frases","reserva_emergencia":"comentário curto sobre a reserva",'
          '"recomendacoes":[{"nome":"","tipo":"Renda fixa|Fundos|ETF|Ações|FII|Cripto","risco":"baixo|médio|alto",'
          '"nota":1-5,"retorno":"estimativa curta","prazo":"","porque":"até 30 palavras","quanto":"sugestão de valor mensal"}]}',
      temperature: 0.5,
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  /// Sugestões de metas por categoria.
  Future<List<Map<String, dynamic>>> budgetSuggestions() async {
    final res = await app.gemini.generateJson(
      system: _system(),
      prompt: 'Sugira metas mensais (limites) para minhas principais categorias de gasto, '
          'realistas mas que me façam economizar. Responda JSON: '
          '{"metas":[{"categoria":"uma das categorias válidas","limite":0,"motivo":"até 20 palavras"}]}',
    );
    final list = (res is Map ? res['metas'] : res) as List? ?? const [];
    return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }
}
