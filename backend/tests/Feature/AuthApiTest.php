<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Auth\Notifications\VerifyEmail;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Facades\URL;
use Tests\TestCase;

class AuthApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_protected_api_without_accept_header_returns_json_401_without_login_redirect(): void
    {
        $this->app['env'] = 'production';
        $this->get('https://localhost/api/v1/shops')
            ->assertUnauthorized()
            ->assertHeader('Content-Type', 'application/json')
            ->assertHeaderMissing('Location')
            ->assertJsonPath('message', 'Unauthenticated.');
    }

    public function test_production_rejects_plaintext_api_transport_and_allows_https(): void
    {
        $this->app['env'] = 'production';
        $this->getJson('http://localhost/api/v1/capabilities')->assertStatus(426);
        $this->getJson('https://localhost/api/v1/capabilities')->assertOk()->assertHeader('Cache-Control', 'no-store, private');
    }

    public function test_unconfigured_mail_never_reports_registration_or_reset_success(): void
    {
        Notification::fake();
        config(['food.email_enabled' => true, 'mail.default' => 'log']);
        $this->getJson('/api/v1/capabilities')->assertOk()->assertJsonPath('data.emailConfigured', false);
        $this->postJson('/api/v1/auth/register', $this->registration())->assertStatus(503);
        $this->postJson('/api/v1/auth/password/forgot', ['email' => 'customer@example.test'])->assertStatus(503);
        $this->assertDatabaseCount('users', 0);
        Notification::assertNothingSent();
        config(['mail.default' => 'failover']);
        $this->getJson('/api/v1/capabilities')->assertOk()->assertJsonPath('data.emailConfigured', false);
    }

    public function test_register_sends_verification_and_limits_unverified_account_to_auth(): void
    {
        $this->configureMail();
        Notification::fake();
        $response = $this->postJson('/api/v1/auth/register', $this->registration());
        $response->assertCreated()->assertJsonPath('data.user.emailVerified', false)->assertJsonPath('data.user.role', null)->assertJsonPath('data.user.providers', ['password']);
        $user = User::where('email', 'customer@example.test')->firstOrFail();
        $this->assertTrue(Hash::check('FoodPassword123', $user->password));
        $this->assertFalse(array_key_exists('password', $response->json('data.user')));
        Notification::assertSentTo($user, VerifyEmail::class);
        $this->withToken($response->json('data.token'))->getJson('/api/v1/auth/me')->assertOk()->assertJsonPath('data.uid', $user->id);
        $this->getJson('/api/v1/shops')->assertForbidden();
    }

    public function test_signed_email_verification_rejects_forgery_and_then_refreshes_real_account(): void
    {
        $user = User::factory()->unverified()->create();
        $this->getJson('/api/v1/auth/email/verify/'.$user->id.'/'.sha1($user->email))->assertForbidden();
        $this->assertFalse($user->fresh()->hasVerifiedEmail());
        $url = URL::temporarySignedRoute('verification.verify', now()->addMinutes(10), ['id' => $user->id, 'hash' => sha1($user->email)]);
        $this->getJson($url)->assertOk();
        $this->assertTrue($user->fresh()->hasVerifiedEmail());
        $this->withToken($user->createToken('test')->plainTextToken)->getJson('/api/v1/auth/me')->assertJsonPath('data.emailVerified', true);
    }

    public function test_login_uses_hashed_password_and_logout_revokes_only_current_session(): void
    {
        $user = User::factory()->create(['email' => 'customer@example.test', 'password' => 'FoodPassword123']);
        $other = $user->createToken('other')->plainTextToken;
        $this->postJson('/api/v1/auth/login', ['email' => $user->email, 'password' => 'WrongPassword123'])->assertUnprocessable();
        $login = $this->postJson('/api/v1/auth/login', ['email' => 'CUSTOMER@EXAMPLE.TEST', 'password' => 'FoodPassword123', 'deviceName' => 'Android']);
        $login->assertOk()->assertJsonPath('data.user.uid', $user->id);
        $token = $login->json('data.token');
        $this->withToken($token)->postJson('/api/v1/auth/logout')->assertOk();
        Auth::forgetGuards();
        $this->withToken($token)->getJson('/api/v1/auth/me')->assertUnauthorized();
        Auth::forgetGuards();
        $this->withToken($other)->getJson('/api/v1/auth/me')->assertOk();
        $this->assertDatabaseCount('personal_access_tokens', 1);
    }

    public function test_imported_password_account_requires_reset_and_reset_revokes_all_sessions(): void
    {
        $user = User::factory()->unverified()->create(['id' => 'FirebaseLegacyId', 'password' => null, 'legacy_password_user' => true]);
        $this->postJson('/api/v1/auth/login', ['email' => $user->email, 'password' => 'OldFirebasePassword'])->assertUnprocessable();
        $oldToken = $user->createToken('old')->plainTextToken;
        $token = Password::createToken($user);
        $payload = ['email' => $user->email, 'token' => $token, 'password' => 'MigratedPassword123', 'password_confirmation' => 'MigratedPassword123'];
        $this->postJson('/api/v1/auth/password/reset', [...$payload, 'token' => 'invalid'])->assertUnprocessable();
        $this->postJson('/api/v1/auth/password/reset', $payload)->assertOk();
        $this->assertTrue($user->fresh()->hasVerifiedEmail());
        $this->assertTrue(Hash::check('MigratedPassword123', $user->fresh()->password));
        $this->assertDatabaseCount('personal_access_tokens', 0);
        $this->postJson('/api/v1/auth/password/reset', $payload)->assertUnprocessable();
        Auth::forgetGuards();
        $this->withToken($oldToken)->getJson('/api/v1/auth/me')->assertUnauthorized();
    }

    public function test_forgot_password_sends_real_notification_workflow_and_unknown_email_is_neutral(): void
    {
        $this->configureMail();
        Notification::fake();
        $user = User::factory()->create();
        $known = $this->postJson('/api/v1/auth/password/forgot', ['email' => $user->email])->assertOk();
        Notification::assertSentTo($user, ResetPassword::class, function (ResetPassword $notification) use ($user): bool {
            $url = $notification->toMail($user)->actionUrl;
            $this->assertStringContainsString('/password/reset/', $url);

            return Password::tokenExists($user, $notification->token);
        });
        $unknown = $this->postJson('/api/v1/auth/password/forgot', ['email' => 'unknown@example.test'])->assertOk();
        $this->assertSame($known->json('data'), $unknown->json('data'));
    }

    public function test_password_change_requires_current_secret_and_revokes_other_devices(): void
    {
        $user = User::factory()->create(['password' => 'CurrentPassword123']);
        $current = $user->createToken('current')->plainTextToken;
        $user->createToken('other');
        $payload = ['currentPassword' => 'wrong', 'newPassword' => 'ChangedPassword123', 'newPasswordConfirmation' => 'ChangedPassword123'];
        $this->withToken($current)->putJson('/api/v1/auth/password', $payload)->assertUnprocessable();
        $this->putJson('/api/v1/auth/password', [...$payload, 'currentPassword' => 'CurrentPassword123'])->assertOk();
        $this->assertTrue(Hash::check('ChangedPassword123', $user->fresh()->password));
        $this->assertDatabaseCount('personal_access_tokens', 1);
        Auth::forgetGuards();
        $this->withToken($current)->getJson('/api/v1/auth/me')->assertOk();
    }

    public function test_expired_tokens_and_disabled_imported_accounts_are_rejected(): void
    {
        $user = User::factory()->create(['password' => 'FoodPassword123']);
        $expired = $user->createToken('expired', ['*'], now()->subMinute())->plainTextToken;
        $this->withToken($expired)->getJson('/api/v1/auth/me')->assertUnauthorized();
        $user->forceFill(['disabled_at' => now()])->save();
        Auth::forgetGuards();
        $this->withToken($user->createToken('disabled')->plainTextToken)->getJson('/api/v1/auth/me')->assertForbidden();
        $this->postJson('/api/v1/auth/login', ['email' => $user->email, 'password' => 'FoodPassword123'])->assertUnprocessable();
    }

    public function test_verification_mail_failure_never_issues_a_success_token(): void
    {
        $this->configureMail();
        Notification::shouldReceive('send')->once()->andThrow(new \RuntimeException('SMTP unavailable'));
        $this->postJson('/api/v1/auth/register', $this->registration())->assertStatus(503)->assertJsonMissingPath('data.token');
        $this->assertDatabaseCount('users', 1);
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    /** @return array<string, string> */
    private function registration(): array
    {
        return ['name' => 'ลูกค้าทดสอบ', 'email' => 'customer@example.test', 'password' => 'FoodPassword123', 'password_confirmation' => 'FoodPassword123'];
    }

    private function configureMail(): void
    {
        config(['food.email_enabled' => true, 'mail.default' => 'smtp', 'mail.mailers.smtp.host' => 'smtp.example.test', 'mail.mailers.smtp.port' => 587, 'mail.from.address' => 'food@example.test']);
    }
}
