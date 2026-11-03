@extends('admin.layout')
@section('title', '用户反馈')
@section('content')
<h1>用户反馈</h1>
<p class="desc">客户在 App「用户中心 → 反馈问题」提交的内容。</p>
<form class="filters">
  @foreach(['new'=>'待处理','doing'=>'处理中','done'=>'已处理','all'=>'全部'] as $k=>$v)
    <a class="btn {{ $status===$k?'':'light' }}" href="{{ route('admin.feedback', ['status'=>$k]) }}">{{ $v }} @if($k!=='all')({{ $counts[$k] ?? 0 }})@endif</a>
  @endforeach
  <input type="hidden" name="status" value="{{ $status }}">
  <input name="q" value="{{ request('q') }}" placeholder="搜索内容 / 邮箱 / 联系方式">
  <button class="btn light">搜索</button>
</form>
<div class="card" style="padding:0">
<table><tr><th style="width:110px">时间</th><th>内容</th><th>邮箱 / 联系方式</th><th>平台</th><th style="width:80px">状态</th></tr>
@forelse($items as $f)
  <tr><td class="muted">{{ $f->created_at->format('m-d H:i') }}</td>
    <td><a href="{{ route('admin.feedback.show', $f) }}">{{ \Illuminate\Support\Str::limit($f->content, 90) }}</a></td>
    <td>{{ $f->email }}@if($f->contact && $f->contact !== $f->email)<br><span class="muted">{{ $f->contact }}</span>@endif</td>
    <td>{{ $f->device['platform'] ?? '' }} v{{ $f->device['app_version'] ?? '' }}</td>
    <td><span class="tag {{ ['new'=>'t-bad','doing'=>'t-warn','done'=>'t-ok'][$f->status] }}">{{ \App\Models\Feedback::STATUS[$f->status] }}</span></td></tr>
@empty <tr><td colspan="5" class="muted">没有反馈</td></tr> @endforelse
</table>
</div>
@include('admin._pager', ['p' => $items])
@endsection
