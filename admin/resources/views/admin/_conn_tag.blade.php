@php($st = $d->conn_state)
@if($st === 'connected')
  @if($d->online_confirmed)<span class="tag t-ok">在线</span>
  @elseif($d->heartbeat_at === null && $d->conn_changed_at && $d->conn_changed_at->gte(now()->subHours(\App\Services\ConnState::LEGACY_MAX_HOURS)))<span class="tag t-warn" title="旧版没有心跳，根据最后一次连接事件推测">推测在线</span>
  @else<span class="tag">失联</span>@endif
@elseif($st === 'failed')<span class="tag t-bad">连接失败</span>
@elseif($st === 'disconnected')<span class="tag">已断开</span>
@else<span class="muted">—</span>@endif
