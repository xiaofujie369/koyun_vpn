<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>登录 · Koyun 后台</title>
<link rel="stylesheet" href="{{ asset('css/admin.css') }}?v=1"></head>
<body style="display:grid;place-items:center;min-height:100vh">
<form method="post" class="card" style="width:340px;padding:26px">
  @csrf
  <h1 style="margin-bottom:2px">Koyun 后台</h1><p class="desc">请登录</p>
  @if($errors->any())<div class="errors">{{ $errors->first() }}</div>@endif
  <div class="field"><label class="f">邮箱</label><input type="email" name="email" value="{{ old('email') }}" required autofocus></div>
  <div class="field"><label class="f">密码</label><input type="password" name="password" required></div>
  <div class="field"><label><input type="checkbox" name="remember" value="1"> 记住我</label></div>
  <button class="btn" style="width:100%">登录</button>
</form>
</body></html>
