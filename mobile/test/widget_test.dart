import 'package:financa/services/firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('codec do Firestore ida e volta', () {
    final data = {
      'texto': 'iFood',
      'valor': 45.9,
      'inteiro': 3,
      'flag': true,
      'data': DateTime.utc(2026, 10, 3, 12),
      'lista': ['a', 1],
      'mapa': {'x': 1.5},
    };
    final back = decodeFields(encodeFields(data));
    expect(back['texto'], 'iFood');
    expect(back['valor'], 45.9);
    expect(back['inteiro'], 3);
    expect(back['flag'], true);
    expect((back['data'] as DateTime).toUtc(), DateTime.utc(2026, 10, 3, 12));
    expect(back['lista'], ['a', 1]);
    expect((back['mapa'] as Map)['x'], 1.5);
  });
}
