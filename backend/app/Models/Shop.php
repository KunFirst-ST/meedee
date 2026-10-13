<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Shop extends Model
{
    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected function casts(): array
    {
        return ['is_open' => 'boolean', 'preparation_minutes' => 'integer'];
    }

    public function reviews(): HasMany
    {
        return $this->hasMany(FoodOrderReview::class);
    }

    public function toApiArray(): array
    {
        return [
            'id' => $this->id, 'ownerId' => $this->owner_id, 'name' => $this->name,
            'isOpen' => $this->is_open, 'category' => $this->category,
            'description' => $this->description, 'location' => $this->location,
            'preparationMinutes' => $this->preparation_minutes,
            'ratingAverage' => $this->reviews_avg_rating === null ? null : round((float) $this->reviews_avg_rating, 1),
            'reviewCount' => (int) ($this->reviews_count ?? 0),
        ];
    }
}
