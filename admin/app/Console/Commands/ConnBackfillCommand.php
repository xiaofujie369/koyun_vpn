<?php

namespace App\Console\Commands;

use App\Services\ConnState;
use Illuminate\Console\Command;

class ConnBackfillCommand extends Command
{
    protected $signature = 'koyun:conn-backfill';
    protected $description = '根据已有事件推算每台设备当前的连接状态（部署“实时在线”时运行一次）';

    public function handle(): int
    {
        $this->info('已更新 ' . ConnState::backfill() . ' 台设备');
        return self::SUCCESS;
    }
}
