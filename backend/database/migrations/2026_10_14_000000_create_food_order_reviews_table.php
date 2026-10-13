<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('food_order_reviews', function (Blueprint $table): void {
            $table->collation = 'utf8mb4_bin';
            $table->id();
            $table->string('food_order_id', 128)->unique();
            $table->foreign('food_order_id')->references('id')->on('food_orders')->restrictOnDelete();
            $table->string('shop_id', 128);
            $table->foreign('shop_id')->references('id')->on('shops')->restrictOnDelete();
            $table->string('customer_id', 128);
            $table->foreign('customer_id')->references('id')->on('users')->restrictOnDelete();
            $table->unsignedTinyInteger('rating');
            $table->string('comment', 500)->nullable();
            $table->timestamps();
            $table->index(['shop_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('food_order_reviews');
    }
};
