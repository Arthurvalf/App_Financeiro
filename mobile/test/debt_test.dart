import 'package:financa/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Debt debt() => Debt(
        id: 'd1',
        name: 'Notebook',
        kind: 'cartao',
        installmentAmount: 300,
        installments: 10,
        firstDue: DateTime(2026, 1, 31),
      );

  test('vencimentos respeitam meses curtos', () {
    final d = debt();
    expect(d.dueOf(0), DateTime(2026, 1, 31));
    expect(d.dueOf(1), DateTime(2026, 2, 28));
    expect(d.dueOf(2), DateTime(2026, 3, 31));
  });

  test('parcelas pagas e restantes', () {
    final d = debt();
    final now = DateTime(2026, 3, 31, 12);
    expect(d.paidCount(now), 3);
    expect(d.remainingCount(now), 7);
    expect(d.remainingAmount(now), 2100);
    expect(d.nextDue(now), DateTime(2026, 4, 30));
    expect(d.total, 3000);
  });

  test('quanto cai em cada mês', () {
    final d = debt();
    expect(d.amountInMonth(DateTime(2026, 5)), 300);
    expect(d.amountInMonth(DateTime(2026, 11)), 0);
  });

  test('regra de categoria', () {
    final r = Rule(id: 'r', pattern: 'Posto', category: 'Transporte');
    expect(r.matches('POSTO SHELL 123'), true);
    expect(r.matches('Mercado'), false);
  });
}
