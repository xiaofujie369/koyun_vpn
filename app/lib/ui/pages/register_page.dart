import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/xboard_api.dart';
import '../../app_config.dart';
import '../../services/session.dart';
import '../theme.dart';
import '../util.dart';

/// 注册失败 → 引导客户用浏览器打开网页注册（需求 1）
Future<void> showWebRegisterDialog(BuildContext context, String reason) {
  final t = context.t;
  return showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(t.registerFailed),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reason.isNotEmpty) ...[
            Text(reason, style: const TextStyle(color: KColors.danger)),
            const SizedBox(height: 14),
          ],
          Text(t.webRegisterHint),
          const SizedBox(height: 12),
          SelectableText(AppConfig.webRegisterUrl,
              style: const TextStyle(fontWeight: FontWeight.w700, color: KColors.lavender)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: AppConfig.webRegisterUrl));
            if (c.mounted) {
              Navigator.pop(c);
              toast(context, t.linkCopied);
            }
          },
          child: Text(t.copyLink),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () {
            Navigator.pop(c);
            openUrl(context, AppConfig.webRegisterUrl);
          },
          child: Text(t.openBrowser),
        ),
      ],
    ),
  );
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _user = TextEditingController();
  final _pwd = TextEditingController();
  final _pwd2 = TextEditingController();
  final _code = TextEditingController();
  final _invite = TextEditingController();
  bool _hide = true;
  bool _loading = false;
  bool _configLoading = true;
  List<String> _suffixes = [];
  String? _suffix;
  bool _emailVerify = true;
  bool _inviteForce = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final cfg = await context.read<Session>().loadGuestConfig();
    if (!mounted) return;
    if (cfg == null) {
      setState(() => _configLoading = false);
      return;
    }
    // 面板开启了人机验证（App 内无法完成）→ 直接引导网页注册
    if ((cfg['is_captcha'] ?? 0) == 1) {
      setState(() => _configLoading = false);
      await showWebRegisterDialog(context, context.t.captchaNeedWeb);
      return;
    }
    final list = cfg['email_whitelist_suffix'];
    setState(() {
      _configLoading = false;
      _emailVerify = (cfg['is_email_verify'] ?? 0) == 1;
      _inviteForce = (cfg['is_invite_force'] ?? 0) == 1;
      if (list is List && list.isNotEmpty) {
        _suffixes = list.map((e) => e.toString()).toList();
        _suffix = _suffixes.contains('gmail.com') ? 'gmail.com' : _suffixes.first;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _email {
    final u = _user.text.trim();
    if (_suffix == null || u.contains('@')) return u;
    return '$u@$_suffix';
  }

  String? _validate({bool forCode = false}) {
    final t = context.t;
    final email = _email;
    final at = email.indexOf('@');
    if (at <= 0 || !email.substring(at).contains('.')) return t.invalidEmail;
    if (_suffixes.isNotEmpty && !_suffixes.contains(email.substring(at + 1).toLowerCase())) {
      return t.emailSuffixNotAllowed;
    }
    // Gmail 限制：面板不接受带 "." 或 "+" 的 Gmail 别名
    if (email.toLowerCase().endsWith('@gmail.com') &&
        RegExp(r'[.+]').hasMatch(email.substring(0, at))) {
      return t.gmailAliasNotAllowed;
    }
    if (forCode) return null;
    if (_pwd.text.length < 8) return t.passwordTooShort;
    if (_pwd.text != _pwd2.text) return t.passwordMismatch;
    if (_emailVerify && _code.text.trim().isEmpty) return t.emailCodeHint;
    if (_inviteForce && _invite.text.trim().isEmpty) return t.inviteRequired;
    return null;
  }

  Future<void> _sendCode() async {
    final err = _validate(forCode: true);
    if (err != null) return toast(context, err);
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (tm) {
      if (!mounted) return tm.cancel();
      setState(() => _countdown--);
      if (_countdown <= 0) tm.cancel();
    });
    try {
      await context.read<Session>().api.sendEmailCode(_email);
      if (mounted) toast(context, context.t.codeSent);
    } on ApiError catch (e) {
      _timer?.cancel();
      if (!mounted) return;
      setState(() => _countdown = 0);
      if (e.isNetwork) {
        await showWebRegisterDialog(context, context.t.networkErrorTitle);
      } else {
        toast(context, e.message);
      }
    }
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) return toast(context, err);
    setState(() => _loading = true);
    try {
      await context.read<Session>().register(
            email: _email,
            password: _pwd.text,
            emailCode: _code.text.trim(),
            inviteCode: _invite.text.trim(),
          );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiError catch (e) {
      if (!mounted) return;
      // 验证码错误这类客户自己能改的错误，直接提示；其它失败引导网页注册
      final fixable = RegExp(r'验证码|code|密码|password|邀请|invite', caseSensitive: false)
          .hasMatch(e.message);
      if (fixable && !e.isNetwork) {
        toast(context, e.message);
      } else {
        await showWebRegisterDialog(context, e.isNetwork ? context.t.networkErrorTitle : e.message);
      }
    } catch (e) {
      if (mounted) await showWebRegisterDialog(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _prefix(IconData i) => Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Icon(i),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: KPage(
              maxWidth: 460,
              child: Column(children: [
                const KLogo(size: 52),
                const SizedBox(height: 22),
                Text(t.registerTitle,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(t.registerSubtitle, style: const TextStyle(color: KColors.sub)),
                const SizedBox(height: 30),
                if (_configLoading) const LinearProgressIndicator(minHeight: 2),
                TextField(
                  controller: _user,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: _suffixes.isEmpty ? t.emailHint : t.emailUserHint,
                    prefixIcon: _prefix(Icons.mail_outline_rounded),
                    suffixIcon: _suffixes.isEmpty
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _suffix,
                                borderRadius: BorderRadius.circular(16),
                                dropdownColor: KColors.surface,
                                style: const TextStyle(
                                    fontFamily: kFont,
                                    color: KColors.ink,
                                    fontWeight: FontWeight.w500),
                                items: _suffixes
                                    .map((s) => DropdownMenuItem(value: s, child: Text('@$s')))
                                    .toList(),
                                onChanged: (v) => setState(() => _suffix = v),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pwd,
                  obscureText: _hide,
                  decoration: InputDecoration(
                    hintText: t.passwordMin8,
                    prefixIcon: _prefix(Icons.lock_outline_rounded),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pwd2,
                  obscureText: _hide,
                  decoration: InputDecoration(
                    hintText: t.passwordAgain,
                    prefixIcon: _prefix(Icons.lock_outline_rounded),
                  ),
                ),
                if (_emailVerify) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: t.emailCodeHint,
                      prefixIcon: _prefix(Icons.verified_user_outlined),
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: TextButton(
                          onPressed: _countdown > 0 ? null : _sendCode,
                          child: Text(_countdown > 0 ? '${_countdown}s' : t.sendCode,
                              style: const TextStyle(
                                  color: KColors.lavender, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _invite,
                  decoration: InputDecoration(
                    hintText: _inviteForce ? t.inviteCodeRequired : t.inviteCodeOptional,
                    prefixIcon: _prefix(Icons.card_giftcard_rounded),
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(t.registerButton),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 20),
                        ]),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: () => showWebRegisterDialog(context, ''),
                  child: Text(t.registerOnWeb),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t.backToLogin),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
