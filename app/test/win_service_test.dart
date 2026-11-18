// App 的服务客户端和 Go 服务（koyun-service）之间的协议测试。服务在 Linux 上以测试模式运行：
//   KOYUN_SERVICE=/path/koyun-service SINGBOX=/path/sing-box flutter test test/win_service_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyun_vpn/core/win_service.dart';

void main() {
  final svcBin = Platform.environment['KOYUN_SERVICE'];
  final sb = Platform.environment['SINGBOX'];
  final skip = svcBin == null || sb == null;
  late Process proc;
  late WinService svc;
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('koyun-svc');
    proc = await Process.start(svcBin!, ['serve', sb!, dir.path]);
    final line = await proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).first;
    final j = jsonDecode(line);
    svc = WinService.at(j['port'], j['token']);
  });

  tearDown(() async {
    proc.kill(ProcessSignal.sigkill);
    await proc.exitCode;
    dir.deleteSync(recursive: true);
  });

  test('启动、读日志、状态、停止', skip: skip, () async {
    final start = (await svc.logs(1 << 30)).$2;
    await svc.start(jsonEncode({
      'log': {'level': 'info'},
      'inbounds': [
        {'type': 'mixed', 'listen': '127.0.0.1', 'listen_port': 18741}
      ],
      'outbounds': [
        {'type': 'direct'}
      ],
    }));
    expect((await svc.status()).$1, isTrue);
    await Future.delayed(const Duration(milliseconds: 300));
    final (lines, next) = await svc.logs(start);
    expect(lines.any((l) => l.contains('started')), isTrue, reason: lines.join('\n'));
    expect(next, greaterThan(start));
    // 只取新日志
    expect((await svc.logs(next)).$1, isEmpty);
    await svc.stop();
    expect((await svc.status()).$1, isFalse);
  });

  test('内核启动失败：抛出内核的错误信息', skip: skip, () async {
    final cfg = jsonEncode({
      'inbounds': [
        {'type': 'mixed', 'tag': 'a', 'listen': '127.0.0.1', 'listen_port': 18742},
        {'type': 'mixed', 'tag': 'b', 'listen': '127.0.0.1', 'listen_port': 18742},
      ],
      'outbounds': [
        {'type': 'direct'}
      ],
    });
    await expectLater(svc.start(cfg), throwsA(isA<ServiceStartError>()));
  });

  test('令牌不对：拒绝', skip: skip, () async {
    final bad = WinService.at(svc.port, 'wrong');
    await expectLater(bad.status(), throwsA(isA<HttpException>()));
  });
}
