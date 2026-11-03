@extends('admin.layout')
@section('title', '设备')
@section('content')
<h1>设备</h1>
<p class="desc">每台装了 Koyun 的电脑 / 手机一个匿名编号（和账号无关）。</p>
<form class="filters">
  <input name="q" value="{{ request('q') }}" placeholder="设备编号开头 / IP">
  <select name="platform"><option value="">全部平台</option>@foreach($platforms as $p)<option @selected(request('platform')===$p)>{{ $p }}</option>@endforeach</select>
  <select name="version"><option value="">全部版本</option>@foreach($versions as $v)<option @selected(request('version')===$v)>{{ $v }}</option>@endforeach</select>
  <button class="btn light">筛选</button>
</form>
<div class="card" style="padding:0">
<table>
  <tr><th>设备编号</th><th>平台</th><th>版本</th><th>系统</th><th>语言</th><th>最近 IP</th><th>首次</th><th>最近</th><th class="right">事件数</th></tr>
  @forelse($devices as $d)
  <tr><td class="mono"><a href="{{ route('admin.devices.show', $d) }}">{{ substr($d->id,0,12) }}…</a></td>
    <td>{{ $d->platform }}</td><td>v{{ $d->app_version }}</td><td class="muted" title="{{ $d->os_version }}">{{ \Illuminate\Support\Str::limit($d->os_version, 28) }}</td>
    <td>{{ $d->locale }}</td><td class="mono">{{ $d->last_ip }}</td>
    <td class="muted">{{ $d->first_seen_at?->format('m-d H:i') }}</td><td>{{ $d->last_seen_at?->diffForHumans() }}</td><td class="right">{{ $d->events_count }}</td></tr>
  @empty <tr><td colspan="9" class="muted">暂无设备</td></tr> @endforelse
</table>
</div>
@include('admin._pager', ['p' => $devices])
@endsection
