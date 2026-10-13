<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MenuItem extends Model
{
    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected function casts(): array
    {
        return ['available' => 'boolean', 'price_satang' => 'integer'];
    }

    public function toApiArray(): array
    {
        return [
            'id' => $this->id, 'shopId' => $this->shop_id, 'name' => $this->name,
            'price' => $this->price_satang / 100, 'priceSatang' => $this->price_satang,
            'available' => $this->available, 'imageBase64' => $this->image_base64,
            'description' => $this->description, 'category' => $this->category,
        ];
    }
}
