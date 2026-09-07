import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow_ai/main.dart';

void main() {
  testWidgets('renders and navigates all five primary tabs', (tester) async {
    await tester.pumpWidget(const KnowFlowApp());

    expect(find.text('KnowFlow AI'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pump();
    expect(find.text('AI 学习助手'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.library_books_outlined));
    await tester.pump();
    expect(find.text('上传资料，建立自己的可检索上下文'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.school_outlined));
    await tester.pump();
    expect(find.text('让 Agent 把目标拆成今天的下一步'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pump();
    expect(find.text('KnowFlow AI · 学习者空间'), findsOneWidget);
  });

  testWidgets('knowledge base creation dialog can be opened and cancelled', (tester) async {
    await tester.pumpWidget(const KnowFlowApp());
    await tester.tap(find.byIcon(Icons.library_books_outlined));
    await tester.pump();

    await tester.tap(find.text('创建知识库并导入示例'));
    await tester.pump();
    expect(find.text('新建知识库'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('创建'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(find.text('新建知识库'), findsNothing);
  });
}
