<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Favorite extends Model
{
    public $incrementing = false;

    public $timestamps = false;

    protected $guarded = [];
}
