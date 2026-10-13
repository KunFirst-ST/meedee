<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\Relations\HasMany;

class FoodOrder extends Model
{
    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    public const ACTIVE = ['pending', 'accepted', 'cooking', 'ready'];

    public const STATUSES = ['pending', 'accepted', 'cooking', 'ready', 'completed', 'cancelled'];

    public const NEXT = ['pending' => 'accepted', 'accepted' => 'cooking', 'cooking' => 'ready', 'ready' => 'completed'];

    protected function casts(): array
    {
        return ['total_satang' => 'integer'];
    }

    public function items(): HasMany
    {
        return $this->hasMany(OrderItem::class)->orderBy('position');
    }

    public function review(): HasOne
    {
        return $this->hasOne(FoodOrderReview::class, 'food_order_id');
    }

    public function toApiArray(): array
    {
        return [
            'id' => $this->id, 'shopId' => $this->shop_id, 'shopName' => $this->shop_name,
            'customerId' => $this->customer_id, 'customerName' => $this->customer_name,
            'items' => $this->items->map(fn (OrderItem $item) => $item->toApiArray())->all(),
            'total' => $this->total_satang / 100, 'totalSatang' => $this->total_satang,
            'status' => $this->status, 'note' => $this->note,
            'createdAt' => $this->created_at?->utc()->toIso8601String(),
            'updatedAt' => $this->updated_at?->utc()->toIso8601String(),
            'review' => $this->relationLoaded('review') ? $this->review?->toApiArray() : null,
        ];
    }
}
