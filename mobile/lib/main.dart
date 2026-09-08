import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const apiBaseUrl = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8001');

class ApiClient {
  ApiClient({
    this.baseUrl = apiBaseUrl,
    this.timeout = const Duration(seconds: 8),
  });
  final String baseUrl;
  final Duration timeout;
  String? token;

  Future<dynamic> _request(String method, String path, {Object? body}) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    client.idleTimeout = timeout;
    try {
      final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) throw Exception(text);
      return text.isEmpty ? null : jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> demoLogin() async =>
      Map<String, dynamic>.from(await _request('POST', '/api/v1/auth/demo'));
  Future<List<dynamic>> knowledgeBases() async =>
      List<dynamic>.from(await _request('GET', '/api/v1/knowledge-bases'));
  Future<List<dynamic>> documents(String kbId) async => List<dynamic>.from(
      await _request('GET', '/api/v1/knowledge-bases/$kbId/documents'));
  Future<void> deleteDocument(String id) async {
    await _request('DELETE', '/api/v1/documents/$id');
  }

  Future<Map<String, dynamic>> createKnowledgeBase(String name) async =>
      Map<String, dynamic>.from(await _request(
          'POST', '/api/v1/knowledge-bases',
          body: {'name': name}));
  Future<Map<String, dynamic>> uploadDocument(
      String id, String filename, List<int> payload) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    client.idleTimeout = timeout;
    try {
      final request = await client
          .postUrl(Uri.parse('$baseUrl/api/v1/knowledge-bases/$id/documents'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final boundary = 'knowflow-${DateTime.now().millisecondsSinceEpoch}';
      request.headers.contentType = ContentType('multipart', 'form-data',
          parameters: {'boundary': boundary});
      request.write('--$boundary\r\n');
      request.write('content-disposition: form-data; name="file"; filename="$filename"\r\n');
      request.write('content-type: application/octet-stream\r\n\r\n');
      request.add(payload);
      request.write('\r\n--$boundary--\r\n');
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) throw Exception(text);
      return Map<String, dynamic>.from(jsonDecode(text));
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> uploadSample(String id) async =>
      uploadDocument(
          id,
          'knowflow-notes.md',
          utf8.encode(
              '# KnowFlow 学习笔记\nRAG 通过检索知识库片段增强生成，citation 用于追溯来源。'));

  Future<Map<String, dynamic>> chat(
          String message, String? kb, String? conversationId) async =>
      Map<String, dynamic>.from(await _request('POST', '/api/v1/chat', body: {
        'message': message,
        'knowledge_base_id': kb,
        'conversation_id': conversationId
      }));
  Future<Map<String, dynamic>> stats() async =>
      Map<String, dynamic>.from(await _request('GET', '/api/v1/stats'));
  Future<Map<String, dynamic>> plan(String goal) async =>
      Map<String, dynamic>.from(await _request('POST', '/api/v1/learning/plans',
          body: {'goal': goal, 'days': 7}));
  Future<List<dynamic>> tasks() async =>
      List<dynamic>.from(await _request('GET', '/api/v1/learning/tasks'));
  Future<Map<String, dynamic>> updateTask(String id, bool completed) async =>
      Map<String, dynamic>.from(await _request(
          'PATCH', '/api/v1/learning/tasks/$id',
          body: {'completed': completed}));
  Future<List<dynamic>> mastery() async =>
      List<dynamic>.from(await _request('GET', '/api/v1/mastery'));
  Future<Map<String, dynamic>> quiz(String? kb) async =>
      Map<String, dynamic>.from(await _request('POST',
          '/api/v1/quizzes${kb == null ? '' : '?knowledge_base_id=$kb'}'));
  Future<Map<String, dynamic>> submitQuiz(
          String id, String questionId, String answer) async =>
      Map<String, dynamic>.from(
          await _request('POST', '/api/v1/quizzes/$id/submit', body: {
        'answers': {questionId: answer}
      }));
  Future<Map<String, dynamic>> repository(String url) async =>
      Map<String, dynamic>.from(await _request(
          'POST', '/api/v1/repositories/import',
          body: {'url': url}));
}

class PickedDocument {
  const PickedDocument({required this.name, required this.bytes});
  final String name;
  final List<int> bytes;
}

class DocumentPicker {
  static const _channel = MethodChannel('knowflow/file_picker');

  Future<PickedDocument?> pick(BuildContext context) async {
    if (Platform.operatingSystem == 'ohos') {
      return _pickCompatibility(context);
    }
    try {
      return _decode(await _channel.invokeMethod<dynamic>('pickDocument'));
    } on PlatformException catch (error) {
      if (error.code != 'picker_unavailable') rethrow;
      return _pickCompatibility(context);
    }
  }

  PickedDocument? _decode(dynamic result) {
    if (result == null) return null;
    final map = Map<Object?, Object?>.from(result as Map);
    final name = map['name'] as String?;
    final bytes = map['bytes'];
    if (name == null || bytes is! Uint8List) {
      throw const FormatException('Invalid document picker result');
    }
    return PickedDocument(name: name, bytes: bytes);
  }

  Future<PickedDocument?> _pickCompatibility(BuildContext context) async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listCompatDocuments');
    final files = (raw ?? [])
        .map((item) => Map<Object?, Object?>.from(item as Map))
        .map((item) => item['name'] as String)
        .toList();
    if (files.isEmpty) throw StateError('No compatibility documents available');
    if (!context.mounted) return null;
    final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('兼容模式选择文件'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                    shrinkWrap: true,
                    children: files
                        .map((file) => ListTile(
                              leading: const Icon(Icons.description_outlined),
                              title: Text(file),
                              onTap: () => Navigator.pop(dialogContext, file),
                            ))
                        .toList()),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消'))
              ],
            ));
    if (name == null) return null;
    return _decode(await _channel.invokeMethod<dynamic>(
        'readCompatDocument', {'name': name}));
  }
}

class KnowledgeBaseDetailDialog extends StatefulWidget {
  const KnowledgeBaseDetailDialog({
    super.key,
    required this.name,
    required this.documents,
    required this.onDelete,
    this.onUpload,
  });

  final String name;
  final List<Map<String, dynamic>> documents;
  final Future<void> Function(String id) onDelete;
  final Future<Map<String, dynamic>> Function(String filename, List<int> bytes)?
      onUpload;

  @override
  State<KnowledgeBaseDetailDialog> createState() =>
      _KnowledgeBaseDetailDialogState();
}

class _KnowledgeBaseDetailDialogState extends State<KnowledgeBaseDetailDialog> {
  late final List<Map<String, dynamic>> documents = [...widget.documents];
  String? deletingId;
  bool uploading = false;
  String? uploadStatus;

  Future<void> _upload() async {
    setState(() {
      uploading = true;
      uploadStatus = '选择中…';
    });
    try {
      final picked = await DocumentPicker().pick(context);
      if (picked == null) {
        if (mounted) setState(() => uploadStatus = null);
        return;
      }
      if (mounted) setState(() => uploadStatus = '上传中…');
      if (widget.onUpload == null) {
        throw StateError('Document upload is unavailable');
      }
      final uploaded = await widget.onUpload!(picked.name, picked.bytes);
      if (mounted) {
        setState(() {
          documents.add(Map<String, dynamic>.from(uploaded));
          uploadStatus = '已索引';
        });
      }
    } catch (_) {
      if (mounted) setState(() => uploadStatus = '上传失败，请重试');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _delete(String id) async {
    setState(() => deletingId = id);
    try {
      await widget.onDelete(id);
      if (mounted) {
        setState(() {
          documents.removeWhere((document) => document['id'] == id);
          deletingId = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => deletingId = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.name),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (uploadStatus != null)
              Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(uploadStatus!))),
            if (documents.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(12), child: Text('还没有文档'))
            else
              Flexible(
                  child: ListView(
                      shrinkWrap: true,
                      children: documents
                          .map((document) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading:
                                    const Icon(Icons.description_outlined),
                                title: Text(document['filename'] as String),
                                subtitle: Text(document['status'] as String),
                                trailing: IconButton(
                                    tooltip: '删除文档',
                                    onPressed: deletingId == null && !uploading
                                        ? () => _delete(document['id'] as String)
                                        : null,
                                    icon: const Icon(Icons.delete_outline)),
                              ))
                          .toList()))
          ]),
        ),
        actions: [
          FilledButton.icon(
              onPressed: uploading ? null : _upload,
              icon: const Icon(Icons.upload_file),
              label: Text(uploading ? '处理中…' : '上传文件')),
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭'))
        ],
      );
}

class KnowFlowApp extends StatelessWidget {
  const KnowFlowApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KnowFlow AI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff146c94),
                brightness: Brightness.light),
            scaffoldBackgroundColor: const Color(0xfff5f7f9)),
        darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff72c2db),
                brightness: Brightness.dark)),
        home: const HomeShell(),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final api = ApiClient();
  final aiController = TextEditingController();
  int index = 0;
  bool busy = false;
  String? error;
  String? conversationId;
  String? selectedKbId;
  List<Map<String, dynamic>> kbs = [];
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> mastery = [];
  Map<String, dynamic> stats = {};
  Map<String, dynamic>? quizData;
  String? quizAnswer;
  final messages = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _login();
  }

  @override
  void dispose() {
    aiController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    try {
      final result = await api.demoLogin();
      api.token = result['access_token'] as String;
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => error = '离线演示：请启动后端后点击重试');
    }
  }

  Future<void> _refresh() async {
    try {
      final values = await Future.wait(
          [api.knowledgeBases(), api.stats(), api.tasks(), api.mastery()]);
      if (mounted) {
        setState(() {
          final nextKbs = (values[0] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          kbs = nextKbs;
          if (selectedKbId != null &&
              !nextKbs.any((kb) => kb['id'] == selectedKbId)) {
            selectedKbId = null;
          }
          stats = Map<String, dynamic>.from(values[1] as Map);
          tasks = (values[2] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          mastery = (values[3] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '后端暂不可用');
    }
  }

  Future<void> _createKb() async {
    final controller = TextEditingController(text: '我的学习库');
    final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('新建知识库'),
                content: TextField(controller: controller, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.pop(context);
                      },
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.pop(context, controller.text);
                      },
                      child: const Text('创建'))
                ]));
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final kb = await api.createKnowledgeBase(name.trim());
      await api.uploadSample(kb['id'] as String);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => error = '创建失败');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _openKb(Map<String, dynamic> kb) async {
    try {
      final documents = await api.documents(kb['id'] as String);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (_) => KnowledgeBaseDetailDialog(
              name: kb['name'] as String,
              documents: documents
                  .map((document) => Map<String, dynamic>.from(document as Map))
                  .toList(),
              onUpload: (filename, bytes) async {
                final uploaded =
                    await api.uploadDocument(kb['id'] as String, filename, bytes);
                await _refresh();
                return uploaded;
              },
              onDelete: (id) async {
                await api.deleteDocument(id);
                await _refresh();
              }));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文档列表加载失败，请重试')));
      }
    }
  }

  Future<void> _ask(String message) async {
    if (message.trim().isEmpty) return;
    setState(() {
      busy = true;
      messages.add({'role': 'user', 'content': message});
    });
    try {
      final result = await api.chat(message, selectedKbId, conversationId);
      if (mounted) {
        setState(() {
          conversationId = result['conversation_id'] as String?;
          messages.add({
            'role': 'assistant',
            'content': result['content'],
            'citations': result['citations']
          });
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '问答失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _createPlan() async {
    setState(() => busy = true);
    try {
      final plan = await api.plan('掌握 RAG 基础');
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已创建 ${plan['tasks'].length} 个学习任务')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('学习计划创建失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _setTask(String id, bool completed) async {
    setState(() => busy = true);
    try {
      await api.updateTask(id, completed);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('任务更新失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _startQuiz() async {
    setState(() => busy = true);
    try {
      final result = await api.quiz(selectedKbId);
      if (mounted) {
        setState(() {
          quizData = result;
          quizAnswer = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('测验加载失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submitQuiz() async {
    final quiz = quizData;
    if (quiz == null || quizAnswer == null) return;
    final question =
        Map<String, dynamic>.from((quiz['questions'] as List).first as Map);
    setState(() => busy = true);
    try {
      final result = await api.submitQuiz(
          quiz['id'] as String, question['id'] as String, quizAnswer!);
      await _refresh();
      if (mounted) {
        setState(() {
          quizData = null;
          quizAnswer = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('本次得分 ${result['score']}%，掌握度已更新')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('测验提交失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_dashboard(), _ai(), _knowledge(), _learning(), _profile()];
    return Scaffold(
        body: SafeArea(child: pages[index]),
        bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (value) => setState(() => index = value),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: '首页'),
              NavigationDestination(
                  icon: Icon(Icons.auto_awesome_outlined),
                  selectedIcon: Icon(Icons.auto_awesome),
                  label: 'AI'),
              NavigationDestination(
                  icon: Icon(Icons.library_books_outlined),
                  selectedIcon: Icon(Icons.library_books),
                  label: '知识库'),
              NavigationDestination(
                  icon: Icon(Icons.school_outlined),
                  selectedIcon: Icon(Icons.school),
                  label: '学习'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: '我的')
            ]));
  }

  Widget _header(String title, String subtitle) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant))
      ]));
  Widget _card(Widget child) => Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      elevation: 0,
      child: Padding(padding: const EdgeInsets.all(18), child: child));
  Widget _dashboard() => RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(children: [
        _header('KnowFlow AI', '把知识变成今天能完成的行动'),
        if (error != null)
          _card(Row(children: [
            const Icon(Icons.cloud_off_outlined),
            const SizedBox(width: 8),
            Expanded(child: Text(error!)),
            IconButton(onPressed: _login, icon: const Icon(Icons.refresh))
          ])),
        _card(Row(children: [
          Expanded(
              child: _metric('知识库', '${stats['knowledge_bases'] ?? 0}',
                  Icons.library_books_outlined)),
          Expanded(
              child: _metric('文档', '${stats['documents'] ?? 0}',
                  Icons.description_outlined)),
          Expanded(
              child: _metric('完成率', '${stats['task_completion_rate'] ?? 0}%',
                  Icons.check_circle_outline))
        ])),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('今日建议', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('先用 15 分钟复习一个薄弱知识点，再完成一组测验。'),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: () => setState(() => index = 1),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('问问你的知识库'))
        ])),
        _card(Row(children: [
          const Icon(Icons.insights_outlined),
          const SizedBox(width: 12),
          Expanded(
              child: Text('已索引 ${stats['documents'] ?? 0} 份文档，掌握度会随着测验实时更新。')),
          IconButton(onPressed: _createKb, icon: const Icon(Icons.add))
        ]))
      ]));
  Widget _metric(String label, String value, IconData icon) =>
      Column(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(fontSize: 12))
      ]);
  Widget _ai() {
    return Column(children: [
      _header('AI 学习助手', '基于你的资料回答，并保留可追溯来源'),
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: DropdownButtonFormField<String>(
              value: selectedKbId ?? '',
              decoration: const InputDecoration(
                  labelText: '知识库', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String>(value: '', child: Text('全部知识库')),
                ...kbs.map((kb) => DropdownMenuItem<String>(
                    value: kb['id'] as String,
                    child: Text(kb['name'] as String)))
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() => selectedKbId =
                      value == null || value.isEmpty ? null : value))),
      Expanded(
          child: messages.isEmpty
              ? Center(
                  child: _card(
                      const Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, size: 42),
                  SizedBox(height: 12),
                  Text('从一个问题开始，例如：RAG 为什么需要 citation？')
                ])))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final item = messages[i];
                    final mine = item['role'] == 'user';
                    return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            constraints: const BoxConstraints(maxWidth: 340),
                            decoration: BoxDecoration(
                                color: mine
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(16)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item['content'] as String),
                                  if (item['citations'] is List &&
                                      (item['citations'] as List).isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                            '来源：${(item['citations'] as List).map((e) => e['filename']).join('、')}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary)))
                                ])));
                  })),
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(children: [
            Expanded(
                child: TextField(
                    controller: aiController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        hintText: '输入问题…', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            IconButton.filled(
                onPressed: busy
                    ? null
                    : () {
                        final text = aiController.text;
                        aiController.clear();
                        _ask(text);
                      },
                icon: const Icon(Icons.arrow_upward))
          ]))
    ]);
  }

  Widget _knowledge() => ListView(children: [
        _header('知识库', '上传资料，建立自己的可检索上下文'),
        _card(FilledButton.icon(
            onPressed: busy ? null : _createKb,
            icon: const Icon(Icons.add),
            label: Text(busy ? '处理中…' : '创建知识库并导入示例'))),
        ...kbs.map((kb) => _card(ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.folder_outlined)),
            title: Text(kb['name'] as String),
            subtitle: Text('${kb['document_count'] ?? 0} 份文档 · 已索引'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : () => _openKb(kb))))
      ]);
  Widget _learning() => ListView(children: [
        _header('学习计划', '把目标拆成今天能完成的下一步'),
        _card(FilledButton.icon(
            onPressed: busy ? null : _createPlan,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('生成 7 天学习计划'))),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('学习任务', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            const Text('还没有学习任务，先生成一份计划。')
          else
            ...tasks.map((task) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: task['completed'] == true,
                onChanged: busy
                    ? null
                    : (value) => _setTask(task['id'] as String, value == true),
                title: Text(task['title'] as String),
                subtitle: Text('截止 ${task['due_date']}')))
        ])),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('学习数据', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('测验正确率 ${stats['quiz_accuracy'] ?? 0}%'),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: ((stats['quiz_accuracy'] ?? 0) as num) / 100),
          const SizedBox(height: 12),
          Text(
              '完成任务 ${stats['tasks_completed'] ?? 0} / ${stats['tasks_total'] ?? 0}')
        ])),
        _quizCard(),
        if (mastery.isNotEmpty)
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('知识掌握度', style: Theme.of(context).textTheme.titleMedium),
            ...mastery.map((item) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item['knowledge'] as String),
                trailing: Text('${item['score']}%')))
          ]))
      ]);

  Widget _quizCard() {
    final quiz = quizData;
    if (quiz == null) {
      return _card(FilledButton.icon(
          onPressed: busy ? null : _startQuiz,
          icon: const Icon(Icons.quiz_outlined),
          label: const Text('开始一次测验')));
    }
    final question =
        Map<String, dynamic>.from((quiz['questions'] as List).first as Map);
    final options = List<String>.from(question['options'] as List);
    return _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('测验', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(question['prompt'] as String),
      ...options.map((option) => RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          value: option,
          groupValue: quizAnswer,
          onChanged:
              busy ? null : (value) => setState(() => quizAnswer = value),
          title: Text(option))),
      FilledButton(
          onPressed: busy || quizAnswer == null ? null : _submitQuiz,
          child: const Text('提交答案'))
    ]));
  }

  Widget _profile() => ListView(children: [
        _header('我的', 'KnowFlow AI · 学习者空间'),
        _card(const ListTile(
            leading: CircleAvatar(child: Icon(Icons.person)),
            title: Text('Demo 学习者'),
            subtitle: Text('demo@knowflow.local'))),
        _card(Column(children: [
          ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('主题'),
              trailing: const Text('跟随系统')),
          ListTile(
              leading: const Icon(Icons.security_outlined),
              title: const Text('隐私与安全')),
          ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于 KnowFlow AI')),
          ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('退出登录'),
              onTap: () => setState(() {
                    api.token = null;
                    kbs = [];
                    tasks = [];
                    mastery = [];
                    stats = {};
                    messages.clear();
                    conversationId = null;
                    selectedKbId = null;
                    error = '已退出，点击刷新重新登录';
                  }))
        ]))
      ]);
}

void main() => runApp(const KnowFlowApp());
