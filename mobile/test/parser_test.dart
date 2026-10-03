import 'package:financa/services/capture.dart';
import 'package:financa/services/categorizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compra no crédito do Nubank', () {
    final p = parseBankNotification(
        'Compra no crédito aprovada', 'Compra de R\$ 45,90 APROVADA em IFOOD *RESTAURANTE para o cartão com final 1234.')!;
    expect(p.amount, 45.90);
    expect(p.isIncome, false);
    expect(p.description, 'Ifood Restaurante');
    expect(p.category, 'Comida');
  });

  test('valor com milhar', () {
    final p = parseBankNotification('Compra aprovada', 'Compra de R\$ 1.234,56 APROVADA em KABUM para o cartão final 9999')!;
    expect(p.amount, 1234.56);
    expect(p.category, 'Compras');
  });

  test('pix enviado para pessoa', () {
    final p = parseBankNotification('Transferência enviada', 'Você enviou uma transferência de R\$ 50,00 para Maria Souza.')!;
    expect(p.amount, 50);
    expect(p.isIncome, false);
    expect(p.description, 'Maria Souza');
    expect(p.category, 'Transferências');
  });

  test('pix recebido', () {
    final p = parseBankNotification('Transferência recebida', 'Você recebeu uma transferência de R\$ 120,00 de João Lima.')!;
    expect(p.amount, 120);
    expect(p.isIncome, true);
    expect(p.category, 'Renda');
    expect(p.description, 'João Lima');
  });

  test('ignora fatura e compra negada', () {
    expect(parseBankNotification('Fatura fechada', 'Sua fatura de R\$ 800,00 fechou.'), isNull);
    expect(parseBankNotification('Compra negada', 'Compra de R\$ 10,00 negada em LOJA X'), isNull);
    expect(parseBankNotification('Novidade', 'Conheça a caixinha turbo!'), isNull);
  });

  test('categorias por palavra-chave', () {
    expect(guessCategory('Uber *Trip'), 'Transporte');
    expect(guessCategory('NETFLIX.COM'), 'Mensalidades');
    expect(guessCategory('Drogasil'), 'Saúde');
    expect(guessCategory('Salário', isIncome: true), 'Renda');
    expect(guessCategory('xyz qualquer'), 'Outros');
  });
}
