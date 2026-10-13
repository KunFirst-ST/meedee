<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Socialite\Facades\Socialite;
use Laravel\Socialite\Two\GoogleProvider;
use Laravel\Socialite\Two\User as GoogleUser;
use Mockery;
use Tests\TestCase;

class GoogleAuthTest extends TestCase
{
    use RefreshDatabase;

    private const VERIFIER = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';

    private const STATE = 'client_state_abcdefghijklmnopqrstuvwxyz0123456789';

    public function test_missing_google_configuration_is_explicit_and_never_creates_identity(): void
    {
        config(['services.google.client_id' => null, 'services.google.client_secret' => null]);
        $this->getJson('/api/v1/capabilities')->assertOk()->assertJsonPath('data.googleConfigured', false);
        $this->getJson('/api/v1/auth/google/start')->assertStatus(503);
        $this->assertDatabaseCount('users', 0);
    }

    public function test_oauth_start_rejects_unlisted_redirect_and_weak_pkce(): void
    {
        $this->configureGoogle();
        $params = $this->startParameters();
        $this->getJson('/api/v1/auth/google/start?'.http_build_query([...$params, 'redirectUri' => 'https://attacker.example/callback']))->assertUnprocessable();
        $this->getJson('/api/v1/auth/google/start?'.http_build_query([...$params, 'codeChallengeMethod' => 'plain']))->assertUnprocessable();
        $this->assertDatabaseCount('oauth_attempts', 0);
    }

    public function test_google_callback_returns_only_single_use_pkce_code_then_real_bearer_session(): void
    {
        $providerState = $this->startAttempt();
        $this->fakeGoogle('google-sub-123', 'customer@example.test', true);
        $callback = $this->get('/api/v1/auth/google/callback?'.http_build_query(['state' => $providerState, 'code' => 'google-code']));
        $callback->assertRedirect();
        $location = $callback->headers->get('Location');
        $this->assertStringStartsWith('msufood://auth/callback?', $location);
        $this->assertStringNotContainsString('token=', $location);
        parse_str(parse_url($location, PHP_URL_QUERY), $query);
        $this->assertSame(self::STATE, $query['state']);
        $this->assertArrayHasKey('code', $query);
        $this->assertDatabaseCount('personal_access_tokens', 0);
        $this->assertDatabaseHas('users', ['google_id' => 'google-sub-123', 'email' => 'customer@example.test', 'password' => null]);
        $payload = ['code' => $query['code'], 'state' => self::STATE, 'verifier' => self::VERIFIER];
        $this->postJson('/api/v1/auth/google/exchange', [...$payload, 'verifier' => str_repeat('wrong', 10)])->assertStatus(400);
        $this->postJson('/api/v1/auth/google/exchange', [...$payload, 'state' => str_repeat('wrong', 10)])->assertStatus(400);
        $session = $this->postJson('/api/v1/auth/google/exchange', $payload);
        $session->assertOk()->assertJsonPath('data.user.emailVerified', true)->assertJsonPath('data.user.providers', ['google']);
        $this->assertNotEmpty($session->json('data.token'));
        $this->postJson('/api/v1/auth/google/exchange', $payload)->assertStatus(400);
        $this->assertDatabaseCount('personal_access_tokens', 1);
        $this->get('/api/v1/auth/google/callback?'.http_build_query(['state' => $providerState, 'code' => 'replay']))->assertStatus(400);
    }

    public function test_callback_rejects_unknown_state_and_unverified_google_email(): void
    {
        $providerState = $this->startAttempt();
        $this->getJson('/api/v1/auth/google/callback?state=forged')->assertStatus(400);
        $this->fakeGoogle('unverified-sub', 'customer@example.test', false);
        $response = $this->get('/api/v1/auth/google/callback?'.http_build_query(['state' => $providerState, 'code' => 'google-code']));
        $this->assertStringContainsString('error=email_not_verified', $response->headers->get('Location'));
        $this->assertDatabaseCount('users', 0);
        $this->assertDatabaseCount('oauth_exchange_codes', 0);
    }

    public function test_google_never_implicitly_links_or_replaces_existing_password_account(): void
    {
        $existing = User::factory()->create(['email' => 'customer@example.test', 'password' => 'Password123']);
        $providerState = $this->startAttempt();
        $this->fakeGoogle('new-sub', $existing->email, true);
        $response = $this->get('/api/v1/auth/google/callback?'.http_build_query(['state' => $providerState, 'code' => 'google-code']));
        $this->assertStringContainsString('error=account_link_required', $response->headers->get('Location'));
        $this->assertNull($existing->fresh()->google_id);
        $this->assertDatabaseCount('users', 1);
        $this->assertDatabaseCount('oauth_exchange_codes', 0);
    }

    public function test_cancel_and_expired_attempt_never_issue_sessions(): void
    {
        $providerState = $this->startAttempt();
        $response = $this->get('/api/v1/auth/google/callback?'.http_build_query(['state' => $providerState, 'error' => 'access_denied']));
        $this->assertStringContainsString('error=cancelled', $response->headers->get('Location'));
        $this->assertDatabaseCount('users', 0);
        $this->assertDatabaseCount('personal_access_tokens', 0);
        $this->assertDatabaseCount('oauth_exchange_codes', 0);
        $this->travel(11)->minutes();
        DB::table('oauth_attempts')->where('state_hash', hash('sha256', $providerState))->update(['consumed_at' => null]);
        $this->getJson('/api/v1/auth/google/callback?state='.$providerState)->assertStatus(400);
    }

    public function test_imported_google_identity_preserves_ownership_and_expired_exchange_is_rejected(): void
    {
        $existing = User::factory()->create([
            'id' => 'FirebaseCaseSensitiveUID',
            'email' => 'merchant@example.test',
            'google_id' => 'imported-google-sub',
            'password' => null,
            'display_name' => 'ชื่อร้านเดิม',
            'role' => 'shop',
            'shop_id' => 'PreservedShopId',
            'legacy_firebase_uid' => 'FirebaseCaseSensitiveUID',
        ]);
        $providerState = $this->startAttempt();
        $this->fakeGoogle('imported-google-sub', $existing->email, true);
        $response = $this->get('/api/v1/auth/google/callback?'.http_build_query(['state' => $providerState, 'code' => 'google-code']));
        parse_str(parse_url($response->headers->get('Location'), PHP_URL_QUERY), $query);
        $this->assertDatabaseCount('users', 1);
        $this->assertDatabaseHas('oauth_exchange_codes', ['user_id' => 'FirebaseCaseSensitiveUID']);
        $this->assertSame('ชื่อร้านเดิม', $existing->fresh()->display_name);
        $this->assertSame('PreservedShopId', $existing->fresh()->shop_id);
        $this->travel(3)->minutes();
        $this->postJson('/api/v1/auth/google/exchange', ['code' => $query['code'], 'state' => self::STATE, 'verifier' => self::VERIFIER])->assertStatus(400);
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    /** @return array<string, string> */
    private function startParameters(): array
    {
        return ['redirectUri' => 'msufood://auth/callback', 'state' => self::STATE, 'codeChallenge' => rtrim(strtr(base64_encode(hash('sha256', self::VERIFIER, true)), '+/', '-_'), '='), 'codeChallengeMethod' => 'S256'];
    }

    private function startAttempt(): string
    {
        $this->configureGoogle();
        $response = $this->getJson('/api/v1/auth/google/start?'.http_build_query($this->startParameters()));
        $response->assertOk();
        parse_str(parse_url($response->json('data.url'), PHP_URL_QUERY), $query);
        $this->assertSame('test-client.apps.googleusercontent.com', $query['client_id']);
        $this->assertNotSame(self::STATE, $query['state']);

        return $query['state'];
    }

    private function configureGoogle(): void
    {
        config(['services.google.client_id' => 'test-client.apps.googleusercontent.com', 'services.google.client_secret' => 'test-secret', 'services.google.redirect' => 'https://api.example.test/api/v1/auth/google/callback', 'food.callback_uris' => ['msufood://auth/callback']]);
    }

    private function fakeGoogle(string $subject, string $email, bool $verified): void
    {
        $identity = (new GoogleUser)->setRaw(['sub' => $subject, 'email' => $email, 'email_verified' => $verified])->map(['id' => $subject, 'name' => 'Google Customer', 'email' => $email]);
        $provider = Mockery::mock(GoogleProvider::class);
        $provider->shouldReceive('stateless')->andReturnSelf();
        $provider->shouldReceive('user')->once()->andReturn($identity);
        Socialite::shouldReceive('driver')->with('google')->andReturn($provider);
    }
}
