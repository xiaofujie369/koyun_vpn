<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Feedback;
use Illuminate\Http\Request;

class FeedbackController extends Controller
{
    public function index(Request $request)
    {
        $q = Feedback::query();
        $status = $request->query('status', 'new');
        if ($status !== 'all') $q->where('status', $status);
        if ($s = trim((string) $request->query('q'))) {
            $q->where(fn ($w) => $w->where('content', 'like', "%$s%")->orWhere('email', 'like', "%$s%")
                ->orWhere('contact', 'like', "%$s%")->orWhere('device_id', 'like', "$s%"));
        }
        $items = $q->orderByDesc('id')->paginate(30)->withQueryString();
        $counts = Feedback::selectRaw('status, COUNT(*) c')->groupBy('status')->pluck('c', 'status');
        return view('admin.feedback', compact('items', 'status', 'counts'));
    }

    public function show(Feedback $feedback)
    {
        return view('admin.feedback_show', ['f' => $feedback]);
    }

    public function update(Request $request, Feedback $feedback)
    {
        $data = $request->validate([
            'status' => 'required|in:new,doing,done',
            'admin_note' => 'nullable|string|max:5000',
        ]);
        $feedback->update($data);
        return back()->with('ok', '已保存');
    }
}
