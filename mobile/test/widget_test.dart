import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow_ai/main.dart';

void main() {
  testWidgets('renders KnowFlow navigation and dashboard', (tester) async {
    await tester.pumpWidget(const KnowFlowApp());
    expect(find.text('KnowFlow AI'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('知识库'), findsWidgets);
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('exposes knowledge-base selection and learning tasks',
      (tester) async {
    await tester.pumpWidget(const KnowFlowApp());

    await tester.tap(find.text('AI'));
    await tester.pump();
    expect(find.text('全部知识库'), findsOneWidget);

    await tester.tap(find.text('学习'));
    await tester.pump();
    expect(find.text('学习任务'), findsOneWidget);
  });

  testWidgets('knowledge-base detail lists and deletes documents',
      (tester) async {
    String? deleted;
    await tester.pumpWidget(MaterialApp(
        home: KnowledgeBaseDetailDialog(
            name: 'Study KB',
            documents: [
              {'id': 'doc-1', 'filename': 'notes.md', 'status': 'indexed'}
            ],
            onDelete: (id) async => deleted = id)));

    expect(find.text('notes.md'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(deleted, 'doc-1');
    expect(find.text('notes.md'), findsNothing);
  });

  testWidgets('uploaded document keeps the server document id',
      (tester) async {
    const channel = MethodChannel('knowflow/file_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => {
              'name': 'picked.txt',
              'bytes': Uint8List.fromList([104, 101, 108, 108, 111])
            });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    String? deleted;
    await tester.pumpWidget(MaterialApp(
        home: KnowledgeBaseDetailDialog(
            name: 'Study KB',
            documents: const [],
            onUpload: (filename, bytes) async => {
                  'id': 'server-doc-7',
                  'filename': filename,
                  'status': 'indexed'
                },
            onDelete: (id) async => deleted = id)));

    await tester.tap(find.text('上传文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(deleted, 'server-doc-7');
  });
}
