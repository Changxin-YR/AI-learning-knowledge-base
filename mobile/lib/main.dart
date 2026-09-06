import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

const apiBaseUrl = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8001');

class ApiClient {
  ApiClient({this.baseUrl = apiBaseUrl});
  final String baseUrl;
  String? token;

  Future<dynamic> _request(String method, String path, {Object? body}) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
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
  Future<Map<String, dynamic>> createKnowledgeBase(String name) async =>
      Map<String, dynamic>.from(await _request(
          'POST', '/api/v1/knowledge-bases',
          body: {'name': name}));
  Future<Map<String, dynamic>> uploadSample(String id) async {
    final client = HttpClient();
    try {
      final request = await client
          .postUrl(Uri.parse('$baseUrl/api/v1/knowledge-bases/$id/documents'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final boundary = 'knowflow-${DateTime.now().millisecondsSinceEpoch}';
      request.headers.contentType = ContentType('multipart', 'form-data',
          parameters: {'boundary': boundary});
      final bytes = utf8.encode(
          '--$boundary\r\ncontent-disposition: form-data; name="file"; filename="knowflow-notes.md"\r\ncontent-type: text/markdown\r\n\r\n# KnowFlow 学习笔记\nRAG 通过检索知识库片段增强生成，citation 用于追溯来源。\r\n--$boundary--\r\n');
      request.add(bytes);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) throw Exception(text);
      return Map<String, dynamic>.from(jsonDecode(text));
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> chat(String message, String? kb) async =>
      Map<String, dynamic>.from(await _request('POST', '/api/v1/chat',
          body: {'message': message, 'knowledge_base_id': kb}));
  Future<Map<String, dynamic>> stats() async =>
      Map<String, dynamic>.from(await _request('GET', '/api/v1/stats'));
  Future<Map<String, dynamic>> plan(String goal) async =>
      Map<String, dynamic>.from(await _request('POST', '/api/v1/learning/plans',
          body: {'goal': goal, 'days': 7}));
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
  int index = 0;
  bool busy = false;
  String? error;
  List<Map<String, dynamic>> kbs = [];
  Map<String, dynamic> stats = {};
  final messages = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _login();
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
      final values = await Future.wait([api.knowledgeBases(), api.stats()]);
      if (mounted) {
        setState(() {
          kbs = (values[0] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          stats = Map<String, dynamic>.from(values[1] as Map);
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
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, controller.text),
                      child: const Text('创建'))
                ]));
    if (name == null || name.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final kb = await api.createKnowledgeBase(name.trim());
      await api.uploadSample(kb['id'] as String);
      await _refresh();
    } catch (e) {
      setState(() => error = '创建失败');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _ask(String message) async {
    if (message.trim().isEmpty) return;
    setState(() {
      busy = true;
      messages.add({'role': 'user', 'content': message});
    });
    try {
      final result = await api.chat(
          message, kbs.isEmpty ? null : kbs.first['id'] as String);
      if (mounted) {
        setState(() => messages.add({
              'role': 'assistant',
              'content': result['content'],
              'citations': result['citations']
            }));
      }
    } catch (_) {
      if (mounted) setState(() => error = '问答失败，请重试');
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
              child: _metric('今日学习', '${stats['learning_minutes'] ?? 0} 分钟',
                  Icons.timer_outlined)),
          Expanded(
              child: _metric('连续学习', '${stats['streak_days'] ?? 0} 天',
                  Icons.local_fire_department_outlined)),
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
    final input = TextEditingController();
    return Column(children: [
      _header('AI 学习助手', '基于你的资料回答，并保留可追溯来源'),
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
                    controller: input,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        hintText: '输入问题…', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            IconButton.filled(
                onPressed: busy
                    ? null
                    : () {
                        final text = input.text;
                        input.clear();
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
            trailing: const Icon(Icons.chevron_right))))
      ]);
  Widget _learning() => ListView(children: [
        _header('学习计划', '让 Agent 把目标拆成今天的下一步'),
        _card(FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final plan = await api.plan('掌握 RAG 基础');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content:
                                Text('已创建 ${plan['tasks'].length} 个学习任务')));
                      }
                    } catch (_) {
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            icon: const Icon(Icons.auto_awesome),
            label: const Text('生成 7 天学习计划'))),
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
        ]))
      ]);
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
                    error = '已退出，点击刷新重新登录';
                  }))
        ]))
      ]);
}

void main() => runApp(const KnowFlowApp());
