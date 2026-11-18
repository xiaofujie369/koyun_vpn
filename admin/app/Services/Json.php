<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;

/** 取事件 data 里的字段：线上是 MySQL，自动测试用 SQLite，两者写法不同 */
class Json
{
    public static function field(string $key, string $col = 'data'): string
    {
        if (! preg_match('/^[a-z_]+$/i', $key)) throw new \InvalidArgumentException($key);
        return DB::getDriverName() === 'sqlite'
            ? "json_extract($col, '$.$key')"
            : "JSON_UNQUOTE(JSON_EXTRACT($col, '$.$key'))";
    }
}
