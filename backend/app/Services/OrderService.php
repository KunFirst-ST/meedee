<?php

namespace App\Services;

use App\Models\FoodOrder;
use App\Models\MenuItem;
use App\Models\Shop;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class OrderService
{
    public function place(User $user, array $input): FoodOrder
    {
        $input['note'] = BusinessRules::text($input['note'] ?? '', 'note', 500);
        $fingerprint = BusinessRules::requestHash($input['shopId'], $input['note'], $input['items']);

        return DB::transaction(function () use ($user, $input, $fingerprint) {
            // Every checkout from one account serializes on its profile. The SQL
            // uniqueness constraint is a second guard against duplicate retries.
            $actor = User::query()->lockForUpdate()->findOrFail($user->id);
            abort_unless($actor->email_verified_at, 403, 'กรุณายืนยันอีเมลก่อนสั่งอาหาร');
            BusinessRules::customer($actor);
            $previous = FoodOrder::query()->where('customer_id', $actor->id)->where('request_id', $input['requestId'])->lockForUpdate()->first();
            if ($previous) {
                abort_unless($previous->request_hash !== null && hash_equals($previous->request_hash, $fingerprint), 409, 'คำขอสั่งอาหารเดิมมีข้อมูลต่างกัน กรุณาตรวจตะกร้าและสร้างคำขอใหม่');

                return $previous->load(['items', 'review']);
            }

            $shop = Shop::query()->lockForUpdate()->findOrFail($input['shopId']);
            if (! $shop->is_open) {
                BusinessRules::invalid('shopId', 'ร้านปิดรับออเดอร์แล้ว');
            }
            BusinessRules::ready($shop);
            $ids = array_column($input['items'], 'menuItemId');
            $menu = MenuItem::query()->whereIn('id', $ids)->orderBy('id')->lockForUpdate()->get()->keyBy('id');
            $lines = [];
            $total = 0;
            foreach ($input['items'] as $position => $line) {
                $item = $menu->get($line['menuItemId']);
                if (! $item || $item->shop_id !== $shop->id) {
                    BusinessRules::invalid('items', 'ไม่พบเมนูที่เลือกในร้านนี้ กรุณาตรวจสอบตะกร้า');
                }
                if (! $item->available) {
                    BusinessRules::invalid('items', "{$item->name} หมดแล้ว กรุณาปรับตะกร้า");
                }
                if ($item->price_satang !== $line['expectedPriceSatang']) {
                    BusinessRules::invalid('items', "ราคา {$item->name} เปลี่ยนแล้ว กรุณาตรวจสอบตะกร้าก่อนสั่งอีกครั้ง");
                }
                $total += $item->price_satang * $line['qty'];
                $lines[] = ['menu_item_id' => $item->id, 'position' => $position, 'name' => $item->name, 'price_satang' => $item->price_satang, 'qty' => $line['qty']];
            }
            $name = BusinessRules::text($actor->display_name, 'customerName', 120, true);
            $order = FoodOrder::create([
                'id' => (string) Str::uuid(), 'shop_id' => $shop->id, 'shop_name' => $shop->name,
                'customer_id' => $actor->id, 'customer_name' => $name, 'total_satang' => $total,
                'status' => 'pending', 'note' => $input['note'],
                'request_id' => $input['requestId'], 'request_hash' => $fingerprint,
            ]);
            $order->items()->createMany($lines);

            return $order->load(['items', 'review']);
        }, 5);
    }

    public function transition(User $user, string $orderId, string $current, string $next): FoodOrder
    {
        return DB::transaction(function () use ($user, $orderId, $current, $next) {
            $actor = User::query()->lockForUpdate()->findOrFail($user->id);
            BusinessRules::enabled($actor);
            abort_unless($actor->email_verified_at, 403, 'กรุณายืนยันอีเมลก่อนดำเนินการ');
            $reference = FoodOrder::findOrFail($orderId);
            $shop = Shop::query()->lockForUpdate()->findOrFail($reference->shop_id);
            $order = FoodOrder::query()->lockForUpdate()->findOrFail($orderId);
            if ($next === 'cancelled' && $order->customer_id === $actor->id) {
                // A customer may cancel their own pending purchase after a role
                // switch, but cannot change another customer's receipt.
            } else {
                BusinessRules::owner($actor, $shop);
            }
            abort_unless($order->status === $current, 409, 'สถานะออเดอร์เปลี่ยนแล้ว กรุณาตรวจสอบอีกครั้ง');
            $allowed = (FoodOrder::NEXT[$current] ?? null) === $next || ($current === 'pending' && $next === 'cancelled');
            abort_unless($allowed, 422, 'ไม่สามารถเปลี่ยนสถานะออเดอร์ได้');
            $order->update(['status' => $next]);

            return $order->load(['items', 'review']);
        }, 5);
    }
}
