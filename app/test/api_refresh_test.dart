// 需要本地 Vikunja 和一个测试账号：
// VIKUNJA_TEST=1 VIKUNJA_TEST_USER=xxx VIKUNJA_TEST_PASS=xxx flutter test test/api_refresh_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_md/api/vikunja_api.dart';

void main() {
  final enabled = Platform.environment['VIKUNJA_TEST'] == '1';
  final user = Platform.environment['VIKUNJA_TEST_USER'] ?? '';
  final pass = Platform.environment['VIKUNJA_TEST_PASS'] ?? '';
  final server = Platform.environment['VIKUNJA_URL'] ?? 'http://localhost:3456';

  test('过期 token 自动续期，并发请求只续一次', () async {
    final api = VikunjaApi(server: server);
    var refreshes = 0;
    await api.login(user, pass);
    expect(api.refreshToken, isNotEmpty);
    api.onTokens = (_, _) => refreshes++;

    final firstRefresh = api.refreshToken;
    api.token = 'invalid.token.value';
    final users = await Future.wait([
      api.getUser(),
      api.getUser(),
      api.listProjects(),
      api.listLabels(),
    ]);
    expect(users.length, 4);
    expect(refreshes, 1);
    expect(api.refreshToken, isNot(firstRefresh));

    // 续期后再失效一次，新的 refresh token 依然可用
    api.token = 'invalid.token.value';
    expect((await api.getUser()).username, user);
    expect(refreshes, 2);
  }, skip: !enabled);
}
