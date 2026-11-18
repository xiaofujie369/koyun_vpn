@extends('admin.layout')
@section('title', '实时在线')
@push('head')
@if(!request('pause'))<meta http-equiv="refresh" content="30">@endif
@endpush
@section('content')
<h1>实时在线 <span class="muted" style="font-size:14px;font-weight:400">{{ now()->format('H:i:s') }} 更新 · @if(request('pause'))<a href="{{ request()->fullUrlWithQuery(['pause'=>null]) }}">恢复自动刷新</a>@else 每 30 秒自动刷新 · <a href="{{ request()->fullUrlWithQuery(['pause'=>1]) }}">暂停</a>@endif</span></h1>
<p class="desc">
  <span class="tag t-ok">在线</span> 1.1.8 起 App 连接中每 5 分钟发心跳，{{ \App\Services\ConnState::HEARTBEAT_FRESH_MIN }} 分钟内收到过就是真实在线。
  <span class="tag t-warn">推测</span> 旧版没有心跳，只能看最后一次连接事件；App 被直接关掉、没来得及上报断开时会一直显示，{{ \App\Services\ConnState::LEGACY_MAX_HOURS }} 小时后不再显示。
</p>

<div class="grid g4">
  <div class="card stat"><div class="k">正在连接</div><div class="v">{{ $summary['total'] }}</div><div class="s">心跳确认 {{ $summary['confirmed'] }} · 推测 {{ $summary['total'] - $summary['confirmed'] }}</div></div>
  <div class="card stat"><div class="k">TUN / 系统代理</div><div class="v">{{ $summary['tun'] }} <span class="muted">/</span> {{ $summary['total'] - $summary['tun'] }}</div><div class="s">TUN 接管全部流量</div></div>
  <div class="card stat"><div class="k">平台</div><div class="v" style="font-size:15px;line-height:1.7">@forelse($summary['platforms'] as $k=>$c)<a href="{{ request()->fullUrlWithQuery(['platform'=>$k,'page'=>null]) }}">{{ $k }}</a> {{ $c }}&nbsp; @empty — @endforelse</div></div>
  <div class="card stat"><div class="k">版本</div><div class="v" style="font-size:15px;line-height:1.7">@forelse($summary['versions'] as $k=>$c)v{{ $k }} {{ $c }}&nbsp; @empty — @endforelse</div></div>
</div>

<div class="grid g2" style="margin-top:14px">
<div class="card"><h2>按节点（前 12）</h2>
  @php($nt = max(1, $summary['nodes']->max() ?? 1))
  @forelse($summary['nodes'] as $k => $c)
    <div class="row" style="margin-bottom:6px"><div style="width:220px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis" title="{{ $k }}"><a href="{{ request()->fullUrlWithQuery(['node'=>$k,'page'=>null]) }}">{{ $k }}</a></div><div class="bar" style="flex:1"><i style="width:{{ round($c*100/$nt) }}%"></i></div><div class="right" style="width:40px">{{ $c }}</div></div>
  @empty <p class="muted">现在没有设备在连接</p> @endforelse
</div>
<div class="card"><h2>筛选</h2>
  <form class="filters" style="margin:0">
    <select name="platform"><option value="">全部平台</option>@foreach($summary['platforms'] as $k=>$c)<option @selected(request('platform')===$k)>{{ $k }}</option>@endforeach</select>
    <input name="node" value="{{ request('node') }}" placeholder="节点名（完整）">
    <label><input type="checkbox" name="legacy" value="0" @checked(request('legacy')==='0')> 只看心跳确认</label>
    <label><input type="checkbox" name="test" value="1" @checked(request('test'))> 包含测试机</label>
    <button class="btn light">筛选</button>
    @if(request()->hasAny(['platform','node','legacy','test']))<a href="{{ route('admin.online') }}">清除</a>@endif
  </form>
</div>
</div>

<div class="card" style="margin-top:14px;padding:0">
<table>
  <tr><th>状态</th><th>设备</th><th>平台 / 版本</th><th>节点</th><th>方式</th><th>已连接</th><th>网速（心跳时）</th><th>最后联系</th><th>IP</th></tr>
  @forelse($devices as $d)
  <tr>
    <td>@if($d->online_confirmed)<span class="tag t-ok">在线</span>@else<span class="tag t-warn" title="旧版没有心跳，根据最后一次连接事件推测">推测</span>@endif</td>
    <td class="mono"><a href="{{ route('admin.devices.show', $d) }}">{{ substr($d->id,0,8) }}</a>@if($d->is_test) <span class="tag">测试机</span>@endif</td>
    <td>{{ $d->platform }} · v{{ $d->app_version }}</td>
    <td>{{ $d->conn_node ?: '—' }}</td>
    <td>{{ $d->conn_tun === null ? '—' : ($d->conn_tun ? 'TUN' : '系统代理') }}@if($d->conn_route) · {{ ['rule'=>'分流','global'=>'全局','direct'=>'直连'][$d->conn_route] ?? $d->conn_route }}@endif</td>
    <td>{{ $d->conn_since ? $d->conn_since->diffForHumans(null, true) : '—' }}</td>
    <td class="mono">@if($d->online_confirmed)↓{{ \App\Services\Fmt::speed($d->hb_down) }} ↑{{ \App\Services\Fmt::speed($d->hb_up) }}@else<span class="muted">—</span>@endif</td>
    <td class="muted">{{ ($d->heartbeat_at ?? $d->last_seen_at)?->diffForHumans() }}</td>
    <td class="mono muted">{{ $d->last_ip }}</td>
  </tr>
  @empty <tr><td colspan="9" class="muted">现在没有设备在连接</td></tr> @endforelse
</table>
</div>
@include('admin._pager', ['p' => $devices])
@endsection
