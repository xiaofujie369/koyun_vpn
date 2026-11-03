<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Device extends Model
{
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;
    protected $guarded = [];
    protected $casts = ['first_seen_at' => 'datetime', 'last_seen_at' => 'datetime'];

    public function events()
    {
        return $this->hasMany(ClientEvent::class, 'device_id');
    }

    public function feedback()
    {
        return $this->hasMany(Feedback::class, 'device_id');
    }
}
