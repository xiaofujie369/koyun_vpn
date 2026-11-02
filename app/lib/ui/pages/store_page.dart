import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/xboard_api.dart';
import '../../services/session.dart';
import '../theme.dart';
import '../util.dart';

const _periods = [
  'month_price', 'quarter_price', 'half_year_price', 'year_price',
  'two_year_price', 'three_year_price', 'onetime_price', 'reset_price',
];

String periodLabel(BuildContext context, String p) {
  final t = context.t;
  return switch (p) {
    'month_price' => t.periodMonth,
    'quarter_price' => t.periodQuarter,
    'half_year_price' => t.periodHalfYear,
    'year_price' => t.periodYear,
    'two_year_price' => t.periodTwoYear,
    'three_year_price' => t.periodThreeYear,
    'onetime_price' => t.periodOnetime,
    'reset_price' => t.periodReset,
    _ => p,
  };
}

class StorePage extends StatefulWidget {
  const StorePage({super.key});
  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  List<Map<String, dynamic>>? _plans;
  String? _error;
  int _filter = 0; // 0 全部 1 周期 2 一次性

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await context.read<Session>().api.plans();
      if (mounted) setState(() => _plans = p.where((e) => e['sell'] != false).toList());
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  static bool _isOnetime(Map p) =>
      p['onetime_price'] != null &&
      _periods.take(6).every((k) => p[k] == null);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final plans = (_plans ?? []).where((p) => switch (_filter) {
          1 => !_isOnetime(p),
          2 => _isOnetime(p),
          _ => true,
        }).toList();
    return RefreshIndicator(
      color: KColors.lavender,
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.only(top: wide ? 32 : 12, bottom: 28), children: [
        KPage(
          maxWidth: 980,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t.navStore, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(t.storeSubtitle, style: const TextStyle(color: KColors.sub)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: KColors.field, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                for (final (i, l) in [(0, t.filterAll), (1, t.filterPeriodic), (2, t.filterOnetime)])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _filter = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _filter == i ? KColors.ink : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text(l,
                            style: TextStyle(
                                color: _filter == i ? Colors.white : KColors.sub,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Center(child: Column(children: [
                Text(_error!, style: const TextStyle(color: KColors.danger)),
                TextButton(onPressed: _load, child: Text(t.retry)),
              ]))
            else if (_plans == null)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
            else if (plans.isEmpty)
              Center(child: Text(t.noPlans, style: const TextStyle(color: KColors.sub)))
            else
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: plans
                    .map((p) => SizedBox(
                          width: wide ? 300 : double.infinity,
                          child: _PlanCard(plan: p, onBuy: () => _buy(p)),
                        ))
                    .toList(),
              ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _buy(Map<String, dynamic> plan) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BuySheet(plan: plan),
    );
  }
}

String _money(num cents) => (cents / 100).toStringAsFixed(2);

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onBuy});
  final Map<String, dynamic> plan;
  final VoidCallback onBuy;
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prices = _periods.where((k) => plan[k] != null && k != 'reset_price').toList();
    final first = prices.isEmpty ? null : prices.first;
    final features = stripHtml((plan['content'] ?? '').toString())
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^[-*•✓✔\s]+'), '').trim())
        .where((l) => l.isNotEmpty)
        .take(6)
        .toList();
    final gb = (plan['transfer_enable'] as num?)?.toInt();
    return KCard(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const IconBox(Icons.diamond_rounded),
        const SizedBox(height: 16),
        Text((plan['name'] ?? '').toString(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        if (gb != null) ...[
          const SizedBox(height: 6),
          Text(t.planTraffic('$gb GB'), style: const TextStyle(color: KColors.sub)),
        ],
        const SizedBox(height: 14),
        if (first != null)
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('¥${_money(plan[first] as num)}',
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('/ ${periodLabel(context, first)}', style: const TextStyle(color: KColors.sub)),
            ),
          ]),
        const SizedBox(height: 12),
        for (final f in features)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle_rounded, size: 18, color: KColors.ok),
              const SizedBox(width: 8),
              Expanded(child: Text(f, style: const TextStyle(fontSize: 13, height: 1.4))),
            ]),
          ),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: onBuy, child: Text(t.subscribeNow)),
      ]),
    );
  }
}

class _BuySheet extends StatefulWidget {
  const _BuySheet({required this.plan});
  final Map<String, dynamic> plan;
  @override
  State<_BuySheet> createState() => _BuySheetState();
}

class _BuySheetState extends State<_BuySheet> {
  late final List<String> _avail =
      _periods.where((k) => widget.plan[k] != null).toList();
  late String? _period = _avail.isEmpty ? null : _avail.first;
  List<Map<String, dynamic>> _methods = [];
  int? _method;
  final _coupon = TextEditingController();
  bool _busy = false;
  String? _tradeNo;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    context.read<Session>().api.paymentMethods().then((m) {
      if (mounted) {
        setState(() {
          _methods = m;
          _method = m.isEmpty ? null : (m.first['id'] as num).toInt();
        });
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _pay() async {
    final api = context.read<Session>().api;
    final t = context.t;
    if (_period == null) return;
    setState(() => _busy = true);
    try {
      _tradeNo ??= await api.createOrder((widget.plan['id'] as num).toInt(), _period!,
          coupon: _coupon.text.trim());
      if (_method == null) throw ApiError(ApiErrorKind.server, t.noPaymentMethod);
      final (type, data) = await api.checkout(_tradeNo!, _method!);
      if (!mounted) return;
      if (type == -1 || data == true) {
        await _done();
        return;
      }
      await openUrl(context, data.toString());
      _startPolling();
    } on ApiError catch (e) {
      if (!mounted) return;
      if (RegExp(r'未付款|开通中|pending|unpaid', caseSensitive: false).hasMatch(e.message)) {
        await _offerCancelPending(e.message);
      } else {
        toast(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 有未支付订单时，帮客户一键取消旧订单
  Future<void> _offerCancelPending(String msg) async {
    final t = context.t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text('$msg\n\n${t.cancelPendingAsk}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.cancelPendingOrder),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = context.read<Session>().api;
    try {
      final orders = await api.orders();
      for (final o in orders.where((o) => o['status'] == 0)) {
        await api.cancelOrder(o['trade_no'].toString());
      }
      if (mounted) toast(context, t.pendingCancelled);
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  void _startPolling() {
    _poll?.cancel();
    var n = 0;
    _poll = Timer.periodic(const Duration(seconds: 4), (tm) async {
      if (++n > 150 || !mounted) return tm.cancel(); // 最多 10 分钟
      try {
        final st = await context.read<Session>().api.orderStatus(_tradeNo!);
        if (st == 1 || st == 3) {
          tm.cancel();
          await _done();
        } else if (st == 2) {
          tm.cancel();
          _tradeNo = null;
        }
      } catch (_) {}
    });
    setState(() {});
  }

  Future<void> _done() async {
    final s = context.read<Session>();
    final t = context.t;
    Navigator.pop(context);
    toast(context, t.paySuccess);
    await Future.delayed(const Duration(seconds: 2));
    await s.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final price = _period == null ? 0 : (widget.plan[_period] as num);
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text((widget.plan['name'] ?? '').toString(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Text(t.choosePeriod, style: const TextStyle(color: KColors.sub)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _avail)
              ChoiceChip(
                label: Text('${periodLabel(context, p)}  ¥${_money(widget.plan[p] as num)}'),
                selected: _period == p,
                onSelected: (_) => setState(() {
                  _period = p;
                  _tradeNo = null;
                }),
              ),
          ]),
          const SizedBox(height: 16),
          Text(t.paymentMethod, style: const TextStyle(color: KColors.sub)),
          const SizedBox(height: 8),
          if (_methods.isEmpty) const LinearProgressIndicator(minHeight: 2),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in _methods)
              ChoiceChip(
                label: Text(m['name'].toString()),
                selected: _method == (m['id'] as num).toInt(),
                onSelected: (_) => setState(() => _method = (m['id'] as num).toInt()),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _coupon,
            onChanged: (_) => _tradeNo = null,
            decoration: InputDecoration(hintText: t.couponHint, isDense: true),
          ),
          const SizedBox(height: 20),
          if (_poll?.isActive == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(child: Text(t.waitingPayment, style: const TextStyle(color: KColors.sub))),
              ]),
            ),
          FilledButton(
            onPressed: _busy ? null : _pay,
            child: _busy
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text('${t.payNow}  ¥${_money(price)}'),
          ),
        ]),
      ),
    );
  }
}
