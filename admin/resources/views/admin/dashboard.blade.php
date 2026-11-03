@extends('admin.layout')
@section('title', '仪表盘')
@section('content')
<h1>仪表盘</h1>
<p class="desc">数据每 2 分钟更新一次（本次 {{ $generated_at }}）。活跃 = 当天有任何上报的设备。</p>

<div class="grid g4">
  <div class="card stat"><div class="k">今日活跃设备</div><div class="v">{{ $active_today }}</div><div class="s">近 7 天 {{ $active_7d }}</div></div>
  <div class="card stat"><div class="k">设备总数</div><div class="v">{{ $devices_total }}</div><div class="s">今日新增 {{ $new_today }}</div></div>
  <div class="card stat"><div class="k">今日连接成功率</div>
    <div class="v" style="color:{{ $conn_rate === null ? 'inherit' : ($conn_rate >= 90 ? 'var(--ok)' : ($conn_rate >= 70 ? 'var(--warn)' : 'var(--bad)')) }}">{{ $conn_rate === null ? '—' : $conn_rate.'%' }}</div>
    <div class="s">成功 {{ $conn_ok }} · 失败 {{ $conn_fail }}</div></div>
  <div class="card stat"><div class="k">待处理反馈 / 今日崩溃</div><div class="v"><a href="{{ route('admin.feedback') }}">{{ $feedback_new }}</a> <span class="muted">/</span> <a href="{{ route('admin.events',['type'=>'crash']) }}">{{ $crash_today }}</a></div><div class="s">点击数字查看</div></div>
</div>

<div class="card" style="margin-top:14px">
  <h2>近 14 天活跃 / 新增设备</h2>
  <canvas id="dau" height="70"></canvas>
</div>

<div class="grid g2" style="margin-top:14px">
  <div class="card"><h2>平台分布（近 30 天活跃）</h2>
    @php($pt = max(1, $platforms->sum()))
    @forelse($platforms as $k => $c)
      <div class="row" style="margin-bottom:8px"><div style="width:80px">{{ $k ?: '未知' }}</div><div class="bar" style="flex:1"><i style="width:{{ round($c*100/$pt) }}%"></i></div><div class="right" style="width:70px">{{ $c }}（{{ round($c*100/$pt) }}%）</div></div>
    @empty <p class="muted">暂无数据</p> @endforelse
  </div>
  <div class="card"><h2>App 版本分布（近 30 天活跃）</h2>
    @php($vt = max(1, $versions->sum()))
    @forelse($versions as $k => $c)
      <div class="row" style="margin-bottom:8px"><div style="width:80px">v{{ $k ?: '?' }}</div><div class="bar" style="flex:1"><i style="width:{{ round($c*100/$vt) }}%"></i></div><div class="right" style="width:70px">{{ $c }}（{{ round($c*100/$vt) }}%）</div></div>
    @empty <p class="muted">暂无数据</p> @endforelse
  </div>
</div>

<div class="card" style="margin-top:14px">
  <h2>节点连接情况（近 7 天，失败多的在前）</h2>
  <table>
    <tr><th>节点</th><th class="right">成功</th><th class="right">失败</th><th class="right">成功率</th><th class="right">平均连接耗时</th></tr>
    @forelse($nodes as $n)
      @php($t = $n->ok + $n->fail)
      @php($rate = $t ? round($n->ok*100/$t,1) : 0)
      <tr><td>{{ $n->node ?: '（未知）' }}</td><td class="right">{{ $n->ok }}</td><td class="right">{{ $n->fail }}</td>
        <td class="right"><span class="tag {{ $rate>=90?'t-ok':($rate>=70?'t-warn':'t-bad') }}">{{ $rate }}%</span></td>
        <td class="right">{{ $n->ms ? $n->ms.' ms' : '—' }}</td></tr>
    @empty <tr><td colspan="5" class="muted">暂无数据</td></tr> @endforelse
  </table>
</div>

<div class="card" style="margin-top:14px">
  <h2>连接失败原因排行（近 7 天）</h2>
  <table>
    <tr><th>原因</th><th class="right" style="width:80px">次数</th></tr>
    @forelse($fail_reasons as $e)
      <tr><td class="mono">{{ $e->e ?: '（空）' }}</td><td class="right">{{ $e->c }}</td></tr>
    @empty <tr><td colspan="2" class="muted">暂无失败记录</td></tr> @endforelse
  </table>
</div>
@endsection

@push('scripts')
<script src="{{ asset('js/chart.umd.min.js') }}"></script>
<script>
const days = @json($days);
new Chart(document.getElementById('dau'), {
  type: 'line',
  data: { labels: days.map(d => d.d), datasets: [
    { label: '活跃设备', data: days.map(d => d.active), borderColor: '#7c6bd6', backgroundColor: 'rgba(124,107,214,.12)', fill: true, tension: .3 },
    { label: '新增设备', data: days.map(d => d.new), borderColor: '#2f9e6b', tension: .3 },
  ]},
  options: { plugins: { legend: { position: 'bottom' } }, scales: { y: { beginAtZero: true, ticks: { precision: 0 } } } }
});
</script>
@endpush
