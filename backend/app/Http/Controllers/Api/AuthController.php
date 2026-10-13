<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\MailReadiness;
use App\Services\TokenIssuer;
use Illuminate\Auth\Events\PasswordReset;
use Illuminate\Auth\Events\Verified;
use Illuminate\Contracts\View\View;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Throwable;

class AuthController extends Controller
{
    public function __construct(private MailReadiness $mail, private TokenIssuer $tokens) {}

    public function capabilities(): JsonResponse
    {
        return response()->json(['data' => [
            'googleConfigured' => GoogleAuthController::configured(),
            'emailConfigured' => $this->mail->configured(),
        ]]);
    }

    public function register(Request $request): JsonResponse
    {
        $this->normalizeEmail($request);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email:rfc', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', 'min:8', 'max:128', 'confirmed'],
        ]);
        $this->mail->requireConfigured();

        $user = User::create([
            'display_name' => trim($data['name']),
            'email' => $data['email'],
            'password' => $data['password'],
        ]);
        try {
            $user->sendEmailVerificationNotification();
        } catch (Throwable $error) {
            Log::error('Verification email delivery failed.', ['type' => $error::class]);
            abort(503, 'สร้างบัญชีแล้ว แต่ส่งอีเมลยืนยันไม่สำเร็จ กรุณาเข้าสู่ระบบแล้วลองส่งอีเมลอีกครั้ง');
        }

        return response()->json(['data' => $this->tokens->issue($user)], 201);
    }

    public function login(Request $request): JsonResponse
    {
        $this->normalizeEmail($request);
        $data = $request->validate([
            'email' => ['required', 'email:rfc', 'max:255'],
            'password' => ['required', 'string', 'max:128'],
            'deviceName' => ['nullable', 'string', 'max:80'],
        ]);
        $user = User::where('email', $data['email'])->first();
        if ($user === null || $user->disabled_at !== null || $user->password === null || ! Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages(['email' => ['อีเมลหรือรหัสผ่านไม่ถูกต้อง หากย้ายบัญชีจากระบบเดิม กรุณาใช้ลืมรหัสผ่าน']]);
        }

        return response()->json(['data' => $this->tokens->issue($user, $data['deviceName'] ?? 'MSU Food')]);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json(['data' => $request->user()->toApiArray()]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()?->delete();

        return response()->json(['data' => ['message' => 'ออกจากระบบแล้ว']]);
    }

    public function resendVerification(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user->hasVerifiedEmail()) {
            return response()->json(['data' => ['message' => 'ยืนยันอีเมลแล้ว']]);
        }
        $this->mail->requireConfigured();
        try {
            $user->sendEmailVerificationNotification();
        } catch (Throwable $error) {
            Log::error('Verification email delivery failed.', ['type' => $error::class]);
            abort(503, 'ส่งอีเมลยืนยันไม่สำเร็จ กรุณาลองอีกครั้งภายหลัง');
        }

        return response()->json(['data' => ['message' => 'ส่งอีเมลยืนยันแล้ว กรุณาตรวจกล่องข้อความและจดหมายขยะ']]);
    }

    public function verifyEmail(Request $request, string $id, string $hash): JsonResponse|Response
    {
        $user = User::findOrFail($id);
        abort_if($user->disabled_at !== null, 403, 'บัญชีนี้ถูกระงับการใช้งาน กรุณาติดต่อผู้ดูแล');
        abort_unless(hash_equals(sha1($user->getEmailForVerification()), $hash), 403, 'ลิงก์ยืนยันไม่ถูกต้อง');
        if (! $user->hasVerifiedEmail() && $user->markEmailAsVerified()) {
            event(new Verified($user));
        }
        if ($request->expectsJson()) {
            return response()->json(['data' => ['message' => 'ยืนยันอีเมลแล้ว กลับไปที่แอปแล้วกดตรวจสอบอีกครั้ง']]);
        }

        return response()->view('auth.verified');
    }

    public function forgotPassword(Request $request): JsonResponse
    {
        $this->normalizeEmail($request);
        $data = $request->validate(['email' => ['required', 'email:rfc', 'max:255']]);
        $this->mail->requireConfigured();
        try {
            $status = Password::sendResetLink($data);
        } catch (Throwable $error) {
            Log::error('Password reset email delivery failed.', ['type' => $error::class]);
            abort(503, 'ส่งอีเมลรีเซ็ตรหัสผ่านไม่สำเร็จ กรุณาลองอีกครั้งภายหลัง');
        }
        if (! in_array($status, [Password::RESET_LINK_SENT, Password::INVALID_USER, Password::RESET_THROTTLED], true)) {
            abort(503, 'ระบบรีเซ็ตรหัสผ่านไม่พร้อมใช้งาน');
        }

        return response()->json(['data' => ['message' => 'หากมีบัญชีนี้ในระบบ จะได้รับอีเมลสำหรับตั้งรหัสผ่านใหม่']]);
    }

    public function resetPassword(Request $request): JsonResponse
    {
        $this->performPasswordReset($request);

        return response()->json(['data' => ['message' => 'ตั้งรหัสผ่านใหม่แล้ว กรุณาเข้าสู่ระบบอีกครั้ง']]);
    }

    public function resetPage(Request $request, string $token): View
    {
        return view('auth.reset', ['token' => $token, 'email' => (string) $request->query('email', '')]);
    }

    public function resetInBrowser(Request $request): RedirectResponse
    {
        $this->performPasswordReset($request);

        return back()->with('status', 'ตั้งรหัสผ่านใหม่แล้ว กลับไปที่แอปเพื่อเข้าสู่ระบบ');
    }

    public function changePassword(Request $request): JsonResponse
    {
        $data = $request->validate([
            'currentPassword' => ['required', 'string', 'max:128'],
            'newPassword' => ['required', 'string', 'min:8', 'max:128', 'different:currentPassword'],
            'newPasswordConfirmation' => ['required', 'same:newPassword'],
        ]);
        $user = $request->user();
        if ($user->password === null || ! Hash::check($data['currentPassword'], $user->password)) {
            throw ValidationException::withMessages(['currentPassword' => ['รหัสผ่านปัจจุบันไม่ถูกต้อง']]);
        }
        $user->forceFill(['password' => $data['newPassword'], 'remember_token' => Str::random(60)])->save();
        $currentId = $user->currentAccessToken()?->getKey();
        $user->tokens()->when($currentId !== null, fn ($query) => $query->where('id', '!=', $currentId))->delete();

        return response()->json(['data' => ['message' => 'เปลี่ยนรหัสผ่านแล้ว และออกจากระบบในอุปกรณ์อื่น']]);
    }

    private function performPasswordReset(Request $request): void
    {
        $this->normalizeEmail($request);
        $data = $request->validate([
            'email' => ['required', 'email:rfc', 'max:255'],
            'token' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string', 'min:8', 'max:128', 'confirmed'],
        ]);
        $status = Password::reset($data, function (User $user, string $password): void {
            abort_if($user->disabled_at !== null, 403, 'บัญชีนี้ถูกระงับการใช้งาน กรุณาติดต่อผู้ดูแล');
            $user->forceFill([
                'password' => $password,
                'legacy_password_user' => false,
                'email_verified_at' => $user->email_verified_at ?? now(),
                'remember_token' => Str::random(60),
            ])->save();
            $user->tokens()->delete();
            event(new PasswordReset($user));
        });
        if ($status !== Password::PASSWORD_RESET) {
            throw ValidationException::withMessages(['token' => ['ลิงก์หมดอายุหรือไม่ถูกต้อง กรุณาขอรีเซ็ตรหัสผ่านใหม่']]);
        }
    }

    private function normalizeEmail(Request $request): void
    {
        if (is_string($request->input('email'))) {
            $request->merge(['email' => Str::lower(trim($request->input('email')))]);
        }
    }
}
