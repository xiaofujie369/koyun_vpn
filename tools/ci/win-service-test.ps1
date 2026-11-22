# CI（GitHub Windows 机器，管理员身份）：真实走一遍 1.1.6 → 新版升级、后台服务、TUN、卸载。
# 用法：pwsh tools/ci/win-service-test.ps1 <新安装包> [<1.1.6 旧安装包>]
param([Parameter(Mandatory)] [string]$Setup, [string]$OldSetup)
$ErrorActionPreference = 'Stop'
$failed = 0
function Check($ok, $msg) {
  if ($ok) { Write-Host "✅ $msg" } else { Write-Host "❌ $msg"; $script:failed++ }
}
function Run-Setup($exe, $extra) {
  # 不能用 -Wait：它连子进程一起等，而安装完会自动打开 Koyun（一直不退出）
  $p = Start-Process $exe -ArgumentList (@('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') + $extra) -PassThru
  if (-not $p.WaitForExit(600000)) { Write-Host "安装超过 10 分钟没结束"; $p.Kill(); return -1 }
  Start-Sleep 3
  Get-Process Koyun -ErrorAction SilentlyContinue | Stop-Process -Force   # 静默安装后会自动打开 App
  return $p.ExitCode
}

$old = "$env:LOCALAPPDATA\Programs\Koyun"
$new = "$env:ProgramFiles\Koyun"
$uninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{6E0C3D52-7A1B-4E2B-9C4B-6B1F2A9E7C01}_is1'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

# 1. 模拟老用户：装 1.1.6（用户目录版，勾选开机启动）
if ($OldSetup) {
  Run-Setup $OldSetup @('/CURRENTUSER', '/TASKS=autostart') | Out-Null
  Check (Test-Path "$old\Koyun.exe") "1.1.6 装在用户目录 $old"
}

# 2. 升级到新版
$code = Run-Setup $Setup @()
Check ($code -eq 0) "新版安装退出码 $code"
Check (Test-Path "$new\Koyun.exe") "新版装在 $new"
Check (Test-Path "$new\koyun-service.exe") "包含 koyun-service.exe"
if ($OldSetup) {
  Check (-not (Test-Path "$old\Koyun.exe")) "旧的用户目录版已卸载"
  Check (-not (Test-Path $uninstKey)) "旧的卸载记录已清除"
  $run = (Get-ItemProperty $runKey -ErrorAction SilentlyContinue).Koyun
  Check ($run -like "*Program Files\Koyun\Koyun.exe*") "开机启动已改到新路径：$run"
}

# 3. 服务
$svc = Get-Service KoyunService -ErrorAction SilentlyContinue
Check ($svc -and $svc.Status -eq 'Running') "KoyunService 正在运行"
Check ($svc -and $svc.StartType -eq 'Automatic') "KoyunService 开机自动启动"
$stateFile = "$new\service-data\service.json"
for ($i = 0; $i -lt 20 -and -not (Test-Path $stateFile); $i++) { Start-Sleep -Milliseconds 500 }
Check (Test-Path $stateFile) "连接信息文件存在"
$acl = (icacls "$new\service-data") -join "`n"
Write-Host $acl
Check (-not ($acl -match 'BUILTIN\\Users|Everyone|Authenticated Users|\\Users:')) "连接信息目录只有 SYSTEM / 管理员 / 安装用户能访问"

$st = Get-Content $stateFile | ConvertFrom-Json
$base = "http://127.0.0.1:$($st.port)"
$h = @{ 'X-Koyun-Token' = $st.token }
function Api($method, $path, $body) {
  $r = Invoke-WebRequest -Uri "$base$path" -Method $method -Headers $h -Body $body -ContentType 'application/json' -SkipHttpErrorCheck
  return @{ code = [int]$r.StatusCode; json = ($r.Content | ConvertFrom-Json) }
}
$noTok = Invoke-WebRequest -Uri "$base/v1/status" -SkipHttpErrorCheck
Check ($noTok.StatusCode -eq 403) "没有令牌：拒绝（$($noTok.StatusCode)）"
$withOrigin = Invoke-WebRequest -Uri "$base/v1/status" -Headers @{ 'X-Koyun-Token' = $st.token; 'Origin' = 'https://evil.example' } -SkipHttpErrorCheck
Check ($withOrigin.StatusCode -eq 403) "浏览器跨站请求：拒绝（$($withOrigin.StatusCode)）"

# 4. 通过服务以 SYSTEM 启动 TUN（不改路由，避免影响 CI 机器联网）
$cfg = @{
  log = @{ level = 'info'; output = 'C:\Windows\koyun-should-not-exist.log' }
  inbounds = @(
    @{ type = 'tun'; tag = 'tun-in'; interface_name = 'Koyun-CI'; address = @('172.19.0.1/30'); auto_route = $false; stack = 'mixed' },
    @{ type = 'mixed'; listen = '127.0.0.1'; listen_port = 17998 }
  )
  outbounds = @(@{ type = 'direct' })
} | ConvertTo-Json -Depth 6
$r = Api 'POST' '/v1/start' $cfg
Write-Host ($r.json | ConvertTo-Json -Compress)
Check ($r.code -eq 200 -and $r.json.running) "服务启动内核（TUN）"
Start-Sleep 3
$ad = Get-NetAdapter -Name 'Koyun-CI' -ErrorAction SilentlyContinue
Check ($null -ne $ad) "TUN 网卡 Koyun-CI 已创建（普通权限做不到，说明是服务以 SYSTEM 创建的）"
$c = curl.exe -s -o NUL -w '%{http_code}' --max-time 20 -x http://127.0.0.1:17998 http://www.gstatic.com/generate_204
Check ($c -eq '204') "通过服务启动的内核联网（HTTP ${c}）"
Check (-not (Test-Path 'C:\Windows\koyun-should-not-exist.log')) "配置里的 log.output 被去掉，没有以系统权限写文件"
$logs = Api 'GET' '/v1/logs?since=0' $null
Check ($logs.json.lines.Count -gt 0) "能读到内核日志（$($logs.json.lines.Count) 行）"

# 5. 启动失败要返回原因
$bad = @{ inbounds = @(@{ type = 'mixed'; tag = 'a'; listen = '127.0.0.1'; listen_port = 17997 }, @{ type = 'mixed'; tag = 'b'; listen = '127.0.0.1'; listen_port = 17997 }); outbounds = @(@{ type = 'direct' }) } | ConvertTo-Json -Depth 6
$r = Api 'POST' '/v1/start' $bad
Check ($r.code -eq 422 -and $r.json.error) "启动失败返回原因：$($r.json.error)"

$r = Api 'POST' '/v1/stop' $null
Check (-not $r.json.running) "停止内核"
Start-Sleep 2
Check ($null -eq (Get-NetAdapter -Name 'Koyun-CI' -ErrorAction SilentlyContinue)) "正常停止后 TUN 网卡已删除（内核收到 Ctrl+Break 正常退出，不再留下残留网卡）"

# 模拟内核崩溃：强制结束后，再用同名网卡启动必须成功（服务会在后台清掉残留网卡）
$r = Api 'POST' '/v1/start' $cfg
Check ($r.code -eq 200) "再次启动 TUN"
Start-Sleep 2
Stop-Process -Name sing-box -Force -ErrorAction SilentlyContinue
Start-Sleep 8
$t0 = Get-Date
$r = Api 'POST' '/v1/start' $cfg
Start-Sleep 3
$st3 = Api 'GET' '/v1/status' $null
$secs = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
Check ($r.code -eq 200 -and $st3.json.running) "内核被强制结束后，再用同名网卡启动成功（$secs 秒）"
Check ($null -ne (Get-NetAdapter -Name 'Koyun-CI' -ErrorAction SilentlyContinue)) "TUN 网卡重新创建"
$r = Api 'POST' '/v1/stop' $null

# 6. 服务重启（模拟开机）后生成新令牌，照样能用
Restart-Service KoyunService
Start-Sleep 2
$st2 = Get-Content $stateFile | ConvertFrom-Json
Check ($st2.token -ne $st.token) "服务重启后换了新令牌"
$ok = Invoke-WebRequest -Uri "http://127.0.0.1:$($st2.port)/v1/status" -Headers @{ 'X-Koyun-Token' = $st2.token } -SkipHttpErrorCheck
Check ($ok.StatusCode -eq 200) "新令牌可用"

# 7. 再装一次（覆盖升级）：服务要能被替换并继续运行
$code = Run-Setup $Setup @()
Check ($code -eq 0 -and (Get-Service KoyunService).Status -eq 'Running') "覆盖安装后服务仍在运行"

# 8. 卸载
$u = Start-Process "$new\unins000.exe" -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -PassThru
$u.WaitForExit(300000) | Out-Null
# 卸载程序会把自己复制到临时目录再运行，等真正的卸载结束
for ($i = 0; $i -lt 60 -and (Test-Path "$new\unins000.exe"); $i++) { Start-Sleep 1 }
Start-Sleep 3
Check ($null -eq (Get-Service KoyunService -ErrorAction SilentlyContinue)) "卸载后服务已删除"
Check (-not (Test-Path "$new\service-data")) "卸载后服务数据已删除"

if ($failed -gt 0) { Write-Host "共 $failed 项失败"; exit 1 }
Write-Host '全部通过'
