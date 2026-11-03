@extends('admin.layout')
@section('title', request('type')==='crash' ? '崩溃记录' : '事件日志')
@section('content')
<h1>{{ request('type')==='crash' ? '崩溃记录' : '事件日志' }}</h1>
<p class="desc">App 自动上报的启动、连接、断开、崩溃记录。保留 {{ config('koyun.retention_days') }} 天。</p>
<form class="filters">
  <select name="type"><option value="">全部类型</option>@foreach($types as $k=>$v)<option value="{{ $k }}" @selected(request('type')===$k)>{{ $v }}</option>@endforeach</select>
  <input name="device" value="{{ request('device') }}" placeholder="设备编号开头">
  <input type="date" name="date" value="{{ request('date') }}">
  <input name="q" value="{{ request('q') }}" placeholder="搜索内容（节点名、错误…）">
  <button class="btn light">筛选</button>
</form>
<div class="card" style="padding:0">
<table><tr><th>时间</th><th>设备</th><th>类型</th><th>内容</th><th>IP</th></tr>
  @forelse($events as $e) @include('admin._event_row', ['e'=>$e]) @empty <tr><td colspan="5" class="muted">暂无记录</td></tr> @endforelse
</table>
</div>
@include('admin._pager', ['p' => $events])
@endsection
