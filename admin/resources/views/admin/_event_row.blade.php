@php($t = $e->type)
@php($cls = ['connect_ok'=>'t-ok','connect_fail'=>'t-bad','crash'=>'t-bad','disconnect'=>'','app_start'=>'t-accent'][$t] ?? '')
<tr>
  <td class="muted" style="white-space:nowrap">{{ $e->created_at?->format('m-d H:i:s') }}</td>
  @if(!isset($hideDevice))<td class="mono"><a href="{{ route('admin.devices.show', $e->device_id) }}">{{ substr($e->device_id,0,8) }}</a></td>@endif
  <td><span class="tag {{ $cls }}">{{ \App\Models\ClientEvent::TYPES[$t] ?? $t }}</span></td>
  <td class="mono" style="word-break:break-all">
    @php($d = $e->data ?? [])
    @if($t==='connect_ok') {{ $d['node'] ?? '' }} · {{ $d['protocol'] ?? '' }} · {{ ($d['tun'] ?? false) ? 'TUN' : '系统代理' }} · {{ $d['route'] ?? '' }} · {{ $d['ms'] ?? '?' }} ms
    @elseif($t==='connect_fail') {{ $d['node'] ?? '' }} · {{ $d['protocol'] ?? '' }} · <span style="color:var(--bad)">{{ \Illuminate\Support\Str::limit($d['error'] ?? '', 300) }}</span>
    @elseif($t==='disconnect') {{ $d['node'] ?? '' }} · 用了 {{ gmdate('H:i:s', (int)($d['duration_s'] ?? 0)) }} · ↓{{ round(($d['down_bytes'] ?? 0)/1048576,1) }} MB ↑{{ round(($d['up_bytes'] ?? 0)/1048576,1) }} MB
    @elseif($t==='crash') <details><summary style="color:var(--bad)">{{ \Illuminate\Support\Str::limit($d['error'] ?? '', 200) }}</summary><pre>{{ $d['stack'] ?? '' }}</pre></details>
    @else {{ $d ? json_encode($d, JSON_UNESCAPED_UNICODE) : '' }}
    @endif
  </td>
  <td class="mono muted">{{ $e->ip }}</td>
</tr>
