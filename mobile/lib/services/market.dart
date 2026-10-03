import 'dart:convert';

import 'package:http/http.dart' as http;

/// Taxas oficiais do Banco Central (API pública SGS, sem chave).
class MarketRates {
  MarketRates({required this.selic, required this.cdi, required this.ipca12m, required this.live, this.asOf});
  final double selic; // % a.a. (meta)
  final double cdi; // % a.a.
  final double ipca12m; // % acumulado 12 meses
  final bool live; // true = veio do Banco Central agora
  final String? asOf;

  /// Poupança: 0,5% a.m. + TR quando Selic > 8,5%; senão 70% da Selic (TR ignorada).
  double get poupanca => selic > 8.5 ? 6.17 : selic * 0.7;
}

class Market {
  static MarketRates? _cache;
  static DateTime? _at;

  /// Valores de reserva caso a API não responda (editáveis no simulador).
  static final fallback = MarketRates(selic: 14.25, cdi: 14.15, ipca12m: 5.0, live: false);

  static Future<MarketRates> rates() async {
    if (_cache != null && _at != null && DateTime.now().difference(_at!).inHours < 6) return _cache!;
    try {
      final r = await Future.wait([_last(432), _last(4389), _last(13522)]);
      final selic = r[0]?.$1;
      if (selic == null) return fallback;
      _cache = MarketRates(
        selic: selic,
        cdi: r[1]?.$1 ?? selic - 0.1,
        ipca12m: r[2]?.$1 ?? fallback.ipca12m,
        live: true,
        asOf: r[0]?.$2,
      );
      _at = DateTime.now();
      return _cache!;
    } catch (_) {
      return fallback;
    }
  }

  static Future<(double, String)?> _last(int series) async {
    try {
      final res = await http
          .get(Uri.parse('https://api.bcb.gov.br/dados/serie/bcdata.sgs.$series/dados/ultimos/1?formato=json'))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body) as List;
      if (list.isEmpty) return null;
      final m = list.last as Map<String, dynamic>;
      final v = double.tryParse('${m['valor']}'.replaceAll(',', '.'));
      if (v == null) return null;
      return (v, '${m['data']}');
    } catch (_) {
      return null;
    }
  }
}
