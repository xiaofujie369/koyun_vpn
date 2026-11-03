<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Setting;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class SettingController extends Controller
{
    public function edit()
    {
        return view('admin.settings', [
            'latest' => Setting::val('latest', []),
            'retention' => config('koyun.retention_days'),
            'keySet' => config('koyun.client_key') !== '',
        ]);
    }

    /** 更新信息（App 的"检查更新"会读取） */
    public function update(Request $request)
    {
        $d = $request->validate([
            'enabled' => 'nullable|boolean',
            'version' => ['nullable', 'regex:/^\d+\.\d+\.\d+$/'],
            'notes' => 'nullable|string|max:3000',
            'page' => 'nullable|url:https|max:500',
            'windows' => 'nullable|url:https|max:500',
            'android' => 'nullable|url:https|max:500',
            'macos' => 'nullable|url:https|max:500',
        ], ['version.regex' => '版本号格式应为 1.2.3', '*.url' => '必须是 https:// 开头的网址']);
        Setting::put('latest', [
            'enabled' => (bool) ($d['enabled'] ?? false),
            'version' => $d['version'] ?? '',
            'notes' => $d['notes'] ?? '',
            'page' => $d['page'] ?? '',
            'downloads' => ['windows' => $d['windows'] ?? '', 'android' => $d['android'] ?? '', 'macos' => $d['macos'] ?? ''],
        ]);
        return back()->with('ok', '更新信息已保存');
    }

    public function password(Request $request)
    {
        $request->validate([
            'current' => 'required|current_password',
            'password' => 'required|string|min:10|confirmed',
        ], ['current.current_password' => '当前密码不正确', 'password.min' => '新密码至少 10 位', 'password.confirmed' => '两次输入的新密码不一致']);
        $request->user()->update(['password' => $request->input('password')]);
        return back()->with('ok', '密码已修改');
    }
}
