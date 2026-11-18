@extends('admin.layout')
@section('title', '设备详情')
@section('content')
<h1>设备 <span class="mono" style="font-size:15px">{{ $device->id }}</span></h1>
<p class="desc"><a href="{{ route('admin.devices') }}">← 返回设备列表</a></p>
<div class="card">
  <table>
    <tr><th style="width:120px">平台 / 系统</th><td>{{ $device->platform }} · {{ $device->os_version }}</td></tr>
    <tr><th>App / 内核</th><td>v{{ $device->app_version }} · sing-box {{ $device->core_version }}</td></tr>
    <tr><th>语言</th><td>{{ $device->locale }}</td></tr>
    <tr><th>IP</th><td class="mono">首次 {{ $device->first_ip }} · 最近 {{ $device->last_ip }}</td></tr>
    <tr><th>时间</th><td>首次 {{ $device->first_seen_at }} · 最近 {{ $device->last_seen_at }}</td></tr>
    <tr><th>当前连接</th><td>@include('admin._conn_tag', ['d' => $device])
      @if($device->conn_node) {{ $device->conn_node }}@endif
      @if($device->conn_state === 'connected' && $device->conn_since) · 已连接 {{ $device->conn_since->diffForHumans(null, true) }}@endif
      @if($device->heartbeat_at) · 最后心跳 {{ $device->heartbeat_at->diffForHumans() }}@endif</td></tr>
    <tr><th>测试机</th><td>
      <form method="post" action="{{ route('admin.devices.test', $device) }}" style="display:inline">@csrf
        {{ $device->is_test ? '是（统计中不计入）' : '否' }} <button class="btn light" style="margin-left:8px">{{ $device->is_test ? '取消测试机标记' : '标记为测试机' }}</button>
      </form>
    </td></tr>
  </table>
</div>
@if($feedback->count())
<div class="card" style="margin-top:14px"><h2>这台设备的反馈</h2>
  <table>@foreach($feedback as $f)
    <tr><td class="muted" style="width:110px">{{ $f->created_at->format('m-d H:i') }}</td><td><a href="{{ route('admin.feedback.show',$f) }}">{{ \Illuminate\Support\Str::limit($f->content, 80) }}</a></td><td style="width:80px"><span class="tag">{{ \App\Models\Feedback::STATUS[$f->status] }}</span></td></tr>
  @endforeach</table></div>
@endif
<div class="card" style="margin-top:14px;padding:0">
  <div style="padding:14px 18px 0"><h2>事件</h2></div>
  <table><tr><th>时间</th><th>类型</th><th>内容</th><th>IP</th></tr>
    @forelse($events as $e) @include('admin._event_row', ['e'=>$e, 'hideDevice'=>true]) @empty <tr><td colspan="4" class="muted">暂无</td></tr> @endforelse
  </table>
</div>
@include('admin._pager', ['p' => $events])
@endsection
