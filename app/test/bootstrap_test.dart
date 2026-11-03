import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyun_vpn/app_config.dart';
import 'package:koyun_vpn/services/bootstrap.dart';

/// 引导配置：Python 工具生成的文件，App 能验签解密；被篡改 / 伪造的文件必须拒绝。
/// 需要测试密钥（编译参数），平时自动跳过：
///   BOOT_TEST_DIR=<目录> flutter test test/bootstrap_test.dart --dart-define=KOYUN_BOOT_PUB=.. --dart-define=KOYUN_BOOT_KEY=..
void main() {
  final dir = Platform.environment['BOOT_TEST_DIR'];
  final skip = dir == null || AppConfig.bootPub.isEmpty;
  test('正常文件：验签解密成功', skip: skip, () async {
    final cfg = await Bootstrap.open(File('$dir/boot.json').readAsStringSync());
    expect(cfg, isNotNull);
    expect(cfg!['api'], ['https://api-new.example.com', 'https://api-bak.example.net/']);
    expect(cfg['web'], 'https://www.example.org');
    expect((cfg['latest'] as Map)['version'], '9.9.9');
    expect(cfg['ts'], isA<int>());
  });
  test('被篡改的文件：拒绝', skip: skip, () async {
    expect(await Bootstrap.open(File('$dir/bad.json').readAsStringSync()), isNull);
  });
  test('别人私钥签名的伪造文件：拒绝', skip: skip, () async {
    expect(await Bootstrap.open(File('$dir/fake.json').readAsStringSync()), isNull);
  });
  test('乱码：拒绝', skip: skip, () async {
    expect(await Bootstrap.open('<html>blocked</html>'), isNull);
  });
}
