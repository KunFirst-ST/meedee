<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\TokenIssuer;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Laravel\Socialite\Facades\Socialite;
use Throwable;

class GoogleAuthController extends Controller
{
    public function __construct(private TokenIssuer $tokens) {}

    public static function configured(): bool
    {
        $redirect = parse_url((string) config('services.google.redirect'));
        $secureRedirect = ($redirect['scheme'] ?? '') === 'https'
            || (! app()->isProduction() && ($redirect['scheme'] ?? '') === 'http' && in_array($redirect['host'] ?? '', ['localhost', '127.0.0.1', '::1'], true));

        return filled(config('services.google.client_id'))
            && filled(config('services.google.client_secret'))
            && $secureRedirect;
    }

    public function start(Request $request): JsonResponse
    {
        $this->requireConfigured();
        $data = $request->validate([
            'redirectUri' => ['required', 'string', 'max:2048', Rule::in(config('food.callback_uris', []))],
            'state' => ['required', 'string', 'regex:/^[A-Za-z0-9_-]{32,128}$/'],
            'codeChallenge' => ['required', 'string', 'regex:/^[A-Za-z0-9_-]{43}$/'],
            'codeChallengeMethod' => ['required', Rule::in(['S256'])],
        ]);
        $providerState = Str::random(64);
        DB::table('oauth_attempts')->insert([
            'state_hash' => hash('sha256', $providerState),
            'client_state_hash' => hash('sha256', $data['state']),
            'client_state' => $data['state'],
            'challenge' => $data['codeChallenge'],
            'redirect_uri' => $data['redirectUri'],
            'expires_at' => now()->addMinutes(10),
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $url = Socialite::driver('google')->stateless()->with([
            'state' => $providerState,
            'prompt' => 'select_account',
        ])->redirect()->getTargetUrl();

        return response()->json(['data' => ['url' => $url]])->header('Cache-Control', 'no-store');
    }

    public function callback(Request $request): RedirectResponse
    {
        $this->requireConfigured();
        $request->validate(['state' => ['required', 'string', 'max:128']]);
        $attempt = DB::transaction(function () use ($request): object {
            $attempt = DB::table('oauth_attempts')->where('state_hash', hash('sha256', $request->string('state')->toString()))->lockForUpdate()->first();
            abort_if($attempt === null || $attempt->consumed_at !== null || CarbonImmutable::parse($attempt->expires_at)->isPast(), 400, 'คำขอเข้าสู่ระบบหมดอายุหรือไม่ถูกต้อง กรุณาลองอีกครั้ง');
            DB::table('oauth_attempts')->where('state_hash', $attempt->state_hash)->update(['consumed_at' => now(), 'updated_at' => now()]);

            return $attempt;
        });
        if ($request->filled('error')) {
            return $this->redirectResult($attempt, ['error' => $request->input('error') === 'access_denied' ? 'cancelled' : 'oauth_failed']);
        }

        try {
            $identity = Socialite::driver('google')->stateless()->user();
            $raw = $identity->getRaw();
            if (($raw['email_verified'] ?? false) !== true || ! filter_var($identity->getEmail(), FILTER_VALIDATE_EMAIL) || ! filled($identity->getId())) {
                return $this->redirectResult($attempt, ['error' => 'email_not_verified']);
            }

            $email = Str::lower(trim($identity->getEmail()));
            $user = DB::transaction(function () use ($identity, $email): ?User {
                $user = User::where('google_id', $identity->getId())->lockForUpdate()->first();
                $emailOwner = User::where('email', $email)->lockForUpdate()->first();
                if ($emailOwner !== null && ($user === null || $emailOwner->id !== $user->id)) {
                    return null;
                }
                if ($user !== null) {
                    if ($user->disabled_at !== null) {
                        return null;
                    }
                    $user->forceFill(['email' => $email, 'email_verified_at' => $user->email_verified_at ?? now()])->save();

                    return $user;
                }

                return User::create([
                    'display_name' => Str::limit(trim($identity->getName() ?: Str::before($email, '@')), 120, ''),
                    'email' => $email,
                    'google_id' => $identity->getId(),
                    'email_verified_at' => now(),
                    'password' => null,
                ]);
            });
            if ($user === null) {
                return $this->redirectResult($attempt, ['error' => 'account_link_required']);
            }

            $code = Str::random(64);
            DB::table('oauth_exchange_codes')->insert([
                'code_hash' => hash('sha256', $code),
                'user_id' => $user->id,
                'state_hash' => $attempt->client_state_hash,
                'challenge' => $attempt->challenge,
                'expires_at' => now()->addMinutes(2),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            return $this->redirectResult($attempt, ['code' => $code]);
        } catch (Throwable $error) {
            Log::error('Google OAuth callback failed.', ['type' => $error::class]);

            return $this->redirectResult($attempt, ['error' => 'oauth_failed']);
        }
    }

    public function exchange(Request $request): JsonResponse
    {
        $data = $request->validate([
            'code' => ['required', 'string', 'regex:/^[A-Za-z0-9]{64}$/'],
            'state' => ['required', 'string', 'regex:/^[A-Za-z0-9_-]{32,128}$/'],
            'verifier' => ['required', 'string', 'regex:/^[A-Za-z0-9._~-]{43,128}$/'],
        ]);
        $session = DB::transaction(function () use ($data): array {
            $exchange = DB::table('oauth_exchange_codes')->where('code_hash', hash('sha256', $data['code']))->lockForUpdate()->first();
            $challenge = rtrim(strtr(base64_encode(hash('sha256', $data['verifier'], true)), '+/', '-_'), '=');
            abort_if($exchange === null || $exchange->consumed_at !== null || CarbonImmutable::parse($exchange->expires_at)->isPast(), 400, 'รหัสเข้าสู่ระบบหมดอายุหรือใช้งานแล้ว');
            abort_unless(hash_equals($exchange->state_hash, hash('sha256', $data['state'])) && hash_equals($exchange->challenge, $challenge), 400, 'คำขอเข้าสู่ระบบไม่ตรงกับอุปกรณ์นี้');
            $user = User::findOrFail($exchange->user_id);
            abort_if($user->disabled_at !== null, 403, 'บัญชีนี้ถูกระงับการใช้งาน กรุณาติดต่อผู้ดูแล');
            abort_unless($user->hasVerifiedEmail(), 403, 'บัญชียังไม่ได้ยืนยันอีเมล');
            DB::table('oauth_exchange_codes')->where('code_hash', $exchange->code_hash)->update(['consumed_at' => now(), 'updated_at' => now()]);

            return $this->tokens->issue($user);
        });

        return response()->json(['data' => $session])->header('Cache-Control', 'no-store');
    }

    /** @param array<string, string> $parameters */
    private function redirectResult(object $attempt, array $parameters): RedirectResponse
    {
        $separator = str_contains($attempt->redirect_uri, '?') ? '&' : '?';

        return redirect()->away($attempt->redirect_uri.$separator.http_build_query([...$parameters, 'state' => $attempt->client_state]))->header('Cache-Control', 'no-store')->header('Referrer-Policy', 'no-referrer');
    }

    private function requireConfigured(): void
    {
        abort_unless(self::configured(), 503, 'Google Login ยังไม่ได้ตั้งค่า Google OAuth บนเซิร์ฟเวอร์ กรุณาติดต่อผู้ดูแล');
    }
}
