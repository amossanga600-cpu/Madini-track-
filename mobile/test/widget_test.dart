import 'package:flutter_test/flutter_test.dart';
import 'package:madini_tracker/main.dart';

void main() {
  testWidgets('Madini Track dashboard opens', (tester) async {
    await tester.pumpWidget(const MadiniTrackApp());

    expect(find.text('Madini Track Tanzania'), findsOneWidget);
    expect(find.text('Uingizaji wa Uzalishaji'), findsOneWidget);
  });
}
