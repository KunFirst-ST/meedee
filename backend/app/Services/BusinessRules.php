<?php

namespace App\Services;

use App\Models\Shop;
use App\Models\User;
use Illuminate\Validation\ValidationException;

class BusinessRules
{
    public const MAX_PRICE_SATANG = 10000000;

    public const MAX_IMAGE_BYTES = 200 * 1024;

    public static function invalid(string $field, string $message): never
    {
        throw ValidationException::withMessages([$field => [$message]]);
    }

    public static function customer(User $actor): void
    {
        self::enabled($actor);
        abort_unless($actor->role === 'customer', 403, 'กรุณาเลือกบทบาทลูกค้าก่อนสั่งอาหาร');
    }

    public static function owner(User $actor, Shop $shop): void
    {
        self::enabled($actor);
        abort_unless($actor->role === 'shop' && $shop->owner_id === $actor->id && $actor->shop_id === $shop->id, 403, 'เฉพาะเจ้าของร้านเท่านั้นที่ดำเนินการได้');
    }

    public static function enabled(User $actor): void
    {
        abort_if($actor->disabled_at !== null, 403, 'บัญชีนี้ถูกระงับ กรุณาติดต่อผู้ดูแล');
        abort_unless($actor->email_verified_at, 403, 'กรุณายืนยันอีเมลก่อนดำเนินการ');
    }

    public static function ready(Shop $shop): void
    {
        if (! is_string($shop->location) || trim($shop->location) === '') {
            self::invalid('location', 'กรุณาระบุจุดรับอาหารจริงในข้อมูลร้านก่อนเปิดรับออเดอร์');
        }
        if ($shop->preparation_minutes === null || $shop->preparation_minutes < 1 || $shop->preparation_minutes > 240) {
            self::invalid('preparationMinutes', 'กรุณาระบุเวลาเตรียมอาหารจริง 1–240 นาทีในข้อมูลร้าน');
        }
    }

    public static function text(mixed $value, string $field, int $maximum, bool $required = false): string
    {
        if (! is_string($value)) {
            self::invalid($field, 'กรุณากรอกข้อความให้ถูกต้อง');
        }
        $value = trim($value);
        if (($required && $value === '') || mb_strlen($value) > $maximum) {
            self::invalid($field, 'ข้อความต้องมี '.($required ? '1' : '0')."–{$maximum} ตัวอักษร");
        }

        return $value;
    }

    public static function price(array $data): int
    {
        if (array_key_exists('priceSatang', $data)) {
            $price = $data['priceSatang'];
            if (! is_int($price) || $price < 1 || $price > self::MAX_PRICE_SATANG) {
                self::invalid('priceSatang', 'ราคาอาหารต้องมากกว่า 0 และไม่เกิน 100,000 บาท');
            }
            if (array_key_exists('price', $data) && self::baht($data['price']) !== $price) {
                self::invalid('price', 'ราคาและจำนวนสตางค์ไม่ตรงกัน');
            }

            return $price;
        }
        if (! array_key_exists('price', $data)) {
            self::invalid('priceSatang', 'กรุณาระบุราคาอาหาร');
        }

        return self::baht($data['price']);
    }

    public static function baht(mixed $value, string $field = 'price'): int
    {
        if (! is_numeric($value) || is_bool($value) || ! is_finite((float) $value) || (float) $value <= 0 || (float) $value > 100000) {
            self::invalid($field, 'ราคาอาหารไม่ถูกต้อง');
        }
        $raw = (float) $value * 100;
        $satang = (int) round($raw);
        if (abs($raw - $satang) > 0.000001) {
            self::invalid($field, 'ราคาอาหารต้องมีทศนิยมไม่เกิน 2 ตำแหน่ง');
        }

        return $satang;
    }

    public static function image(mixed $encoded): ?string
    {
        if ($encoded === null || $encoded === '') {
            return null;
        }
        if (! is_string($encoded) || strlen($encoded) > 280000) {
            self::invalid('imageBase64', 'รูปภาพต้องมีขนาดไม่เกิน 200 KB');
        }
        $bytes = base64_decode($encoded, true);
        if ($bytes === false || strlen($bytes) > self::MAX_IMAGE_BYTES) {
            self::invalid('imageBase64', 'รูปภาพต้องเป็น Base64 ที่ถูกต้องและไม่เกิน 200 KB');
        }
        $info = @getimagesizefromstring($bytes);
        if ($info === false || ! in_array($info['mime'] ?? '', ['image/jpeg', 'image/png', 'image/webp', 'image/gif'], true) || $info[0] > 4096 || $info[1] > 4096) {
            self::invalid('imageBase64', 'กรุณาใช้รูป JPEG, PNG, WebP หรือ GIF ที่ถูกต้อง');
        }
        abort_unless(function_exists('imagecreatefromstring'), 503, 'เซิร์ฟเวอร์ยังไม่พร้อมตรวจรูปภาพ กรุณาติดต่อผู้ดูแล');
        $image = @imagecreatefromstring($bytes);
        if ($image === false) {
            self::invalid('imageBase64', 'ไฟล์รูปภาพเสียหายหรืออ่านภาพไม่ได้ กรุณาเลือกรูปใหม่');
        }
        imagedestroy($image);

        return base64_encode($bytes);
    }

    /** Sort distinct lines so the same cart can be safely retried in any UI order. */
    public static function requestHash(string $shopId, string $note, array $items): string
    {
        $lines = array_map(fn (array $line) => [
            'menuItemId' => $line['menuItemId'], 'qty' => $line['qty'], 'expectedPriceSatang' => $line['expectedPriceSatang'],
        ], $items);
        usort($lines, fn (array $left, array $right) => strcmp($left['menuItemId'], $right['menuItemId']));

        return hash('sha256', json_encode(['shopId' => $shopId, 'note' => $note, 'items' => $lines], JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }
}
