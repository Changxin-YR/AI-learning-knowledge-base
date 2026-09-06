import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow_ai/main.dart';

void main() {
  testWidgets('renders KnowFlow navigation and dashboard', (tester) async {
    await tester.pumpWidget(const KnowFlowApp());
    expect(find.text('KnowFlow AI'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('知识库'), findsOneWidget);
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
