@php($t = $e->type)
@php($cls = ['connect_ok'=>'t-ok','connect_fail'=>'t-bad','crash'=>'t-bad','disconnect'=>'','app_start'=>'t-accent','core_exit'=>'t-bad','node_unreachable'=>'t-warn','core_recover'=>'t-warn','proxy_guard'=>'t-warn'][$t] ?? '')
<tr>
  <td class="muted" style="white-space:nowrap">{{ $e->created_at?->format('m-d H:i:s') }}</td>
  @if(!isset($hideDevice))<td class="mono"><a href="{{ route('admin.devices.show', $e->device_id) }}">{{ substr($e->device_id,0,8) }}</a></td>@endif
  <td><span class="tag {{ $cls }}">{{ \App\Models\ClientEvent::TYPES[$t] ?? $t }}</span></td>
  <td class="mono" style="word-break:break-all">
    @php($d = $e->data ?? [])
    @if($t==='connect_ok') {{ $d['node'] ?? '' }} · {{ $d['protocol'] ?? '' }} · {{ ($d['tun'] ?? false) ? 'TUN' : '系统代理' }} · {{ $d['route'] ?? '' }} · {{ $d['ms'] ?? '?' }} ms
    @elseif($t==='connect_fail') {{ $d['node'] ?? '' }} · {{ $d['protocol'] ?? '' }} · <span style="color:var(--bad)">{{ isset($d['kind']) ? (\App\Models\ClientEvent::FAIL_KINDS[$d['kind']] ?? $d['kind']).'：' : '' }}{{ \Illuminate\Support\Str::limit($d['error'] ?? '', 300) }}</span>
    @elseif($t==='node_unreachable') {{ $d['node'] ?? '' }} · {{ ($d['after'] ?? '')==='switch' ? '切换后检测不通' : '连接中检测不通' }}
    @elseif($t==='core_exit') <span style="color:var(--bad)">{{ \Illuminate\Support\Str::limit($d['error'] ?? '', 300) }}</span>@if(isset($d['code'])) · 退出码 {{ $d['code'] }}@endif
    @elseif($t==='core_recover') {{ ($d['reason'] ?? '')==='process_died' ? 'App 被系统结束后重新打开，自动重连' : '内核退出后自动重连（第 '.($d['attempt'] ?? '?').' 次）' }}
    @elseif($t==='proxy_guard') 系统代理被其他软件改掉，已自动恢复
    @elseif($t==='net_reset') {{ \Illuminate\Support\Str::limit($d['line'] ?? '', 200) }}@if(isset($d['skipped'])) · 省略 {{ $d['skipped'] }} 次@endif
    @elseif($t==='disconnect') {{ $d['node'] ?? '' }} · 用了 {{ gmdate('H:i:s', (int)($d['duration_s'] ?? 0)) }} · ↓{{ round(($d['down_bytes'] ?? 0)/1048576,1) }} MB ↑{{ round(($d['up_bytes'] ?? 0)/1048576,1) }} MB
    @elseif($t==='crash') <details><summary style="color:var(--bad)">{{ \Illuminate\Support\Str::limit($d['error'] ?? '', 200) }}</summary><pre>{{ $d['stack'] ?? '' }}</pre></details>
    @else {{ $d ? json_encode($d, JSON_UNESCAPED_UNICODE) : '' }}
    @endif
  </td>
  <td class="mono muted">{{ $e->ip }}</td>
</tr>
