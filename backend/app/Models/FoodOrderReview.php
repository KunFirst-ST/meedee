<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class FoodOrderReview extends Model
{
    protected $guarded = [];

    protected function casts(): array
    {
        return ['rating' => 'integer'];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(FoodOrder::class, 'food_order_id');
    }

    public function shop(): BelongsTo
    {
        return $this->belongsTo(Shop::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'customer_id');
    }

    public function toApiArray(): array
    {
        return [
            'rating' => $this->rating,
            'comment' => $this->comment,
            'createdAt' => $this->created_at?->utc()->toIso8601String(),
        ];
    }

    /** @return array{id: int, rating: int, comment: ?string, createdAt: ?string, customerName: string} */
    public function toShopApiArray(): array
    {
        $displayName = trim($this->customer?->display_name ?? '');
        $customerName = $displayName === '' || str_contains($displayName, '@')
            ? 'ลูกค้า'
            : preg_split('/\s+/u', $displayName, 2)[0];

        return [
            'id' => (int) $this->id,
            ...$this->toApiArray(),
            'customerName' => $customerName,
        ];
    }
}
