import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyun_vpn/core/config_builder.dart';
import 'package:koyun_vpn/core/delay_probe.dart';
import 'package:koyun_vpn/models/node.dart';
import 'package:koyun_vpn/services/storage.dart';
import 'package:koyun_vpn/services/sub_parser.dart';

/// 结构与 Xboard flag=sing-box 真实输出一致（密码 / 地址为假数据）
const sampleSingBox = '''
{"dns":{},"outbounds":[
 {"tag":"节点选择","type":"selector","outbounds":["自动选择"]},
 {"tag":"direct","type":"direct"},
 {"tag":"自动选择","type":"urltest","outbounds":[]},
 {"type":"anytls","tag":"[anytls]剩余流量：79.07 GB","server":"1.2.3.4","password":"x","server_port":3088,"tls":{"enabled":true,"server_name":"a.example.com"}},
 {"type":"anytls","tag":"[anytls]套餐到期：2026-12-01","server":"1.2.3.4","password":"x","server_port":3088,"tls":{"enabled":true,"server_name":"a.example.com"}},
 {"type":"anytls","tag":"[anytls]🇭🇰香港D01-1X移动","server":"1.2.3.4","password":"pw","server_port":3088,"tls":{"enabled":true,"insecure":false,"server_name":"hk.example.com","ech":{"enabled":true,"config":["-----BEGIN ECH CONFIGS-----\\nAEb+DQBCbgAgACBNzX3ebOwqN0fFT4dTEI4Eu6znOwT6csG8Zjen2D+oDgAIAAEA\\nAQABAAMAD2VjaC5leGFtcGxlLmNvbQAA\\n-----END ECH CONFIGS-----"],"query_server_name":"hk.example.com"}}},
 {"server":"5.6.7.8","server_port":8443,"tag":"[Hy2]🇯🇵日本D13-1X","tls":{"enabled":true,"insecure":false,"server_name":"jp.example.com"},"up_mbps":100,"down_mbps":500,"type":"hysteria2","password":"pw","obfs":{"type":"salamander","password":"ob"}},
 {"type":"vless","tag":"[vless]🇹🇼台湾A04-1X直连","server":"9.9.9.9","server_port":12555,"uuid":"b831381d-6324-4d53-ad4f-8cda48b30811","packet_encoding":"xudp"},
 {"type":"vless","tag":"[vless]🇯🇵日本大版ISP-2X","server":"9.9.9.8","server_port":443,"uuid":"b831381d-6324-4d53-ad4f-8cda48b30811","flow":"xtls-rprx-vision","tls":{"enabled":true,"server_name":"www.apple.com","utls":{"enabled":true,"fingerprint":"chrome"},"reality":{"enabled":true,"public_key":"jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0","short_id":"0123abcd"}}},
 {"type":"vless","tag":"[vless]🇯🇵日本大版ISP-2X","server":"9.9.9.7","server_port":443,"uuid":"b831381d-6324-4d53-ad4f-8cda48b30811"}
]}
''';

const sampleLinks = '''
vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.1.1.1:443?encryption=none&security=reality&sni=www.apple.com&fp=chrome&pbk=jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0&sid=0123&flow=xtls-rprx-vision&type=tcp#%F0%9F%87%BA%F0%9F%87%B8US-Reality
vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.1.1.2:443?security=tls&sni=a.com&type=ws&path=%2Fws&host=a.com#WS
trojan://pass@1.1.1.3:443?sni=t.com&allowInsecure=1#Trojan
ss://YWVzLTI1Ni1nY206cGFzcw@1.1.1.4:8388#SS-SIP002
hysteria2://pw@1.1.1.5:443/?sni=h.com&obfs=salamander&obfs-password=x&insecure=1#Hy2
tuic://b831381d-6324-4d53-ad4f-8cda48b30811:pw@1.1.1.6:443?congestion_control=bbr&sni=tu.com&alpn=h3#TUIC
anytls://pw@1.1.1.7:443?sni=any.com#AnyTLS
vmess://eyJ2IjoiMiIsInBzIjoiVk1lc3MiLCJhZGQiOiIxLjEuMS44IiwicG9ydCI6IjQ0MyIsImlkIjoiYjgzMTM4MWQtNjMyNC00ZDUzLWFkNGYtOGNkYTQ4YjMwODExIiwiYWlkIjoiMCIsIm5ldCI6IndzIiwicGF0aCI6Ii92IiwiaG9zdCI6InYuY29tIiwidGxzIjoidGxzIn0=
''';

void main() {
  test('解析 Xboard sing-box 订阅：过滤提示节点、去重 tag', () {
    final nodes = SubParser.parse(sampleSingBox);
    expect(nodes.length, 5);
    expect(nodes.any((n) => n.tag.contains('剩余流量')), false);
    expect(nodes.map((n) => n.tag).toSet().length, nodes.length);
    expect(nodes.first.countryCode, 'HK');
    expect(nodes.first.plainName, '香港D01-1X移动');
    expect(nodes[1].type, 'hysteria2');
    expect(nodes.first.multiplier, '1x');
  });

  test('解析分享链接（明文与 Base64）', () {
    final plain = SubParser.parse(sampleLinks);
    expect(plain.map((n) => n.type).toList(),
        ['vless', 'vless', 'trojan', 'shadowsocks', 'hysteria2', 'tuic', 'anytls', 'vmess']);
    final b64 = SubParser.parse(base64.encode(utf8.encode(sampleLinks)));
    expect(b64.length, 8);
    final reality = plain.first.outbound;
    expect(reality['tls']['reality']['public_key'], isNotEmpty);
    expect(plain[3].outbound['method'], 'aes-256-gcm');
    expect(plain.last.outbound['transport']['type'], 'ws');
  });

  group('节点测速', () {
    final nodes = SubParser.parse(sampleSingBox);
    CoreOptions opts({bool tun = false, bool ipv6 = false, bool tester = false}) => CoreOptions(
          nodes: nodes,
          selected: 'auto',
          ruleSetDir: 'rules',
          workDir: 'work',
          clashPort: 19090,
          clashSecret: 's',
          tun: tun,
          ipv6: ipv6,
          testPort: 19290,
          testSecret: 'pw',
          testerOnly: tester,
        );

    test('节点域名的解析不受 IPv6 开关影响（只有 IPv6 地址的域名也能连）', () {
      for (final ipv6 in [false, true]) {
        final route = ConfigBuilder.build(opts(ipv6: ipv6))['route'] as Map;
        expect(route['default_domain_resolver']['strategy'], 'prefer_ipv4');
      }
    });

    test('只有 TUN 模式才绑定默认网卡', () {
      expect((ConfigBuilder.build(opts())['route'] as Map)['auto_detect_interface'], false);
      expect((ConfigBuilder.build(opts(tun: true))['route'] as Map)['auto_detect_interface'], true);
    });

    test('测速入口：每个节点一个用户，规则排在最前面', () {
      final cfg = ConfigBuilder.build(opts());
      final inbound = (cfg['inbounds'] as List).cast<Map>().firstWhere((i) => i['tag'] == 'test-in');
      expect(inbound['listen'], '127.0.0.1');
      expect((inbound['users'] as List).length, nodes.length + 1); // 多一个 App 自己用的账号
      final rules = (cfg['route'] as Map)['rules'] as List;
      expect(rules.first, {
        'inbound': ['test-in'],
        'auth_user': ['n0'],
        'outbound': nodes.first.tag,
      });
      expect(rules[nodes.length + 1], {'action': 'sniff'});
    });

    test('临时测速内核没有自动选择组', () {
      final cfg = ConfigBuilder.build(opts(tester: true));
      final outbounds = (cfg['outbounds'] as List).cast<Map>();
      expect(outbounds.any((o) => o['tag'] == 'auto'), false);
      expect(outbounds.first['outbounds'], isNot(contains('auto')));
      expect(outbounds.first['default'], nodes.first.tag);
    });

    /// 假的内核测速入口：回应 CONNECT 后，第一次 HEAD 很慢（模拟握手），第二次很快
    Future<(ServerSocket, List<String>)> fakeProxy({bool closeAfterFirst = false, String connect = '200 OK', String? dropHost}) async {
      final seen = <String>[];
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((c) {
        var heads = 0;
        c.listen((data) async {
          final text = latin1.decode(data);
          seen.add(text);
          if (text.startsWith('CONNECT')) {
            c.write('HTTP/1.1 $connect\r\n\r\n');
            return;
          }
          if (dropHost != null && text.contains('Host: $dropHost')) {
            await c.close(); // 模拟这个地址走不通：连接被断开
            return;
          }
          heads++;
          if (closeAfterFirst && heads > 1) return;
          if (heads == 1) await Future.delayed(const Duration(milliseconds: 300));
          c.write('HTTP/1.1 204 No Content\r\nServer: x\r\n\r\n');
          if (closeAfterFirst) await c.close();
        }, onError: (_) {});
      });
      return (server, seen);
    }

    DelayProbe probe(ServerSocket s, {void Function(String)? log}) =>
        DelayProbe(port: s.port, password: 'pw', users: {'a': 'n0'}, log: log);

    test('只计第二次请求的耗时，并带上节点对应的用户名', () async {
      final (s, seen) = await fakeProxy();
      final ms = await probe(s).measure('a');
      await s.close();
      expect(ms, inInclusiveRange(1, 200));
      expect(seen.first, contains('CONNECT cp.cloudflare.com:80'));
      expect(seen.first, contains('Proxy-Authorization: Basic ${base64.encode(utf8.encode('n0:pw'))}'));
    });

    test('连接不能复用时退回第一次的结果', () async {
      final (s, _) = await fakeProxy(closeAfterFirst: true);
      final ms = await probe(s).measure('a');
      await s.close();
      expect(ms, greaterThanOrEqualTo(290));
    });

    test('主测速地址走不通时换备用地址，并记录原因', () async {
      final (s, seen) = await fakeProxy(dropHost: 'cp.cloudflare.com');
      final logs = <String>[];
      final ms = await probe(s, log: logs.add).measure('a');
      await s.close();
      expect(ms, inInclusiveRange(1, 200));
      expect(seen.any((t) => t.contains('CONNECT www.gstatic.com:80')), true);
      expect(logs.first, contains('cp.cloudflare.com 失败'));
      expect(logs.last, contains('www.gstatic.com 成功'));
    });

    test('入口拒绝、未知节点、超时都返回 -1', () async {
      final (s, _) = await fakeProxy(connect: '407 Proxy Authentication Required');
      expect(await probe(s).measure('a'), -1);
      expect(await probe(s).measure('不存在'), -1);
      await s.close();

      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      silent.listen((_) {});
      expect(await probe(silent).measure('a', timeout: const Duration(milliseconds: 100)), -1);
      await silent.close();
    });
  });

  test('生成配置并写出供内核校验', () {
    final nodes = <ProxyNode>[...SubParser.parse(sampleSingBox), ...SubParser.parse(sampleLinks)];
    for (final tun in [false, true]) {
      final cfg = ConfigBuilder.build(CoreOptions(
        nodes: nodes,
        selected: nodes[2].tag,
        ruleSetDir: '${Directory.current.absolute.path}/assets/rules',
        workDir: Directory.systemTemp.path,
        clashPort: 19090,
        clashSecret: 'secret',
        tun: tun,
        mixedPort: 17890,
        routeMode: RouteMode.rule,
        ipv6: tun,
        testPort: 19290,
        testSecret: 'pw',
      ));
      final out = File('build/test-config-${tun ? 'tun' : 'proxy'}.json');
      out.createSync(recursive: true);
      out.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(cfg));
      final outbounds = cfg['outbounds'] as List;
      expect((outbounds.first as Map)['default'], nodes[2].tag);
    }
  });
}
