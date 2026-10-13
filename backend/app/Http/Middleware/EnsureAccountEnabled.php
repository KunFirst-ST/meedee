<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureAccountEnabled
{
    /**
     * Handle an incoming request.
     *
     * @param  Closure(Request): (Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        abort_if($request->user()?->disabled_at !== null, 403, 'บัญชีนี้ถูกระงับการใช้งาน กรุณาติดต่อผู้ดูแล');

        return $next($request);
    }
}
