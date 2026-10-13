<?php

namespace Tests\Feature;

use App\Models\MenuItem;
use App\Models\Shop;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class FoodBusinessTest extends TestCase
{
    use RefreshDatabase;

    private function signIn(User $user): void
    {
        Sanctum::actingAs($user->fresh());
    }

    /** @return array{User, string, string, string} */
    private function readyMerchant(): array
    {
        $merchant = User::factory()->create(['role' => null, 'display_name' => 'เจ้าของร้านจริง']);
        $this->signIn($merchant);
        $shopId = $this->postJson('/api/v1/profile/role', ['role' => 'shop', 'shopName' => 'ร้านอาหาร'])->assertOk()->json('data.shopId');
        $this->patchJson("/api/v1/shops/{$shopId}", ['location' => 'จุดรับหน้าร้าน', 'preparationMinutes' => 15])->assertOk();
        $this->patchJson("/api/v1/shops/{$shopId}/open", ['isOpen' => true])->assertOk();
        $first = $this->postJson("/api/v1/shops/{$shopId}/menu", ['name' => 'ข้าวผัด', 'priceSatang' => 4550])->assertCreated()->json('data.id');
        $second = $this->postJson("/api/v1/shops/{$shopId}/menu", ['name' => 'ไข่ดาว', 'priceSatang' => 1000])->assertCreated()->json('data.id');

        return [$merchant->fresh(), $shopId, $first, $second];
    }

    private function customer(): User
    {
        return User::factory()->create(['role' => 'customer', 'display_name' => 'ชื่อลูกค้าจากฐานข้อมูล']);
    }

    private function cart(string $shopId, string $first, string $second, string $requestId = 'same-cart'): array
    {
        return ['shopId' => $shopId, 'requestId' => $requestId, 'note' => ' ไม่เผ็ด ', 'items' => [
            ['menuItemId' => $first, 'qty' => 2, 'expectedPriceSatang' => 4550],
            ['menuItemId' => $second, 'qty' => 1, 'expectedPriceSatang' => 1000],
        ]];
    }

    public function test_customer_and_merchant_complete_a_real_canonical_receipt(): void
    {
        [$merchant, $shop, $first, $second] = $this->readyMerchant();
        $customer = $this->customer();
        $this->signIn($customer);
        $this->freezeSecond();
        $payload = $this->cart($shop, $first, $second);
        $order = $this->postJson('/api/v1/orders', [...$payload, 'customerName' => 'spoof', 'total' => 1])->assertCreated()->assertJsonPath('data.customerName', $customer->display_name)->assertJsonPath('data.totalSatang', 10100)->assertJsonPath('data.items.0.name', 'ข้าวผัด')->assertJsonPath('data.note', 'ไม่เผ็ด')->json('data');
        $this->assertSame(now()->toIso8601String(), $order['createdAt']);
        $this->getJson('/api/v1/orders')->assertOk()->assertJsonCount(1, 'data');
        $this->signIn($merchant);
        $this->getJson("/api/v1/shops/{$shop}/orders?history=false")->assertOk()->assertJsonCount(1, 'data');
        $this->postJson("/api/v1/orders/{$order['id']}/accept")->assertOk()->assertJsonPath('data.status', 'accepted');
        $this->postJson("/api/v1/orders/{$order['id']}/accept")->assertConflict();
        foreach (['accepted' => 'cooking', 'cooking' => 'ready', 'ready' => 'completed'] as $from => $to) {
            $this->travel(1)->seconds();
            $this->patchJson("/api/v1/orders/{$order['id']}/status", ['currentStatus' => $from, 'nextStatus' => $to])->assertOk()->assertJsonPath('data.status', $to)->assertJsonPath('data.updatedAt', now()->toIso8601String());
        }
        $this->getJson("/api/v1/shops/{$shop}/orders?history=false")->assertOk()->assertJsonCount(0, 'data');
        $this->getJson("/api/v1/shops/{$shop}/orders?history=true")->assertOk()->assertJsonCount(1, 'data');
        $this->deleteJson("/api/v1/menu/{$first}")->assertOk();
        $this->signIn($customer);
        $this->getJson("/api/v1/orders/{$order['id']}")->assertOk()->assertJsonPath('data.items.0.name', 'ข้าวผัด')->assertJsonPath('data.totalSatang', 10100);
        $this->postJson("/api/v1/orders/{$order['id']}/cancel")->assertConflict();
    }

    public function test_idempotent_retry_returns_original_after_price_or_shop_changes_and_rejects_changed_payload(): void
    {
        [$merchant, $shop, $first, $second] = $this->readyMerchant();
        $customer = $this->customer();
        $payload = $this->cart($shop, $first, $second);
        $this->signIn($customer);
        $id = $this->postJson('/api/v1/orders', $payload)->assertCreated()->json('data.id');
        $this->signIn($merchant);
        $this->patchJson("/api/v1/menu/{$first}", ['priceSatang' => 9000])->assertOk();
        $this->patchJson("/api/v1/shops/{$shop}/open", ['isOpen' => false])->assertOk();
        $this->signIn($customer);
        $reordered = $payload;
        $reordered['items'] = array_reverse($payload['items']);
        $this->postJson('/api/v1/orders', $reordered)->assertCreated()->assertJsonPath('data.id', $id)->assertJsonPath('data.totalSatang', 10100);
        $this->postJson('/api/v1/orders', [...$payload, 'note' => 'changed'])->assertConflict();
        $changed = $payload;
        $changed['items'][0]['qty'] = 3;
        $this->postJson('/api/v1/orders', $changed)->assertConflict();
        $this->assertDatabaseCount('food_orders', 1);
        $this->assertDatabaseCount('order_items', 2);
    }

    public function test_checkout_rejects_stale_unavailable_foreign_menu_and_closed_shop_atomically(): void
    {
        [$merchant, $shop, $first, $second] = $this->readyMerchant();
        $customer = $this->customer();
        $payload = $this->cart($shop, $first, $second);
        $this->signIn($customer);
        $stale = $payload;
        $stale['items'][0]['expectedPriceSatang'] = 4500;
        $this->postJson('/api/v1/orders', $stale)->assertUnprocessable()->assertJsonValidationErrors('items');
        $this->signIn($merchant);
        $this->patchJson("/api/v1/menu/{$second}/available", ['available' => false])->assertOk();
        $this->signIn($customer);
        $this->postJson('/api/v1/orders', $payload)->assertUnprocessable();
        $this->signIn($merchant);
        $this->patchJson("/api/v1/shops/{$shop}/open", ['isOpen' => false])->assertOk();
        $this->signIn($customer);
        $this->postJson('/api/v1/orders', $payload)->assertUnprocessable();
        $this->assertDatabaseCount('food_orders', 0);
        $this->assertDatabaseCount('order_items', 0);
        [, $otherShop] = $this->readyMerchant();
        $this->signIn($customer);
        $this->postJson('/api/v1/orders', [...$payload, 'shopId' => $otherShop])->assertUnprocessable();
    }

    public function test_cross_account_reads_mutations_and_status_jumps_are_denied(): void
    {
        [$merchant, $shop, $first, $second] = $this->readyMerchant();
        $customer = $this->customer();
        $this->signIn($customer);
        $id = $this->postJson('/api/v1/orders', $this->cart($shop, $first, $second))->assertCreated()->json('data.id');
        $this->postJson("/api/v1/orders/{$id}/accept")->assertForbidden();
        $this->signIn($this->customer());
        $this->getJson("/api/v1/orders/{$id}")->assertForbidden();
        $this->getJson('/api/v1/orders')->assertOk()->assertJsonCount(0, 'data');
        $this->getJson("/api/v1/shops/{$shop}/orders")->assertForbidden();
        $this->patchJson("/api/v1/shops/{$shop}", ['name' => 'stolen'])->assertForbidden();
        $this->patchJson("/api/v1/menu/{$first}", ['priceSatang' => 1])->assertForbidden();
        $this->deleteJson("/api/v1/menu/{$first}")->assertForbidden();
        $this->postJson("/api/v1/orders/{$id}/cancel")->assertForbidden();
        $this->signIn($merchant);
        $this->patchJson("/api/v1/orders/{$id}/status", ['currentStatus' => 'pending', 'nextStatus' => 'completed'])->assertUnprocessable();
        $this->signIn($customer);
        $this->postJson("/api/v1/orders/{$id}/cancel")->assertOk()->assertJsonPath('data.status', 'cancelled');
        $this->signIn($merchant);
        $this->postJson("/api/v1/orders/{$id}/accept")->assertConflict();
    }

    public function test_unverified_disabled_and_anonymous_accounts_cannot_use_business_routes(): void
    {
        $this->getJson('/api/v1/shops')->assertUnauthorized();
        $this->getJson('/api/v1/shops/missing/reviews')->assertUnauthorized();
        $this->signIn(User::factory()->unverified()->create());
        $this->getJson('/api/v1/shops')->assertForbidden();
        $this->getJson('/api/v1/shops/missing/reviews')->assertForbidden();
        $this->postJson('/api/v1/profile/role', ['role' => 'shop', 'shopName' => 'blocked'])->assertForbidden();
        $this->signIn(User::factory()->create(['disabled_at' => now()]));
        $this->getJson('/api/v1/shops')->assertForbidden();
        $this->getJson('/api/v1/shops/missing/reviews')->assertForbidden();
        $this->assertDatabaseCount('shops', 0);
    }

    public function test_role_switch_closes_and_reuses_the_same_owned_shop_and_preserves_history(): void
    {
        [$merchant, $shop] = $this->readyMerchant();
        $this->signIn($merchant);
        $this->postJson('/api/v1/profile/role', ['role' => 'customer'])->assertOk()->assertJsonPath('data.shopId', $shop);
        $this->assertFalse(Shop::findOrFail($shop)->is_open);
        $this->patchJson("/api/v1/shops/{$shop}/open", ['isOpen' => true])->assertForbidden();
        $this->postJson('/api/v1/profile/role', ['role' => 'shop', 'shopName' => 'must not overwrite'])->assertOk()->assertJsonPath('data.shopId', $shop);
        $this->assertSame('ร้านอาหาร', Shop::findOrFail($shop)->name);
        $this->assertDatabaseCount('shops', 1);
        $this->deleteJson('/api/v1/profile/role')->assertOk()->assertJsonPath('data.role', null)->assertJsonPath('data.shopId', $shop);
        $this->assertDatabaseCount('menu_items', 2);
    }

    public function test_shop_readiness_profile_validation_and_protected_fields(): void
    {
        $merchant = User::factory()->create();
        $this->signIn($merchant);
        $shop = $this->postJson('/api/v1/profile/role', ['role' => 'shop', 'shopName' => 'ร้าน'])->assertOk()->json('data.shopId');
        $this->patchJson("/api/v1/shops/{$shop}/open", ['isOpen' => true])->assertUnprocessable()->assertJsonValidationErrors('location');
        $this->patchJson("/api/v1/shops/{$shop}", ['location' => 'หน้าร้าน'])->assertOk();
        $this->patchJson("/api/v1/shops/{$shop}/open", ['isOpen' => true])->assertUnprocessable()->assertJsonValidationErrors('preparationMinutes');
        $this->patchJson("/api/v1/shops/{$shop}", ['preparationMinutes' => 241])->assertUnprocessable();
        $this->patchJson("/api/v1/shops/{$shop}", ['preparationMinutes' => 1])->assertOk();
        $this->patchJson("/api/v1/shops/{$shop}/open", ['isOpen' => true])->assertOk();
        $this->patchJson("/api/v1/shops/{$shop}", ['location' => ' '])->assertUnprocessable();
        $this->patchJson('/api/v1/profile', ['displayName' => ' '.str_repeat('ก', 120).' ', 'phone' => '+66 (81) 234-5678', 'email' => 'takeover@example.com', 'role' => 'customer'])->assertOk()->assertJsonPath('data.phone', '+66812345678')->assertJsonPath('data.email', $merchant->email)->assertJsonPath('data.role', 'shop');
        $this->patchJson('/api/v1/profile', ['displayName' => ' ', 'phone' => '123'])->assertUnprocessable();
        $this->assertSame('หน้าร้าน', Shop::findOrFail($shop)->location);
    }

    public function test_cart_limits_and_exact_satang_are_validated_without_partial_orders(): void
    {
        [, $shop, $first, $second] = $this->readyMerchant();
        $this->signIn($this->customer());
        $payload = $this->cart($shop, $first, $second);
        foreach ([0, 100, 1.5] as $qty) {
            $invalid = $payload;
            $invalid['items'][0]['qty'] = $qty;
            $this->postJson('/api/v1/orders', $invalid)->assertUnprocessable();
        }
        $invalid = $payload;
        $invalid['items'][1] = $invalid['items'][0];
        $this->postJson('/api/v1/orders', $invalid)->assertUnprocessable();
        $invalid['items'] = array_fill(0, 9, $payload['items'][0]);
        $this->postJson('/api/v1/orders', $invalid)->assertUnprocessable();
        $this->postJson('/api/v1/orders', [...$payload, 'note' => str_repeat('a', 501)])->assertUnprocessable();
        $this->assertDatabaseCount('food_orders', 0);
    }

    public function test_menu_image_validation_preserves_actual_raster_and_rejects_svg_or_oversize(): void
    {
        [, $shop, $first] = $this->readyMerchant();
        $image = imagecreatetruecolor(1, 1);
        ob_start();
        imagepng($image);
        $png = base64_encode(ob_get_clean());
        imagedestroy($image);
        $this->patchJson("/api/v1/menu/{$first}", ['imageBase64' => $png])->assertOk()->assertJsonPath('data.imageBase64', $png);
        $this->patchJson("/api/v1/menu/{$first}", ['imageBase64' => base64_encode('<svg xmlns="http://www.w3.org/2000/svg"></svg>')])->assertUnprocessable();
        $this->patchJson("/api/v1/menu/{$first}", ['imageBase64' => base64_encode(substr(base64_decode($png), 0, 33))])->assertUnprocessable();
        $this->patchJson("/api/v1/menu/{$first}", ['imageBase64' => base64_encode(str_repeat('x', 204801))])->assertUnprocessable();
        $this->assertSame($png, MenuItem::findOrFail($first)->image_base64);
        $this->patchJson("/api/v1/menu/{$first}", ['removeImage' => true])->assertOk()->assertJsonPath('data.imageBase64', null);
        $this->postJson("/api/v1/shops/{$shop}/menu", ['name' => 'invalid', 'price' => 12.345])->assertUnprocessable();
        $this->assertDatabaseCount('menu_items', 2);
    }

    public function test_favorites_are_self_scoped_and_unknown_shops_do_not_create_records(): void
    {
        [, $shop] = $this->readyMerchant();
        $customer = $this->customer();
        $this->signIn($customer);
        $this->putJson("/api/v1/favorites/{$shop}", ['favorite' => true])->assertOk()->assertJsonPath('data.0', $shop);
        $this->putJson("/api/v1/favorites/{$shop}", ['favorite' => true])->assertOk();
        $this->assertDatabaseCount('favorites', 1);
        $this->signIn($this->customer());
        $this->getJson('/api/v1/favorites')->assertOk()->assertExactJson(['data' => []]);
        $this->putJson('/api/v1/favorites/missing', ['favorite' => true])->assertNotFound();
        $this->signIn($customer);
        $this->putJson("/api/v1/favorites/{$shop}", ['favorite' => false])->assertOk()->assertExactJson(['data' => []]);
    }

    public function test_only_the_customer_can_review_a_completed_order_and_shop_rating_uses_saved_reviews(): void
    {
        [$merchant, $shop, $first, $second] = $this->readyMerchant();
        $customer = $this->customer();
        $this->signIn($customer);
        $orderId = $this->postJson('/api/v1/orders', $this->cart($shop, $first, $second))->assertCreated()->json('data.id');
        $this->postJson("/api/v1/orders/{$orderId}/review", ['rating' => 5, 'comment' => ''])->assertConflict();

        $outsider = $this->customer();
        $this->signIn($outsider);
        $otherOrderId = $this->postJson('/api/v1/orders', $this->cart($shop, $first, $second, 'other-customer-order'))->assertCreated()->json('data.id');
        $this->postJson("/api/v1/orders/{$orderId}/review", ['rating' => 5])->assertForbidden();

        $this->signIn($merchant);
        foreach ([$orderId, $otherOrderId] as $receiptId) {
            $this->postJson("/api/v1/orders/{$receiptId}/accept")->assertOk();
            foreach (['accepted' => 'cooking', 'cooking' => 'ready', 'ready' => 'completed'] as $current => $next) {
                $this->patchJson("/api/v1/orders/{$receiptId}/status", ['currentStatus' => $current, 'nextStatus' => $next])->assertOk();
            }
        }

        $this->signIn($outsider);
        $this->postJson("/api/v1/orders/{$otherOrderId}/review", ['rating' => 3, 'comment' => 'พอใช้'])->assertCreated();

        $this->signIn($customer);
        $this->postJson("/api/v1/orders/{$orderId}/review", ['rating' => 5, 'comment' => ' อร่อยมาก '])
            ->assertCreated()
            ->assertJsonPath('data.rating', 5)
            ->assertJsonPath('data.comment', 'อร่อยมาก');
        $this->postJson("/api/v1/orders/{$orderId}/review", ['rating' => 4])->assertConflict();
        $this->postJson("/api/v1/orders/{$orderId}/review", ['rating' => 0])->assertUnprocessable();
        $this->getJson("/api/v1/orders/{$orderId}")->assertOk()->assertJsonPath('data.review.rating', 5);
        $this->assertDatabaseCount('food_order_reviews', 2);

        $shopResponse = $this->getJson("/api/v1/shops/{$shop}")->assertOk();
        $this->assertEquals(4, $shopResponse->json('data.ratingAverage'));
        $this->assertSame(2, $shopResponse->json('data.reviewCount'));
        $this->signIn($merchant);
        $this->getJson("/api/v1/shops/{$shop}/orders?history=true")
            ->assertOk()
            ->assertJsonFragment(['rating' => 5, 'comment' => 'อร่อยมาก']);
    }

    public function test_corrupt_shop_link_never_grants_ownership(): void
    {
        [, $shop] = $this->readyMerchant();
        $outsider = User::factory()->create(['role' => null, 'shop_id' => $shop]);
        $this->signIn($outsider);
        $this->postJson('/api/v1/profile/role', ['role' => 'shop', 'shopName' => 'steal'])->assertConflict();
        $this->assertNull($outsider->fresh()->role);
        $this->assertDatabaseCount('shops', 1);
    }
}
