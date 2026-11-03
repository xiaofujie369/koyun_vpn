@if($p->hasPages())
<div class="pager">
  @if($p->onFirstPage())<span class="muted">上一页</span>@else<a href="{{ $p->previousPageUrl() }}">上一页</a>@endif
  <span class="cur">{{ $p->currentPage() }} / {{ $p->lastPage() }}</span>
  @if($p->hasMorePages())<a href="{{ $p->nextPageUrl() }}">下一页</a>@else<span class="muted">下一页</span>@endif
  <span>共 {{ $p->total() }} 条</span>
</div>
@endif
