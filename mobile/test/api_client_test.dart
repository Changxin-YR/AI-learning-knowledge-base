import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow_ai/main.dart';

void main() {
  test('API requests fail with a timeout when the server does not respond',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await Future<void>.delayed(const Duration(seconds: 1));
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final client = ApiClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        timeout: const Duration(milliseconds: 100));

    await expectLater(client.stats(), throwsA(isA<TimeoutException>()));
  });
}
