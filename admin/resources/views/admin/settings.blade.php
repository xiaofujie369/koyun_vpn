@extends('admin.layout')
@section('title', '设置')
@section('content')
<h1>设置</h1>
<p class="desc">客户端密钥：{!! $keySet ? '<span class="tag t-ok">已设置</span>' : '<span class="tag t-bad">未设置（App 上报会被拒绝）</span>' !!} · 事件保留 {{ $retention }} 天</p>
<div class="grid g2">
  <div class="card">
    <h2>App 更新信息</h2>
    <p class="muted" style="margin-top:-6px">打开后，App 的「检查更新」会优先读这里（比 GitHub 在国内更快）。版本号要比客户当前版本新才会提示。</p>
    @php($l = $latest ?: [])
    <form method="post" action="{{ route('admin.settings.update') }}">@csrf
      <div class="field"><label><input type="checkbox" name="enabled" value="1" @checked(!empty($l['enabled']))> 启用</label></div>
      <div class="field"><label class="f">最新版本号（例如 1.1.0）</label><input type="text" name="version" value="{{ old('version', $l['version'] ?? '') }}"></div>
      <div class="field"><label class="f">更新说明</label><textarea name="notes">{{ old('notes', $l['notes'] ?? '') }}</textarea></div>
      <div class="field"><label class="f">下载页面</label><input type="url" name="page" value="{{ old('page', $l['page'] ?? '') }}" placeholder="https://"></div>
      <div class="field"><label class="f">Windows 安装包地址（-setup.exe）</label><input type="url" name="windows" value="{{ old('windows', $l['downloads']['windows'] ?? '') }}" placeholder="https://"></div>
      <div class="field"><label class="f">安卓 APK 地址</label><input type="url" name="android" value="{{ old('android', $l['downloads']['android'] ?? '') }}" placeholder="https://"></div>
      <div class="field"><label class="f">macOS 安装包地址</label><input type="url" name="macos" value="{{ old('macos', $l['downloads']['macos'] ?? '') }}" placeholder="https://"></div>
      <button class="btn">保存</button>
    </form>
  </div>
  <div class="card">
    <h2>修改密码</h2>
    <form method="post" action="{{ route('admin.settings.password') }}">@csrf
      <div class="field"><label class="f">当前密码</label><input type="password" name="current" required></div>
      <div class="field"><label class="f">新密码（至少 10 位）</label><input type="password" name="password" required></div>
      <div class="field"><label class="f">再输一次新密码</label><input type="password" name="password_confirmation" required></div>
      <button class="btn">修改密码</button>
    </form>
  </div>
</div>
@endsection
