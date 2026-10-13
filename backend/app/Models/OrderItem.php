<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class OrderItem extends Model
{
    public $timestamps = false;

    protected $guarded = [];

    protected function casts(): array
    {
        return ['price_satang' => 'integer', 'qty' => 'integer', 'position' => 'integer'];
    }

    public function toApiArray(): array
    {
        return ['menuItemId' => $this->menu_item_id, 'name' => $this->name, 'price' => $this->price_satang / 100, 'qty' => $this->qty];
    }
}
