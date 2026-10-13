<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class RequireVerifiedFoodAccount
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user()?->disabled_at !== null) {
            return response()->json(['message' => 'บัญชีนี้ถูกระงับ กรุณาติดต่อผู้ดูแล'], 403);
        }
        if (! $request->user()?->email_verified_at) {
            return response()->json(['message' => 'กรุณายืนยันอีเมลก่อนใช้ระบบร้านค้าและออเดอร์'], 403);
        }

        return $next($request);
    }
}
