<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/** 清理过期事件（每天自动运行），反馈不删 */
class PruneCommand extends Command
{
    protected $signature = 'koyun:prune';
    protected $description = '删除超过保留天数的事件';

    public function handle(): int
    {
        $days = max(7, (int) config('koyun.retention_days'));
        $before = now()->subDays($days);
        $total = 0;
        do {
            $n = DB::table('client_events')->where('created_at', '<', $before)->limit(5000)->delete();
            $total += $n;
        } while ($n > 0);
        $this->info("已删除 $days 天前的事件 $total 条");
        return 0;
    }
}
