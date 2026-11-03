<?php

namespace App\Console\Commands;

use App\Models\Admin;
use Illuminate\Console\Command;
use Illuminate\Support\Str;

/** 创建管理员 / 重置密码：php artisan koyun:admin 邮箱 */
class AdminCommand extends Command
{
    protected $signature = 'koyun:admin {email}';
    protected $description = '创建后台管理员或重置其密码（随机生成新密码）';

    public function handle(): int
    {
        $email = $this->argument('email');
        $password = Str::password(16, symbols: false);
        $admin = Admin::firstOrNew(['email' => $email]);
        $new = ! $admin->exists;
        $admin->password = $password;
        $admin->save();
        $this->info(($new ? '已创建管理员' : '已重置密码') . "：$email");
        $this->line("密码：$password");
        $this->line('后台地址：' . rtrim(config('app.url'), '/') . '/' . config('koyun.admin_path'));
        return 0;
    }
}
