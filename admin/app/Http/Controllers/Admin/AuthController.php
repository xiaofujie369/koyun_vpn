<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class AuthController extends Controller
{
    public function show()
    {
        return view('admin.login');
    }

    public function login(Request $request)
    {
        $cred = $request->validate(['email' => 'required|email', 'password' => 'required|string']);
        if (! Auth::attempt($cred, $request->boolean('remember'))) {
            return back()->withErrors(['email' => '邮箱或密码错误'])->onlyInput('email');
        }
        $request->session()->regenerate();
        Auth::user()->update(['last_login_at' => now(), 'last_login_ip' => $request->ip()]);
        return redirect()->intended(route('admin.dashboard'));
    }

    public function logout(Request $request)
    {
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();
        return redirect()->route('admin.login');
    }
}
