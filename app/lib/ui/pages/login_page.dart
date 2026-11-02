import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/xboard_api.dart';
import '../../services/session.dart';
import '../theme.dart';
import '../util.dart';
import 'forgot_page.dart';
import 'import_page.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.message});

  /// 进入登录页时要提示的信息（如"登录已过期"）
  final String? message;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pwd = TextEditingController();
  bool _hide = true;
  bool _loading = false;
  int _failCount = 0;

  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    _email.text = s.storage.lastEmail ?? '';
    if (widget.message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => toast(context, widget.message!));
    }
  }

  Future<void> _login() async {
    final t = context.t;
    final email = _email.text.trim();
    if (!email.contains('@')) return toast(context, t.invalidEmail);
    if (_pwd.text.isEmpty) return toast(context, t.passwordHint);
    setState(() => _loading = true);
    try {
      await context.read<Session>().login(email, _pwd.text);
    } on ApiError catch (e) {
      _failCount++;
      if (!mounted) return;
      if (e.isNetwork) {
        await _offerImport(t.networkErrorTitle, t.networkErrorBody);
      } else if (_failCount >= 2) {
        await _offerImport(t.loginFailed, '${e.message}\n\n${t.loginFailedImportHint}');
      } else {
        toast(context, e.message);
      }
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 登录失败时引导切换到本地导入订阅模式
  Future<void> _offerImport(String title, String body) async {
    final t = context.t;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.retry)),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.switchToImport),
          ),
        ],
      ),
    );
    if (go == true && mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: KPage(
              maxWidth: 380,
              child: AutofillGroup(
                child: Column(
                  children: [
                    const KLogo(size: 52),
                    const SizedBox(height: 28),
                    Text(t.welcomeBack,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                    const SizedBox(height: 10),
                    Text(t.loginSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: KColors.sub, fontSize: 14)),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email, AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: t.emailHint,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 16, right: 8),
                          child: Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _pwd,
                      obscureText: _hide,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        hintText: t.passwordHint,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 16, right: 8),
                          child: Icon(Icons.lock_outline_rounded),
                        ),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: IconButton(
                            icon: Icon(_hide
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _hide = !_hide),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ForgotPage(email: _email.text))),
                        child: Text(t.forgotPassword),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FilledButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(t.loginButton),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 20),
                            ]),
                    ),
                    const SizedBox(height: 26),
                    _OrDivider(text: t.newUser),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const RegisterPage())),
                      child: Text(t.createAccount),
                    ),
                    const SizedBox(height: 18),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const ImportPage())),
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: Text(t.importSubscription),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(text, style: const TextStyle(color: KColors.sub, fontSize: 13)),
        ),
        const Expanded(child: Divider()),
      ]);
}
