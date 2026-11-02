import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import 'theme.dart';

extension L10nX on BuildContext {
  AppLocalizations get t => AppLocalizations.of(this);
}

String fmtBytes(num b, {int digits = 2}) {
  if (b < 0) b = 0;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : digits)} ${units[i]}';
}

String fmtSpeed(int bps) => '${fmtBytes(bps, digits: 1)}/s';

String fmtDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

String fmtDate(int unixSeconds) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 去掉公告里的 HTML / Markdown 标记，纯文本展示
String stripHtml(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

Future<void> openUrl(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
      .catchError((_) => false);
  if (!ok && context.mounted) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) toast(context, context.t.linkCopied);
  }
}

Color delayColor(int? d) {
  if (d == null || d == -2) return KColors.faint;
  if (d < 0) return KColors.danger;
  if (d < 300) return KColors.ok;
  if (d < 800) return KColors.warn;
  return KColors.danger;
}

/// Logo（圆角方形）
class KLogo extends StatelessWidget {
  const KLogo({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.26),
          border: Border.all(color: KColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset('assets/images/logo.jpg', fit: BoxFit.cover),
      );
}

/// 页面统一的居中最大宽度容器
class KPage extends StatelessWidget {
  const KPage({super.key, required this.child, this.maxWidth = 720, this.padding});
  final Widget child;
  final double maxWidth;
  final EdgeInsets? padding;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: padding ?? const EdgeInsets.symmetric(horizontal: 20),
            child: child,
          ),
        ),
      );
}

/// 页面标题行：标题 + 副标题 + 右侧操作
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: KSize.title, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: const TextStyle(color: KColors.sub, fontSize: KSize.small + 0.5)),
              ],
            ]),
          ),
          ...actions,
        ]),
      );
}

class KCard extends StatelessWidget {
  const KCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => Material(
        color: color ?? KColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KSize.radiusLg),
          side: const BorderSide(color: KColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: KColors.bg,
          child: Padding(padding: padding, child: child),
        ),
      );
}

class IconBox extends StatelessWidget {
  const IconBox(this.icon, {super.key, this.color = KColors.sub, this.size = 30, this.bg = KColors.field});
  final IconData icon;
  final Color color;
  final Color bg;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.28)),
        child: Icon(icon, color: color, size: size * 0.55),
      );
}

/// 小标签
class KTag extends StatelessWidget {
  const KTag(this.text, {super.key, this.color = KColors.sub, this.bg = KColors.field});
  final String text;
  final Color color, bg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
        child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      );
}

/// 分段选择器（Codex 风格：浅底 + 白色滑块）
class KSegmented<T> extends StatelessWidget {
  const KSegmented({super.key, required this.items, required this.value, required this.onChanged});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: KColors.field,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: KColors.border),
        ),
        child: Row(children: [
          for (final (v, label) in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(v),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == value ? KColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: v == value
                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1))]
                          : null,
                    ),
                    child: Text(label,
                        style: TextStyle(
                          fontSize: KSize.small + 0.5,
                          fontWeight: v == value ? FontWeight.w600 : FontWeight.w400,
                          color: v == value ? KColors.ink : KColors.sub,
                        )),
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// 卡片里的一行设置：图标 + 标题/说明 + 右侧控件
class KRow extends StatelessWidget {
  const KRow({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        hoverColor: KColors.bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(children: [
            Icon(icon, size: 17, color: KColors.sub),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: KSize.body)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(subtitle!, style: const TextStyle(fontSize: KSize.small, color: KColors.faint)),
                  ),
              ]),
            ),
            if (trailing != null) trailing! else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, size: 18, color: KColors.faint),
          ]),
        ),
      );
}

/// 一组带分隔线的行
class KGroup extends StatelessWidget {
  const KGroup({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title!, style: const TextStyle(fontSize: KSize.small, color: KColors.sub, fontWeight: FontWeight.w500)),
          ),
        KCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: 43),
              children[i],
            ],
          ]),
        ),
      ]);
}

/// 数据小卡片：标签 + 数值
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.sub});
  final String label, value;
  final String? sub;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => KCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 14, color: KColors.faint), const SizedBox(width: 5)],
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: KSize.small, color: KColors.sub))),
          ]),
          const SizedBox(height: 6),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
          if (sub != null)
            Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: KColors.faint)),
        ]),
      );
}

/// 按钮里的加载圈
class BtnSpinner extends StatelessWidget {
  const BtnSpinner({super.key, this.color = Colors.white});
  final Color color;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: color));
}

/// 国旗图片（assets/flags/xx.png，来源 flagcdn.com）。
/// Windows 自带字体显示不了国旗表情，所以所有平台统一用图片；没有对应图片时显示 🌐。
class CountryFlag extends StatelessWidget {
  const CountryFlag(this.code, {super.key, this.width = 22});
  final String? code;
  final double width;
  @override
  Widget build(BuildContext context) {
    final c = code?.toLowerCase();
    final h = width * 0.75;
    Widget fallback() => SizedBox(
          width: width,
          height: h,
          child: Center(child: Text('🌐', style: TextStyle(fontSize: h * 0.9, height: 1))),
        );
    if (c == null || c.length != 2) return fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 0.6),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Image.asset('assets/flags/$c.png',
            width: width, height: h, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback()),
      ),
    );
  }
}
