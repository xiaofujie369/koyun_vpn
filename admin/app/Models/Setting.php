<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Cache;

class Setting extends Model
{
    protected $primaryKey = 'key';
    public $incrementing = false;
    protected $keyType = 'string';
    public const CREATED_AT = null;
    protected $guarded = [];
    protected $casts = ['value' => 'array'];

    public static function val(string $key, $default = null)
    {
        return Cache::remember("koyun_setting_$key", 60, fn () => static::find($key)?->value) ?? $default;
    }

    public static function put(string $key, $value): void
    {
        static::updateOrCreate(['key' => $key], ['value' => $value]);
        Cache::forget("koyun_setting_$key");
    }
}
