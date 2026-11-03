@extends('admin.layout')
@section('title', '反馈详情')
@section('content')
<h1>反馈 #{{ $f->id }}</h1>
<p class="desc"><a href="{{ route('admin.feedback') }}">← 返回反馈列表</a> · {{ $f->created_at }} · 设备 <a class="mono" href="{{ route('admin.devices.show', $f->device_id) }}">{{ substr($f->device_id,0,12) }}</a></p>
<div class="grid g2">
  <div class="card">
    <h2>问题描述</h2>
    <div style="white-space:pre-wrap">{{ $f->content }}</div>
    <hr style="border:0;border-top:1px solid var(--line);margin:14px 0">
    <table>
      <tr><th style="width:90px">账号邮箱</th><td>{{ $f->email ?: '—' }}</td></tr>
      <tr><th>联系方式</th><td>{{ $f->contact ?: '—' }}</td></tr>
      <tr><th>IP</th><td class="mono">{{ $f->ip }}</td></tr>
      <tr><th>设备</th><td>{{ $f->device['platform'] ?? '' }} · v{{ $f->device['app_version'] ?? '' }} · {{ $f->device['os_version'] ?? '' }}</td></tr>
    </table>
  </div>
  <div class="card">
    <h2>处理</h2>
    <form method="post" action="{{ route('admin.feedback.update', $f) }}">@csrf
      <div class="field"><label class="f">状态</label>
        <select name="status">@foreach(\App\Models\Feedback::STATUS as $k=>$v)<option value="{{ $k }}" @selected($f->status===$k)>{{ $v }}</option>@endforeach</select></div>
      <div class="field"><label class="f">备注（只有后台能看到）</label><textarea name="admin_note">{{ $f->admin_note }}</textarea></div>
      <button class="btn">保存</button>
    </form>
  </div>
</div>
@if($f->extra)
<div class="card" style="margin-top:14px"><h2>当时的状态</h2>
  @php($x = $f->extra)
  <table>
    <tr><th style="width:110px">系统</th><td>{{ $x['os'] ?? '' }}</td></tr>
    <tr><th>是否已连接</th><td>{{ !empty($x['connected']) ? '是' : '否' }} · 节点 {{ $x['node'] ?? '' }} · {{ !empty($x['tun']) ? 'TUN' : '系统代理' }} · {{ $x['route'] ?? '' }}</td></tr>
    <tr><th>套餐 / 节点数</th><td>{{ $x['plan'] ?? '—' }} · {{ $x['nodes_count'] ?? '?' }} 个节点</td></tr>
    @foreach(['local_ip'=>'本机网络','proxy_ip'=>'代理出口'] as $k=>$label)
      @if(!empty($x[$k]))<tr><th>{{ $label }}</th><td class="mono">{{ $x[$k]['ip'] ?? '' }} · {{ $x[$k]['country_code'] ?? '' }} {{ $x[$k]['city'] ?? '' }} · {{ $x[$k]['org'] ?? '' }} · 风险 {{ $x[$k]['fraud_score'] ?? '—' }}</td></tr>@endif
    @endforeach
  </table>
</div>
@endif
@if($f->logs)
<div class="card" style="margin-top:14px"><h2>运行日志</h2><pre>{{ $f->logs }}</pre></div>
@endif
@endsection
