import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/xboard_api.dart';
import '../../services/session.dart';
import '../theme.dart';
import '../util.dart';
import 'register_page.dart';

class ForgotPage extends StatefulWidget {
  const ForgotPage({super.key, this.email = ''});
  final String email;
  @override
  State<ForgotPage> createState() => _ForgotPageState();
}

class _ForgotPageState extends State<ForgotPage> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _pwd = TextEditingController();
  bool _loading = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_email.text.contains('@')) return toast(context, context.t.invalidEmail);
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (tm) {
      if (!mounted) return tm.cancel();
      setState(() => _countdown--);
      if (_countdown <= 0) tm.cancel();
    });
    try {
      await context.read<Session>().api.sendEmailCode(_email.text.trim());
      if (mounted) toast(context, context.t.codeSent);
    } on ApiError catch (e) {
      _timer?.cancel();
      if (mounted) {
        setState(() => _countdown = 0);
        toast(context, e.message);
      }
    }
  }

  Future<void> _submit() async {
    final t = context.t;
    if (_pwd.text.length < 8) return toast(context, t.passwordTooShort);
    setState(() => _loading = true);
    try {
      await context
          .read<Session>()
          .api
          .resetPassword(_email.text.trim(), _code.text.trim(), _pwd.text);
      if (!mounted) return;
      toast(context, t.passwordResetDone);
      Navigator.pop(context);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        await showWebRegisterDialog(context, t.networkErrorTitle);
      } else {
        toast(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Widget pre(IconData i) =>
        Padding(padding: const EdgeInsets.only(left: 16, right: 8), child: Icon(i));
    return Scaffold(
      appBar: AppBar(title: Text(t.forgotPassword)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 20, bottom: 32),
        child: KPage(
          maxWidth: 460,
          child: Column(children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(hintText: t.emailHint, prefixIcon: pre(Icons.mail_outline_rounded)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: t.emailCodeHint,
                prefixIcon: pre(Icons.verified_user_outlined),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: TextButton(
                    onPressed: _countdown > 0 ? null : _sendCode,
                    child: Text(_countdown > 0 ? '${_countdown}s' : t.sendCode,
                        style: const TextStyle(color: KColors.lavender, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pwd,
              obscureText: true,
              decoration: InputDecoration(hintText: t.newPasswordHint, prefixIcon: pre(Icons.lock_outline_rounded)),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(t.resetPassword),
            ),
          ]),
        ),
      ),
    );
  }
}
