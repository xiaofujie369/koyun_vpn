<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;

class Admin extends Authenticatable
{
    protected $fillable = ['email', 'password', 'last_login_at', 'last_login_ip'];
    protected $hidden = ['password', 'remember_token'];
    protected $casts = ['last_login_at' => 'datetime', 'password' => 'hashed'];
}
