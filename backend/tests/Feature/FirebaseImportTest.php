<?php

namespace Tests\Feature;

use App\Models\FoodOrder;
use App\Models\Shop;
use App\Models\User;
use App\Services\FirebaseImporter;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class FirebaseImportTest extends TestCase
{
    use RefreshDatabase;

    private array $temporaryFiles = [];

    protected function tearDown(): void
    {
        foreach ($this->temporaryFiles as $file) {
            if (is_file($file)) {
                unlink($file);
            }
        }
        parent::tearDown();
    }

    private function source(): array
    {
        $date = '2025-09-12T04:30:01Z';

        return [
            'schemaVersion' => 1, 'projectId' => 'msu-foodnaja', 'exportedAt' => '2026-10-13T10:00:00Z',
            'authUsers' => [
                ['uid' => 'legacy-merchant', 'email' => 'merchant@example.org', 'displayName' => 'Original owner', 'emailVerified' => true, 'createdAt' => $date, 'providerData' => [['providerId' => 'password', 'uid' => 'merchant@example.org']], 'passwordHash' => 'must-not-be-stored', 'salt' => 'must-not-be-stored'],
                ['uid' => 'legacy-customer', 'email' => 'customer@example.org', 'displayName' => 'Original customer', 'emailVerified' => true, 'createdAt' => $date, 'providerData' => [['providerId' => 'google.com', 'uid' => 'google-identity-123']]],
            ],
            'users' => [
                ['id' => 'legacy-merchant', 'data' => ['displayName' => 'ชื่อเจ้าของร้าน', 'role' => 'shop', 'shopId' => 'original-shop', 'createdAt' => $date, 'customField' => ['preserve' => true]]],
                ['id' => 'legacy-customer', 'data' => ['displayName' => 'ชื่อลูกค้า', 'phone' => '0812345678', 'role' => 'customer', 'createdAt' => $date]],
            ],
            'shops' => [['id' => 'original-shop', 'data' => ['name' => 'ร้านเดิม', 'ownerId' => 'legacy-merchant', 'isOpen' => true, 'location' => 'จุดรับจริง', 'preparationMinutes' => 10, 'createdAt' => $date, 'orderCount' => 90]]],
            'menuItems' => [['id' => 'original-menu', 'data' => ['name' => 'เมนูปัจจุบัน', 'shopId' => 'original-shop', 'price' => 50, 'available' => true, 'createdAt' => $date]]],
            'orders' => [['id' => 'original-order', 'data' => ['shopId' => 'original-shop', 'shopName' => 'ชื่อร้าน ณ วันที่ซื้อ', 'customerId' => 'legacy-customer', 'customerName' => 'ชื่อลูกค้า ณ วันที่ซื้อ', 'items' => [['menuItemId' => 'deleted-menu', 'name' => 'เมนูเดิมที่ลบไปแล้ว', 'price' => 45.50, 'qty' => 2]], 'total' => 91, 'status' => 'completed', 'note' => 'ต้นฉบับ', 'requestId' => 'legacy-request', 'createdAt' => $date, 'updatedAt' => '2025-09-12T04:50:01Z']]],
            'favorites' => [['userId' => 'legacy-customer', 'shopId' => 'original-shop', 'data' => ['shopId' => 'original-shop', 'createdAt' => $date]]],
            'documents' => [['path' => 'legacySettings/config', 'data' => ['unknownField' => 'preserve additional collection']]],
        ];
    }

    private function file(array $source): array
    {
        $file = tempnam(sys_get_temp_dir(), 'msu-import-');
        $bytes = json_encode($source, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
        file_put_contents($file, $bytes);
        $this->temporaryFiles[] = $file;

        return [$file, hash('sha256', $bytes)];
    }

    public function test_dry_run_reports_counts_without_writing_or_modifying_source(): void
    {
        [$file, $hash] = $this->file($this->source());
        $before = file_get_contents($file);
        $this->artisan('firebase:import', ['file' => $file])->expectsOutputToContain($hash)->assertSuccessful();
        $this->assertDatabaseCount('users', 0);
        $this->assertDatabaseCount('shops', 0);
        $this->assertDatabaseCount('firebase_import_batches', 0);
        $this->assertSame($before, file_get_contents($file));
    }

    public function test_commit_preserves_ids_ownership_historical_names_totals_timestamps_and_unknown_fields(): void
    {
        [$file, $hash] = $this->file($this->source());
        $this->artisan('firebase:import', ['file' => $file, '--commit' => true, '--expect-sha256' => $hash])->assertSuccessful();
        $this->assertDatabaseHas('shops', ['id' => 'original-shop', 'owner_id' => 'legacy-merchant', 'is_open' => true]);
        $this->assertDatabaseHas('users', ['id' => 'legacy-merchant', 'shop_id' => 'original-shop', 'password' => null, 'legacy_password_user' => true]);
        $this->assertDatabaseHas('users', ['id' => 'legacy-customer', 'google_id' => 'google-identity-123']);
        $order = FoodOrder::with('items')->findOrFail('original-order')->toApiArray();
        $this->assertSame('ชื่อร้าน ณ วันที่ซื้อ', $order['shopName']);
        $this->assertSame('ชื่อลูกค้า ณ วันที่ซื้อ', $order['customerName']);
        $this->assertSame('เมนูเดิมที่ลบไปแล้ว', $order['items'][0]['name']);
        $this->assertSame('deleted-menu', $order['items'][0]['menuItemId']);
        $this->assertSame(9100, $order['totalSatang']);
        $this->assertSame('2025-09-12T04:30:01+00:00', $order['createdAt']);
        $this->assertSame('2025-09-12T04:50:01+00:00', $order['updatedAt']);
        $archive = json_decode(DB::table('firebase_import_records')->where('document_path', 'users/legacy-merchant')->value('document_payload'), true);
        $this->assertTrue($archive['customField']['preserve']);
        $this->assertDatabaseHas('firebase_import_records', ['document_path' => 'legacySettings/config']);
        $auth = DB::table('firebase_import_records')->where('document_path', 'firebaseAuth/legacy-merchant')->value('document_payload');
        $this->assertStringNotContainsString('passwordHash', $auth);
        $this->assertStringNotContainsString('must-not-be-stored', $auth);
    }

    public function test_identical_import_is_idempotent_and_does_not_overwrite_later_live_edits(): void
    {
        $importer = app(FirebaseImporter::class);
        $prepared = $importer->prepare($this->source());
        $hash = hash('sha256', 'same source');
        $this->assertFalse($importer->commit($prepared, $hash)['alreadyImported']);
        Shop::findOrFail('original-shop')->update(['name' => 'ร้านแก้ข้อมูลหลังย้าย']);
        $this->assertTrue($importer->commit($prepared, $hash)['alreadyImported']);
        $this->assertDatabaseCount('users', 2);
        $this->assertDatabaseCount('food_orders', 1);
        $this->assertSame('ร้านแก้ข้อมูลหลังย้าย', Shop::findOrFail('original-shop')->name);
    }

    public function test_commit_requires_reviewed_source_hash_and_an_empty_target(): void
    {
        [$file, $hash] = $this->file($this->source());
        $this->artisan('firebase:import', ['file' => $file, '--commit' => true, '--expect-sha256' => str_repeat('0', 64)])->assertFailed();
        $this->assertDatabaseCount('users', 0);
        $existing = User::factory()->create();
        $this->artisan('firebase:import', ['file' => $file, '--commit' => true, '--expect-sha256' => $hash])->expectsOutputToContain('not empty')->assertFailed();
        $this->assertDatabaseCount('users', 1);
        $this->assertDatabaseCount('firebase_import_batches', 0);
        $this->assertDatabaseHas('users', ['id' => $existing->id]);
    }

    public function test_validation_rejects_foreign_owner_missing_identity_and_wrong_historical_total_before_any_writes(): void
    {
        foreach (['owner', 'identity', 'total', 'project'] as $case) {
            $source = $this->source();
            match ($case) {
                'owner' => $source['shops'][0]['data']['ownerId'] = 'unknown-owner',
                'identity' => $source['authUsers'] = [],
                'total' => $source['orders'][0]['data']['total'] = 1,
                'project' => $source['projectId'] = 'wrong-project',
            };
            [$file, $hash] = $this->file($source);
            $this->artisan('firebase:import', ['file' => $file, '--commit' => true, '--expect-sha256' => $hash])->assertFailed();
            $this->assertDatabaseCount('users', 0);
            $this->assertDatabaseCount('shops', 0);
            $this->assertDatabaseCount('food_orders', 0);
        }
    }

    public function test_database_failure_rolls_back_entire_batch_and_every_business_table(): void
    {
        $importer = app(FirebaseImporter::class);
        $prepared = $importer->prepare($this->source());
        $prepared['tables']['favorites'][0]['shop_id'] = 'foreign-key-does-not-exist';
        try {
            $importer->commit($prepared, hash('sha256', 'failed source'));
            $this->fail('Foreign-key failure must reject the transaction.');
        } catch (QueryException) {
            $this->assertDatabaseCount('users', 0);
            $this->assertDatabaseCount('shops', 0);
            $this->assertDatabaseCount('food_orders', 0);
            $this->assertDatabaseCount('firebase_import_batches', 0);
        }
    }

    public function test_imported_disabled_account_stays_disabled_and_cannot_use_business_api(): void
    {
        $source = $this->source();
        $source['authUsers'][1]['disabled'] = true;
        $importer = app(FirebaseImporter::class);
        $importer->commit($importer->prepare($source), hash('sha256', 'disabled source'));
        $user = User::findOrFail('legacy-customer');
        $this->assertNotNull($user->disabled_at);
        Sanctum::actingAs($user);
        $this->getJson('/api/v1/shops')->assertForbidden();
        $this->postJson('/api/v1/profile/role', ['role' => 'customer'])->assertForbidden();
    }

    public function test_legacy_receipts_without_menu_id_and_missing_dates_are_preserved_without_fake_values(): void
    {
        $source = $this->source();
        unset($source['orders'][0]['data']['items'][0]['menuItemId'], $source['orders'][0]['data']['createdAt'], $source['orders'][0]['data']['updatedAt']);
        $importer = app(FirebaseImporter::class);
        $importer->commit($importer->prepare($source), hash('sha256', 'missing dates source'));
        $receipt = FoodOrder::findOrFail('original-order')->toApiArray();
        $this->assertNull($receipt['createdAt']);
        $this->assertNull($receipt['updatedAt']);
        $this->assertNull($receipt['items'][0]['menuItemId']);
        $this->assertSame(9100, $receipt['totalSatang']);
    }

    public function test_conflicting_duplicate_document_archive_is_not_silently_dropped(): void
    {
        $source = $this->source();
        $source['documents'][] = ['path' => 'shops/original-shop', 'data' => ['name' => 'conflicting copy']];
        $this->expectException(ValidationException::class);
        app(FirebaseImporter::class)->prepare($source);
    }

    public function test_exporter_typed_raw_archive_preserves_precision_and_document_metadata(): void
    {
        $source = $this->source();
        $data = $source['shops'][0]['data'];
        $raw = [...$data, 'orderCount' => ['__firestoreType' => 'integer', 'value' => '90'], 'customLocation' => ['__firestoreType' => 'geoPoint', 'latitude' => 16.2, 'longitude' => 103.3]];
        $timestamp = ['__firestoreType' => 'timestamp', '_seconds' => 1757651401, '_nanoseconds' => 123456789];
        $source['documents'][] = ['path' => 'shops/original-shop', 'data' => $data, 'rawData' => $raw, 'createTime' => $timestamp, 'updateTime' => $timestamp];
        $importer = app(FirebaseImporter::class);
        $importer->commit($importer->prepare($source), hash('sha256', 'typed source'));
        $archive = json_decode(DB::table('firebase_import_records')->where('document_path', 'shops/original-shop')->value('document_payload'), true);
        $this->assertSame('90', $archive['fields']['orderCount']['value']);
        $this->assertSame('geoPoint', $archive['fields']['customLocation']['__firestoreType']);
        $this->assertSame(123456789, $archive['createTime']['_nanoseconds']);
        $this->assertDatabaseHas('shops', ['id' => 'original-shop', 'owner_id' => 'legacy-merchant']);
    }
}
