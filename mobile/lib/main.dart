import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const apiBaseUrl = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8001');
const appVersion = '1.1.0';

/// Kept at module scope so the 我的 tab can switch the theme without threading
/// a callback through the whole widget tree.
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Very small Markdown cleanup for answer bubbles. The deterministic demo
/// answer is a raw knowledge-base chunk, so heading markers and list bullets
/// used to leak into the UI verbatim.
String plainText(String raw) {
  var text = raw.replaceAll('\r\n', '\n');
  text = text.replaceAll(RegExp(r'^#{1,6}[ \t]*', multiLine: true), '');
  text = text.replaceAll(RegExp(r'^[ \t]*[-*+][ \t]+', multiLine: true), '• ');
  text = text.replaceAll('**', '').replaceAll('`', '');
  return text.trim();
}

/// The backend stores raw status codes; the UI used to show them untranslated
/// next to already-localised labels.
String localizedStatus(String? status) {
  switch (status) {
    case 'indexed':
      return '已索引';
    case 'processing':
      return '处理中';
    case 'pending':
      return '待处理';
    case 'failed':
      return '处理失败';
    default:
      return status ?? '未知';
  }
}

class ApiClient {
  ApiClient({
    this.baseUrl = apiBaseUrl,
    this.timeout = const Duration(seconds: 20),
    this.chatTimeout = const Duration(seconds: 75),
    this.uploadTimeout = const Duration(seconds: 180),
  });
  final String baseUrl;
  final Duration timeout;
  final Duration chatTimeout;
  final Duration uploadTimeout;
  String? token;

  Future<dynamic> _request(String method, String path,
      {Object? body, Duration? requestTimeout}) async {
    final limit = requestTimeout ?? timeout;
    final client = HttpClient();
    client.connectionTimeout = limit;
    client.idleTimeout = limit;
    try {
      final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(limit);
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
    client.connectionTimeout = uploadTimeout;
    client.idleTimeout = uploadTimeout;
    try {
      final request = await client
          .postUrl(Uri.parse('$baseUrl/api/v1/knowledge-bases/$id/documents'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final boundary = 'knowflow-${DateTime.now().millisecondsSinceEpoch}';
      request.headers.contentType = ContentType('multipart', 'form-data',
          parameters: {'boundary': boundary});
      request.write('--$boundary\r\n');
      request.write(
          'content-disposition: form-data; name="file"; filename="$filename"\r\n');
      request.write('content-type: application/octet-stream\r\n\r\n');
      request.add(payload);
      request.write('\r\n--$boundary--\r\n');
      final response = await request.close().timeout(uploadTimeout);
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
      Map<String, dynamic>.from(await _request('POST', '/api/v1/chat',
          requestTimeout: chatTimeout,
          body: {
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

  /// Sample documents generated in Dart. They are deliberately NOT shipped as
  /// packaged fixtures any more: they are only offered when the platform picker
  /// is genuinely unavailable and the user explicitly opts in from the UI.
  static final List<PickedDocument> samples = [
    PickedDocument(
        name: 'KnowFlow 示例笔记.md',
        bytes: utf8.encode('# KnowFlow 示例笔记\n'
            '\n'
            'RAG 通过检索知识库片段增强生成，citation 用于追溯来源。\n'
            '\n'
            '- 检索：先从资料里找到相关片段\n'
            '- 生成：模型只依据这些片段作答\n')),
    PickedDocument(
        name: 'RAG 速览.txt',
        bytes: utf8.encode('检索增强生成（RAG）= 检索 + 生成。\n'
            '\n'
            '先检索相关资料，再让模型基于资料作答并给出引用，避免凭空编造。\n')),
  ];

  Future<PickedDocument?> pick() async =>
      _decode(await _channel.invokeMethod<dynamic>('pickDocument'));

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
  bool pickerUnavailable = false;
  String? uploadStatus;

  Future<void> _upload() async {
    if (uploading) return;
    setState(() {
      uploading = true;
      pickerUnavailable = false;
      uploadStatus = '选择中…';
    });
    PickedDocument? picked;
    try {
      picked = await DocumentPicker().pick();
    } catch (_) {
      // Fail loudly, but also offer an explicit opt-in sample document so the
      // user is never stuck with a dead upload button.
      if (!mounted) return;
      setState(() {
        uploading = false;
        pickerUnavailable = true;
        uploadStatus = '系统文件选择器不可用，可改用示例文档';
      });
      return;
    }
    if (picked == null) {
      if (mounted) {
        setState(() {
          uploading = false;
          uploadStatus = null;
        });
      }
      return;
    }
    await _send(picked);
  }

  Future<void> _pickSample() async {
    if (uploading) return;
    final index = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('选择示例文档'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < DocumentPicker.samples.length; i++)
                        ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(DocumentPicker.samples[i].name),
                          onTap: () => Navigator.pop(dialogContext, i),
                        )
                    ]),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消'))
              ],
            ));
    if (index == null || !mounted) return;
    setState(() {
      uploading = true;
      uploadStatus = '上传中…';
    });
    await _send(DocumentPicker.samples[index]);
  }

  Future<void> _send(PickedDocument picked) async {
    try {
      if (widget.onUpload == null) {
        throw StateError('Document upload is unavailable');
      }
      final uploaded = await widget.onUpload!(picked.name, picked.bytes);
      if (mounted) {
        setState(() {
          documents.add(Map<String, dynamic>.from(uploaded));
          uploadStatus = '已索引';
          uploading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          uploadStatus = '上传失败，请重试';
          uploading = false;
        });
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> document) async {
    final id = document['id'] as String;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('删除文档'),
              content: Text('确定删除《${document['filename']}》吗？此操作不可撤销。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('删除'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => deletingId = id);
    try {
      await widget.onDelete(id);
      if (mounted) {
        setState(() {
          documents.removeWhere((item) => item['id'] == id);
          deletingId = null;
          uploadStatus = '已删除文档';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          deletingId = null;
          uploadStatus = '删除失败，请重试';
        });
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
                                leading: const Icon(Icons.description_outlined),
                                title: Text(document['filename'] as String),
                                subtitle:
                                    Text(localizedStatus(document['status'] as String?)),
                                trailing: IconButton(
                                    tooltip: '删除文档',
                                    onPressed: deletingId == null && !uploading
                                        ? () => _delete(document)
                                        : null,
                                    icon: const Icon(Icons.delete_outline)),
                              ))
                          .toList()))
          ]),
        ),
        actions: [
          if (pickerUnavailable)
            TextButton(
                onPressed: uploading ? null : _pickSample,
                child: const Text('使用示例文档')),
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
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, mode, _) => MaterialApp(
          title: 'KnowFlow AI',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
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
        ),
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
  final learningScroll = ScrollController();
  int index = 0;
  bool busy = false;
  bool loggedOut = false;
  String? error;
  String? conversationId;
  String? lastQuestion;
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
    learningScroll.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    try {
      final result = await api.demoLogin();
      api.token = result['access_token'] as String;
      await _refresh();
      if (mounted) setState(() => loggedOut = false);
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
      if (mounted) setState(() => error = '后端暂不可用，请检查网络后重试');
    }
  }

  void _logout() {
    setState(() {
      api.token = null;
      loggedOut = true;
      kbs = [];
      tasks = [];
      mastery = [];
      stats = {};
      messages.clear();
      conversationId = null;
      lastQuestion = null;
      selectedKbId = null;
      quizData = null;
      quizAnswer = null;
      error = null;
    });
  }

  Future<void> _createKb() async {
    final controller = TextEditingController(text: '我的学习库');
    final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('新建知识库'),
                content: TextField(controller: controller, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.pop(dialogContext);
                      },
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.pop(dialogContext, controller.text);
                      },
                      child: const Text('创建'))
                ]));
    // Dispose after the dialog's exit animation so the field never touches a
    // disposed controller.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => controller.dispose());
    if (name == null || name.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final kb = await api.createKnowledgeBase(name.trim());
      await api.uploadSample(kb['id'] as String);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => error = '知识库创建失败，请重试');
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
      // Pull the server state again after the dialog closes so the card count
      // is never stale.
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文档列表加载失败，请重试')));
      }
    }
  }

  Future<void> _ask(String message) async {
    final text = message.trim();
    if (text.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      lastQuestion = text;
      messages.add({'role': 'user', 'content': text});
    });
    try {
      final result = await api.chat(text, selectedKbId, conversationId);
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
      if (!mounted) return;
      setState(() {
        error = '问答失败：后端无响应或超时，请检查网络后重试';
        messages.add({
          'role': 'error',
          'content': '这条提问没有拿到回答。你可以直接重试。'
        });
      });
      // Give the question back so nothing the user typed is lost.
      if (aiController.text.isEmpty) aiController.text = text;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _createPlan() async {
    final controller = TextEditingController(text: '掌握 RAG 基础');
    final goal = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: const Text('生成学习计划'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '学习目标')),
                actions: [
                  TextButton(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.pop(dialogContext);
                      },
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.pop(dialogContext, controller.text);
                      },
                      child: const Text('生成'))
                ]));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => controller.dispose());
    if (goal == null || goal.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final plan = await api.plan(goal.trim());
      await _refresh();
      if (mounted) {
        final created = (plan['created_count'] ?? plan['tasks'].length);
        final skipped = plan['skipped_count'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(skipped is int && skipped > 0
                ? '新增 $created 个任务，$skipped 个已存在（未重复添加）'
                : '已创建 $created 个学习任务')));
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
        // Bring the new quiz card fully into view so its submit button is
        // never left half-hidden below the fold.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!learningScroll.hasClients) return;
          learningScroll.animateTo(
            learningScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
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
    final questions = (quiz['questions'] as List?) ?? const [];
    if (questions.isEmpty) return;
    final question = Map<String, dynamic>.from(questions.first as Map);
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
            selectedIndex: loggedOut ? 4 : index,
            onDestinationSelected: (value) {
              setState(() => index = value);
              if (loggedOut && value != 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请先在“我的”页重新登录')));
              }
            },
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

  /// Rendered on every tab that can trigger a request, not just 首页.
  Widget _errorCard() => error == null
      ? const SizedBox.shrink()
      : _card(Row(children: [
          const Icon(Icons.cloud_off_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text(error!)),
          IconButton(
              tooltip: '重试',
              onPressed: _login,
              icon: const Icon(Icons.refresh))
        ]));

  Widget _dashboard() => RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _header('KnowFlow AI', '把知识变成今天能完成的行动'),
            _errorCard(),
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
            _card(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                  child: Text(
                      '已索引 ${stats['documents'] ?? 0} 份文档，掌握度会随着测验实时更新。')),
              IconButton(
                  tooltip: '新建知识库',
                  onPressed: _createKb,
                  icon: const Icon(Icons.add))
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
      if (error != null) _errorCard(),
      Expanded(
          child: messages.isEmpty
              // Scrollable so the empty state cannot be squeezed away in
              // landscape / small windows.
              ? LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: constraints.maxHeight),
                          child: Center(
                              child: _card(const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Icon(Icons.auto_awesome, size: 42),
                                SizedBox(height: 12),
                                Text('从一个问题开始，例如：RAG 为什么需要 citation？')
                              ]))))))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final item = messages[i];
                    final role = item['role'];
                    final mine = role == 'user';
                    final failed = role == 'error';
                    final citations = (item['citations'] is List)
                        ? List<dynamic>.from(item['citations'] as List)
                        : const <dynamic>[];
                    // The backend can return several chunks from documents that
                    // share a filename; joining them raw produced
                    // "rag_notes.md、rag_notes.md、rag_notes.md".
                    final sources = <String>[];
                    for (final citation in citations) {
                      if (citation is Map && citation['filename'] is String) {
                        final name = citation['filename'] as String;
                        if (!sources.contains(name)) sources.add(name);
                      }
                    }
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
                                    : failed
                                        ? Theme.of(context)
                                            .colorScheme
                                            .errorContainer
                                        : Theme.of(context)
                                            .colorScheme
                                            .surface,
                                borderRadius: BorderRadius.circular(16)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(plainText('${item['content']}')),
                                  if (sources.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text('来源：${sources.join('、')}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary))),
                                  if (failed && lastQuestion != null)
                                    Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                            onPressed: busy
                                                ? null
                                                : () => _ask(lastQuestion!),
                                            icon: const Icon(Icons.refresh, size: 16),
                                            label: const Text('重试')))
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
                        hintText: '输入问题…',
                        border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            IconButton.filled(
                tooltip: '发送',
                onPressed: busy
                    ? null
                    : () {
                        final text = aiController.text;
                        if (text.trim().isEmpty) return;
                        aiController.clear();
                        _ask(text);
                      },
                icon: const Icon(Icons.arrow_upward))
          ]))
    ]);
  }

  Widget _knowledge() => RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _header('知识库', '上传资料，建立自己的可检索上下文'),
            _errorCard(),
            _card(FilledButton.icon(
                onPressed: busy ? null : _createKb,
                icon: const Icon(Icons.add),
                label: Text(busy ? '处理中…' : '创建知识库并导入示例'))),
            ...kbs.map((kb) => _card(ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.folder_outlined)),
                title: Text(kb['name'] as String),
                subtitle:
                    Text('${kb['document_count'] ?? 0} 份文档 · 已索引'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : () => _openKb(kb))))
          ]));

  Widget _learning() => RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          controller: learningScroll,
          // Bottom padding keeps the last control clear of the navigation bar.
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _header('学习计划', '把目标拆成今天能完成的下一步'),
            _errorCard(),
            _card(FilledButton.icon(
                onPressed: busy ? null : _createPlan,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('生成 7 天学习计划'))),
            _card(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            _card(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('学习数据', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text('测验正确率 ${stats['quiz_accuracy'] ?? 0}%'),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value:
                      (((stats['quiz_accuracy'] ?? 0) as num) / 100).clamp(0.0, 1.0).toDouble()),
              const SizedBox(height: 12),
              Text(
                  '任务完成 ${stats['tasks_completed'] ?? 0} / ${stats['tasks_total'] ?? 0}'
                  '（完成率 ${stats['task_completion_rate'] ?? 0}%）')
            ])),
            _quizCard(),
            if (mastery.isNotEmpty)
              _card(
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('知识掌握度', style: Theme.of(context).textTheme.titleMedium),
                ...mastery.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['knowledge'] as String),
                    trailing: Text('${item['score']}%')))
              ]))
          ]));

  Widget _quizCard() {
    final quiz = quizData;
    if (quiz == null) {
      return _card(FilledButton.icon(
          onPressed: busy ? null : _startQuiz,
          icon: const Icon(Icons.quiz_outlined),
          label: const Text('开始一次测验')));
    }
    final questions = (quiz['questions'] as List?) ?? const [];
    if (questions.isEmpty) {
      return _card(const Text('这次测验没有可用题目，请稍后再试。'));
    }
    final question = Map<String, dynamic>.from(questions.first as Map);
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

  Future<void> _pickTheme() async {
    final selected = await showDialog<ThemeMode>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
                title: const Text('主题'),
                children: ThemeMode.values
                    .map((mode) => RadioListTile<ThemeMode>(
                          value: mode,
                          groupValue: themeModeNotifier.value,
                          title: Text(switch (mode) {
                            ThemeMode.system => '跟随系统',
                            ThemeMode.light => '浅色',
                            ThemeMode.dark => '深色',
                          }),
                          onChanged: (value) =>
                              Navigator.pop(dialogContext, value),
                        ))
                    .toList()));
    if (selected != null) themeModeNotifier.value = selected;
  }

  void _showInfo(String title, String body) {
    showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(title),
                content: Text(body),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('关闭'))
                ]));
  }

  Widget _profile() {
    if (loggedOut) {
      return ListView(children: [
        _header('我的', 'KnowFlow AI · 学习者空间'),
        _errorCard(),
        _card(Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline, size: 42),
          const SizedBox(height: 12),
          const Text('已退出登录'),
          const SizedBox(height: 4),
          const Text('登录后即可继续查看知识库与学习进度。',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: busy ? null : _login,
              icon: const Icon(Icons.login),
              label: const Text('使用演示账号登录'))
        ]))
      ]);
    }
    return ListView(children: [
      _header('我的', 'KnowFlow AI · 学习者空间'),
      _errorCard(),
      _card(const ListTile(
          leading: CircleAvatar(child: Icon(Icons.person)),
          title: Text('Demo 学习者'),
          subtitle: Text('demo@knowflow.local'))),
      _card(Column(children: [
        ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('主题'),
            trailing: Text(switch (themeModeNotifier.value) {
              ThemeMode.system => '跟随系统',
              ThemeMode.light => '浅色',
              ThemeMode.dark => '深色',
            }),
            onTap: _pickTheme),
        ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('隐私与安全'),
            onTap: () => _showInfo('隐私与安全',
                '演示环境说明：\n\n'
                '· 账号仅使用内置演示账号，不收集个人信息；\n'
                '· 你上传的资料与提问只发送到本机配置的后端地址，不会发送到第三方分析服务；\n'
                '· 应用不包含广告、追踪或埋点 SDK。')),
        ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于 KnowFlow AI'),
            onTap: () => _showInfo('关于 KnowFlow AI',
                'KnowFlow AI $appVersion\n\n把资料变成可检索、可追溯的学习上下文。')),
        ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('退出登录'),
            onTap: _logout)
      ]))
    ]);
  }
}

void main() => runApp(const KnowFlowApp());
