import 'package:flutter_test/flutter_test.dart';
import 'package:bilibeats/main.dart';

void main() {
  testWidgets('bilibeat App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BiliBeatApp());
    expect(find.byType(BiliBeatApp), findsOneWidget);
  });
}
