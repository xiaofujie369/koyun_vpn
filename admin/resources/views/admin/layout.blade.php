<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>@yield('title') · Koyun 后台</title>
<link rel="stylesheet" href="{{ asset('css/admin.css') }}?v=1">
</head>
<body>
<div class="wrap">
  <aside class="side">
    <div class="brand">Koyun 后台<small>客户端数据管理</small></div>
    @php($r = request()->route()?->getName() ?? '')
    @php($fbNew = \App\Models\Feedback::where('status','new')->count())
    <nav class="nav">
      <a href="{{ route('admin.dashboard') }}" class="{{ $r==='admin.dashboard'?'on':'' }}">仪表盘</a>
      <a href="{{ route('admin.feedback') }}" class="{{ str_starts_with($r,'admin.feedback')?'on':'' }}">用户反馈 @if($fbNew)<span class="badge">{{ $fbNew }}</span>@endif</a>
      <a href="{{ route('admin.devices') }}" class="{{ str_starts_with($r,'admin.devices')?'on':'' }}">设备</a>
      <a href="{{ route('admin.events') }}" class="{{ $r==='admin.events' && request('type')!=='crash' ?'on':'' }}">事件日志</a>
      <a href="{{ route('admin.events', ['type'=>'crash']) }}" class="{{ $r==='admin.events' && request('type')==='crash' ?'on':'' }}">崩溃记录</a>
      <a href="{{ route('admin.settings') }}" class="{{ $r==='admin.settings'?'on':'' }}">设置</a>
    </nav>
    <div class="bottom">
      {{ auth()->user()->email }}<br>
      <form method="post" action="{{ route('admin.logout') }}">@csrf<button>退出登录</button></form>
    </div>
  </aside>
  <main>
    @if(session('ok'))<div class="flash">{{ session('ok') }}</div>@endif
    @if($errors->any())<div class="errors">@foreach($errors->all() as $e)<div>{{ $e }}</div>@endforeach</div>@endif
    @yield('content')
  </main>
</div>
@stack('scripts')
</body>
</html>
