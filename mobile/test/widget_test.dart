import 'package:flutter_test/flutter_test.dart';
import 'package:madini_tracker/utils.dart';

void main() {
  test('UUID ina muundo sahihi na ni ya kipekee', () {
    final a = newUuid();
    final b = newUuid();
    expect(a, isNot(b));
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(a),
      isTrue,
    );
  });

  test('Grade na recovery', () {
    expect(gradeGpt(5, 1000), closeTo(5, 0.0001));
    expect(gradeGpt(5, 0), 0);
    expect(recoveryPercent(4, 5), closeTo(80, 0.0001));
    expect(recoveryPercent(4, null), isNull);
  });

  test('Malipo ya mfanyakazi', () {
    expect(calcPay('Siku', 20000, 10), 200000);
    expect(calcPay('Mwezi', 600000, 5), 600000);
    expect(calcPay('Mgawo', 0, 5), 0);
  });

  test('Hesabu ya mauzo ya dhahabu', () {
    final c = calcSale(
      weightG: 100,
      purityPct: 90,
      pricePerG: 200000,
      royaltyPct: 6,
      inspectionPct: 1,
      otherFees: 100000,
    );
    expect(c.fineGold, closeTo(90, 0.0001));
    expect(c.gross, closeTo(18000000, 0.01));
    expect(c.royalty, closeTo(1080000, 0.01));
    expect(c.inspection, closeTo(180000, 0.01));
    expect(c.net, closeTo(16640000, 0.01));
  });

  test('Umbizo wa namba na tarehe', () {
    expect(fmtNum(1234567.891), '1,234,567.89');
    expect(fmtNum(-1500, decimals: 0), '-1,500');
    expect(nextDay('2026-12-31'), '2027-01-01');
    expect(parseNum('1,250.5'), 1250.5);
  });

  test('CSV inalinda koma na nukuu', () {
    final csv = toCsv([
      {'a': 'x,y', 'b': 'she said "hi"'}
    ], ['a', 'b']);
    expect(csv, 'a,b\n"x,y","she said ""hi"""\n');
  });
}
