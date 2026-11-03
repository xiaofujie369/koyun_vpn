<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Feedback extends Model
{
    protected $table = 'feedback';
    protected $guarded = [];
    protected $casts = ['extra' => 'array', 'device' => 'array'];

    public const STATUS = ['new' => '待处理', 'doing' => '处理中', 'done' => '已处理'];
}
