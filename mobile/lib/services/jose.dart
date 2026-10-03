import 'dart:convert';

import 'package:intl/intl.dart';

import '../config.dart';
import '../models.dart';
import '../state/app_state.dart';
import 'market.dart';

final _f = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
String _m(double v) => _f.format(v);

/// O cérebro do José Pinto: persona, conhecimento financeiro, contexto real e ações.
class Jose {
  Jose(this.app);
  final AppState app;

  static const _playbook = '''
MANUAL DO JOSÉ (use como base de raciocínio, sem recitar):
• Ordem de prioridades: 1) quitar dívidas caras (rotativo do cartão ~400% a.a., cheque especial, empréstimo pessoal) →
  2) reserva de emergência (6 meses de gastos; 12 se renda variável) em liquidez diária: Tesouro Selic, CDB 100%+ do CDI
  com liquidez diária, caixinhas que rendem 100% do CDI → 3) objetivos com prazo (casar o prazo do título com o do objetivo)
  → 4) longo prazo/aposentadoria (Tesouro IPCA+, ETFs, ações, FIIs).
• Renda fixa: IR regressivo (22,5% até 180 dias; 20% até 360; 17,5% até 720; 15% acima). LCI/LCA/CRI/CRA/debêntures
  incentivadas são isentas de IR para pessoa física — compare pelo "CDI equivalente". FGC cobre até R\$ 250 mil por CPF por
  instituição (CDB, LCI, LCA, poupança). Tesouro Direto tem garantia do Tesouro Nacional; marcação a mercado afeta quem vende antes.
• Poupança rende menos que 100% do CDI quando a Selic está alta. Fundos DI com taxa de administração alta perdem para Tesouro Selic.
• Renda variável: diversificar (ETFs como BOVA11, IVVB11, SMAL11; FIIs de tijolo/papel), aportes mensais, horizonte 5+ anos.
  Ações isentas de IR em vendas até R\$ 20 mil/mês (swing trade); FIIs: rendimentos isentos, ganho de capital 20%.
• Cripto: no máximo uma fatia pequena (até ~5%) e só para perfil arrojado com reserva pronta.
• Orçamento: referência 50/30/20 (necessidades/desejos/futuro); "pague-se primeiro" no dia do salário.
• Compras: parcelar sem juros é ok se cabe no orçamento dos próximos meses; nunca entrar no rotativo; desconfiar de juros embutidos.
• Para dívidas: método avalanche (maior juro primeiro) economiza mais; bola de neve (menor saldo primeiro) motiva.
• Sempre mostre a conta: valores em R\$, prazos, quanto rende/custa. Seja específico com os números do usuário.
''';

  Future<String> _system() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final names = allCats.map((c) => c.name).join(', ');
    final rates = await Market.rates();
    return '''
Você é ${AppConfig.assistantName}, o assistente financeiro pessoal do app Finança — um gênio de finanças pessoais e
investimentos no Brasil, com o raciocínio de um planejador financeiro certificado (CFP) e a conversa de um amigo.
Português do Brasil, tom próximo, direto e com bom humor na medida, sem jargão (se usar um termo técnico, explique em meia frase).

COMO PENSAR
• Antes de responder, analise os números reais do contexto abaixo (previsões, médias, dívidas, reserva, recorrências).
  Nunca invente transações ou saldos. Se faltar um dado importante, faça UMA pergunta objetiva.
• Dê recomendações concretas e acionáveis: o quê, quanto (R\$) e quando. Mostre contas curtas quando ajudarem.
• Em investimentos, considere perfil de risco, horizonte, reserva de emergência e dívidas. Cite produtos reais do mercado
  brasileiro e taxas atuais. Use a busca do Google quando precisar de cotações, taxas ou notícias recentes.
  Lembre de forma breve que não é recomendação formal quando sugerir ativos específicos.
• Seja breve: até ~170 palavras, a não ser que peçam detalhe. Listas curtas com "•". Sem tabelas e sem títulos com #.
  Use **negrito** só para o número ou a ideia principal.

$_playbook

AÇÕES (o app executa): quando fizer sentido, escreva NO FINAL da resposta uma linha por ação, JSON numa linha só:
ACAO: {"tipo":"transacao","descricao":"Almoço","valor":32.5,"entrada":false,"categoria":"Comida","data":"$today"}
ACAO: {"tipo":"meta","categoria":"Lazer","limite":300}
ACAO: {"tipo":"divida","nome":"Notebook","parcela":350,"parcelas":10,"primeira":"$today","tipo_divida":"cartao","juros_mes":0}
ACAO: {"tipo":"categoria","nome":"Pet"}
ACAO: {"tipo":"regra","contem":"petz","categoria":"Pet"}
ACAO: {"tipo":"lembrar","fato":"Está juntando R\$ 8 mil para viajar em julho de 2027"}
Use "lembrar" sempre que o usuário contar algo duradouro sobre a vida financeira dele (salário, objetivos, dependentes,
planos, preferências). Não repita fatos que já estão na memória.
Categorias válidas hoje: $names. Hoje é $today.

=== MEMÓRIA (o que você já sabe sobre o usuário) ===
${app.memories.isEmpty ? '(nada ainda)' : app.memories.map((m) => '• ${m.text}').join('\n')}

=== TAXAS ${rates.live ? 'DO BANCO CENTRAL (atualizadas)' : '(estimadas — confira na busca)'} ===
Selic meta ${rates.selic.toStringAsFixed(2)}% a.a. • CDI ${rates.cdi.toStringAsFixed(2)}% a.a. • IPCA 12m ${rates.ipca12m.toStringAsFixed(2)}% • Poupança ~${rates.poupanca.toStringAsFixed(2)}% a.a.

=== CONTEXTO FINANCEIRO REAL ===
${context()}
''';
  }

  /// Resumo analítico das finanças do usuário.
  String context() {
    final now = DateTime.now();
    final cur = monthOf(now);
    final df = DateFormat('dd/MM');
    final p = app.profile;
    final b = StringBuffer();
    b.writeln('Nome: ${p.name.isEmpty ? 'não informado' : p.name}');
    b.writeln('Perfil investidor: risco ${p.risk}, horizonte ${p.horizon}, conhecimento ${p.knowledge}');
    if (p.monthlyIncome > 0) b.writeln('Renda mensal declarada: ${_m(p.monthlyIncome)}');
    if (p.payday > 0) b.writeln('Dia do salário: ${p.payday}');
    if (p.goals.isNotEmpty) b.writeln('Objetivos declarados: ${p.goals}');

    final fc = app.forecast();
    b.writeln('\nHOJE: dia ${now.day} de ${daysInMonth(now.year, now.month)}.');
    b.writeln('Gasto no mês até agora: ${_m(fc.spentSoFar)} • Previsão de fechamento: ${_m(fc.projected)}'
        '${fc.pendingInstallments > 0 ? ' (inclui ${_m(fc.pendingInstallments)} de parcelas a vencer)' : ''}');
    b.writeln('Renda de referência: ${_m(fc.income)} • Sobra prevista: ${_m(fc.freeAtEnd)}');
    b.writeln('Gasto hoje: ${_m(app.spentOnDay(now))} • Média mensal (3 meses): ${_m(app.avgMonthlySpend())}');

    b.writeln('\nPOR CATEGORIA (mês atual | média 3 meses | meta):');
    final cats = {...app.byCategory(cur).keys, ...app.budgets.keys};
    for (final c in cats) {
      final meta = app.budgets[c];
      b.writeln('  • $c: ${_m(app.spentIn(cur, category: c))} | ${_m(app.avgCategorySpend(c))}'
          '${meta != null ? ' | meta ${_m(meta)}' : ''}');
    }

    b.writeln('\nHISTÓRICO (gastos / entradas / investido):');
    for (var i = 5; i >= 1; i--) {
      final m = DateTime(now.year, now.month - i);
      final s = app.spentIn(m), inc = app.incomeIn(m), inv = app.investedIn(m);
      if (s == 0 && inc == 0 && inv == 0) continue;
      b.writeln('  • ${DateFormat('MM/yyyy').format(m)}: ${_m(s)} / ${_m(inc)} / ${_m(inv)}');
    }

    final rec = app.recurring();
    if (rec.isNotEmpty) {
      final total = rec.fold(0.0, (s, r) => s + r.avgAmount);
      b.writeln('\nGASTOS RECORRENTES detectados (${_m(total)}/mês, ${_m(total * 12)}/ano):');
      for (final r in rec.take(15)) {
        b.writeln('  • ${r.name}: ~${_m(r.avgAmount)} (${r.category}, ${r.months} meses)');
      }
    }

    final active = app.debts.where((d) => !d.finished).toList();
    if (active.isNotEmpty) {
      b.writeln('\nDÍVIDAS E PARCELAS (restante total ${_m(app.totalDebtRemaining)}):');
      for (final d in active) {
        final next = d.nextDue();
        b.writeln('  • ${d.name} (${d.kindLabel}): ${_m(d.installmentAmount)}/mês, '
            '${d.paidCount()}/${d.installments} pagas, faltam ${_m(d.remainingAmount())}'
            '${d.interestMonthly > 0 ? ', juros ${d.interestMonthly}% a.m.' : ''}'
            '${next != null ? ', próxima ${df.format(next)}' : ''}');
      }
      b.writeln('  Comprometido nos próximos meses: ${[
        for (var i = 0; i < 6; i++) '${DateFormat('MM/yy').format(DateTime(now.year, now.month + i))} ${_m(app.commitmentsIn(DateTime(now.year, now.month + i)))}'
      ].join(' • ')}');
    }

    b.writeln('\nPATRIMÔNIO INVESTIDO: ${_m(app.totalInvested)} '
        '(cobre ~${app.emergencyMonths.toStringAsFixed(1)} meses de gastos)');
    for (final i in app.investments.take(15)) {
      b.writeln('  • ${i.name} (${i.kind}): ${_m(i.amount)}');
    }

    final recent = app.txs.take(40);
    if (recent.isNotEmpty) {
      b.writeln('\nÚLTIMOS LANÇAMENTOS:');
      for (final t in recent) {
        b.writeln('  • ${df.format(t.date)} ${t.isIncome ? '+' : '-'}${_m(t.amount)} ${t.description} [${t.category}]');
      }
    }
    return b.toString();
  }

  /// Envia a mensagem, executa as ações e devolve as notas de confirmação.
  Future<List<String>> send(String userText) async {
    app.chat.add(ChatMsg(userText, fromUser: true));
    app.refresh();
    final history = app.chat.length > 24 ? app.chat.sublist(app.chat.length - 24) : List.of(app.chat);
    final reply = await app.gemini.generateFull(
      system: await _system(),
      messages: history,
      temperature: 0.6,
      search: true,
    );

    final notes = <String>[];
    final visible = <String>[];
    for (final line in reply.text.split('\n')) {
      final t = line.trim();
      final up = t.toUpperCase();
      if (up.startsWith('ACAO:') || up.startsWith('AÇÃO:')) {
        final note = await _runAction(t.substring(t.indexOf(':') + 1).trim());
        if (note != null) notes.add(note);
      } else {
        visible.add(line);
      }
    }
    var text = visible.join('\n').trim();
    if (reply.sources.isNotEmpty) {
      text += '\n\nFontes: ${reply.sources.take(3).map((s) => s.title).join(' · ')}';
    }
    app.chat.add(ChatMsg(text, fromUser: false));
    for (final n in notes) {
      app.chat.add(ChatMsg(n, fromUser: false, isNote: true));
    }
    app.refresh();
    return notes;
  }

  Future<String?> _runAction(String raw) async {
    try {
      final a = jsonDecode(raw.replaceAll('`', '').trim()) as Map<String, dynamic>;
      switch (a['tipo']) {
        case 'transacao':
          final valor = _num(a['valor']).abs();
          if (valor <= 0) return null;
          final entrada = a['entrada'] == true;
          final desc = '${a['descricao'] ?? 'Lançamento'}';
          var cat = '${a['categoria'] ?? ''}';
          if (!allCats.any((c) => c.name == cat)) cat = app.categorize(desc, isIncome: entrada);
          final date = DateTime.tryParse('${a['data'] ?? ''}') ?? DateTime.now();
          final now = DateTime.now();
          await app.saveTx(Tx(
            id: newId(),
            description: desc,
            amount: valor,
            isIncome: entrada,
            category: cat,
            date: DateTime(date.year, date.month, date.day, now.hour, now.minute),
            source: 'jose',
          ));
          return 'Anotado: ${entrada ? 'entrada' : 'gasto'} de ${_m(valor)} em $cat ($desc)';
        case 'meta':
          final cat = '${a['categoria']}';
          final lim = _num(a['limite']);
          if (!allCats.any((c) => c.name == cat) || lim <= 0) return null;
          await app.setBudget(cat, lim);
          return 'Meta criada: $cat até ${_m(lim)} por mês';
        case 'divida':
          final parcela = _num(a['parcela']);
          final n = _num(a['parcelas']).round();
          if (parcela <= 0 || n <= 0) return null;
          final kind = '${a['tipo_divida'] ?? 'outro'}';
          final d = Debt(
            id: newId(),
            name: '${a['nome'] ?? 'Dívida'}',
            kind: const ['cartao', 'emprestimo', 'financiamento', 'outro'].contains(kind) ? kind : 'outro',
            installmentAmount: parcela,
            installments: n,
            firstDue: DateTime.tryParse('${a['primeira'] ?? ''}') ?? DateTime.now(),
            interestMonthly: _num(a['juros_mes']),
            autoLaunch: kind == 'cartao',
          );
          await app.saveDebt(d);
          return 'Dívida registrada: ${d.name}, ${n}x de ${_m(parcela)}';
        case 'categoria':
          final nome = '${a['nome'] ?? ''}'.trim();
          if (nome.isEmpty || allCats.any((c) => c.name.toLowerCase() == nome.toLowerCase())) return null;
          await app.addCategory(nome, 'estrela', colorChoices[allCats.length % colorChoices.length]);
          return 'Categoria criada: $nome';
        case 'regra':
          final contem = '${a['contem'] ?? ''}'.trim();
          final cat = '${a['categoria'] ?? ''}';
          if (contem.isEmpty || !allCats.any((c) => c.name == cat)) return null;
          await app.addRule(contem, cat);
          final changed = await app.applyRulesToAll();
          return 'Regra criada: "$contem" → $cat${changed > 0 ? ' ($changed lançamentos ajustados)' : ''}';
        case 'lembrar':
          final fato = '${a['fato'] ?? ''}'.trim();
          if (fato.isEmpty) return null;
          await app.addMemory(fato);
          return 'Vou lembrar: $fato';
      }
    } catch (_) {}
    return null;
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v'.replaceAll(',', '.')) ?? 0;
  }

  /// 3 insights curtos sobre o mês.
  Future<List<Map<String, String>>> insights() async {
    final res = await app.gemini.generateJson(
      system: await _system(),
      prompt: 'Analise meu mês e me dê exatamente 3 insights práticos e específicos (com valores em R\$), '
          'priorizando o que mais impacta meu dinheiro (previsão de fechamento, recorrências, dívidas, metas, reserva). '
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

  /// "Posso comprar isso?"
  Future<Map<String, dynamic>> canIBuy({
    required String item,
    required double price,
    required int installments,
    required String category,
  }) async {
    final now = DateTime.now();
    final fc = app.forecast();
    final parcela = price / installments;
    final budget = app.budgets[category];
    final spentCat = app.spentIn(monthOf(now), category: category);
    final facts = StringBuffer()
      ..writeln('Compra: $item — ${_m(price)} ${installments > 1 ? 'em ${installments}x de ${_m(parcela)}' : 'à vista'}')
      ..writeln('Categoria: $category (gasto no mês ${_m(spentCat)}${budget != null ? ', meta ${_m(budget)}' : ', sem meta'})')
      ..writeln('Sobra prevista no fim do mês sem a compra: ${_m(fc.freeAtEnd)}')
      ..writeln('Parcelas já comprometidas: ${[
        for (var i = 0; i < 6; i++) '${DateFormat('MM/yy').format(DateTime(now.year, now.month + i))} ${_m(app.commitmentsIn(DateTime(now.year, now.month + i)))}'
      ].join(' • ')}')
      ..writeln('Reserva cobre ~${app.emergencyMonths.toStringAsFixed(1)} meses de gastos');
    final res = await app.gemini.generateJson(
      system: await _system(),
      prompt: 'Quero saber se posso fazer esta compra agora.\n$facts\n'
          'Pense como um planejador financeiro: impacto no mês, nos próximos meses, nas metas, na reserva e nos objetivos. '
          'Responda JSON: {"veredito":"sim|com cuidado|não agora","nota":0-10,"resumo":"1 a 2 frases diretas",'
          '"impacto":"o que muda nos números (com R\$)","pontos":["até 3 motivos curtos"],'
          '"alternativa":"sugestão para comprar melhor (esperar, juntar, parcelar, versão mais barata)",'
          '"quando":"melhor momento para comprar, se não for agora"}',
      temperature: 0.4,
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  /// Recomendações de investimento com nota e risco.
  Future<Map<String, dynamic>> recommendations(double monthly) async {
    final res = await app.gemini.generateJson(
      system: await _system(),
      prompt: 'Monte recomendações de investimento para mim. Posso investir cerca de ${_m(monthly)} por mês. '
          'Siga meu perfil e a ordem de prioridades (dívidas caras, reserva, objetivos, longo prazo). '
          'Use as taxas atuais do contexto para estimar retornos líquidos. Dê de 4 a 6 opções ordenadas pela prioridade. '
          'Responda JSON: {"resumo":"2 frases","reserva_emergencia":"situação da minha reserva e quanto falta",'
          '"recomendacoes":[{"nome":"","tipo":"Renda fixa|Fundos|ETF|Ações|FII|Cripto","risco":"baixo|médio|alto",'
          '"nota":1-5,"retorno":"estimativa líquida curta","prazo":"","porque":"até 30 palavras","quanto":"valor mensal sugerido"}]}',
      temperature: 0.4,
    );
    return res is Map<String, dynamic> ? res : <String, dynamic>{};
  }

  /// Sugestões de metas por categoria.
  Future<List<Map<String, dynamic>>> budgetSuggestions() async {
    final res = await app.gemini.generateJson(
      system: await _system(),
      prompt: 'Sugira metas mensais (limites) para minhas principais categorias de gasto, realistas com base nas médias, '
          'mas que me façam economizar. Responda JSON: '
          '{"metas":[{"categoria":"uma das categorias válidas","limite":0,"motivo":"até 20 palavras"}]}',
    );
    final list = (res is Map ? res['metas'] : res) as List? ?? const [];
    return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  /// Comentário curto sobre as dívidas (qual pagar primeiro etc.).
  Future<String> debtAdvice() async {
    return app.gemini.generate(
      system: await _system(),
      messages: [
        ChatMsg(
            'Olhe minhas dívidas e parcelas e me diga, em até 90 palavras, qual estratégia seguir '
            '(o que quitar ou amortizar primeiro, se vale antecipar, e quanto isso economiza).',
            fromUser: true)
      ],
      temperature: 0.4,
    );
  }
}
