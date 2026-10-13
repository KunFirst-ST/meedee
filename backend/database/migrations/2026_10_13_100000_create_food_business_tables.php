<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('shops', function (Blueprint $table) {
            $table->collation = 'utf8mb4_bin';
            $table->string('id', 128)->primary();
            $table->string('owner_id', 128)->unique();
            $table->foreign('owner_id')->references('id')->on('users')->restrictOnDelete();
            $table->string('name', 120);
            $table->boolean('is_open')->default(false);
            $table->string('category', 80)->nullable();
            $table->string('description', 500)->nullable();
            $table->string('location', 200)->nullable();
            $table->unsignedSmallInteger('preparation_minutes')->nullable();
            $table->timestamps();
            $table->index('name');
        });
        Schema::create('menu_items', function (Blueprint $table) {
            $table->collation = 'utf8mb4_bin';
            $table->string('id', 128)->primary();
            $table->string('shop_id', 128);
            $table->foreign('shop_id')->references('id')->on('shops')->restrictOnDelete();
            $table->string('name', 120);
            $table->unsignedInteger('price_satang');
            $table->boolean('available')->default(true);
            $table->mediumText('image_base64')->nullable();
            $table->string('category', 80)->nullable();
            $table->string('description', 500)->nullable();
            $table->timestamps();
            $table->index(['shop_id', 'name']);
        });
        Schema::create('food_orders', function (Blueprint $table) {
            $table->collation = 'utf8mb4_bin';
            $table->string('id', 128)->primary();
            $table->string('shop_id', 128);
            $table->foreign('shop_id')->references('id')->on('shops')->restrictOnDelete();
            $table->string('customer_id', 128);
            $table->foreign('customer_id')->references('id')->on('users')->restrictOnDelete();
            $table->string('shop_name', 120);
            $table->string('customer_name', 120);
            $table->unsignedBigInteger('total_satang');
            $table->string('status', 16);
            $table->string('note', 500)->default('');
            $table->string('request_id', 128)->nullable();
            $table->char('request_hash', 64)->nullable();
            $table->timestamps();
            $table->unique(['customer_id', 'request_id']);
            $table->index(['shop_id', 'status', 'created_at']);
            $table->index(['customer_id', 'created_at']);
        });
        Schema::create('order_items', function (Blueprint $table) {
            $table->collation = 'utf8mb4_bin';
            $table->bigIncrements('id');
            $table->string('food_order_id', 128);
            $table->foreign('food_order_id')->references('id')->on('food_orders')->restrictOnDelete();
            // A purchased receipt survives deletion of its current menu item.
            $table->string('menu_item_id', 128)->nullable();
            $table->unsignedSmallInteger('position');
            $table->string('name', 120);
            $table->unsignedInteger('price_satang');
            $table->unsignedSmallInteger('qty');
            $table->unique(['food_order_id', 'position']);
        });
        Schema::create('favorites', function (Blueprint $table) {
            $table->collation = 'utf8mb4_bin';
            $table->string('user_id', 128);
            $table->foreign('user_id')->references('id')->on('users')->restrictOnDelete();
            $table->string('shop_id', 128);
            $table->foreign('shop_id')->references('id')->on('shops')->restrictOnDelete();
            $table->timestamp('created_at')->nullable();
            $table->primary(['user_id', 'shop_id']);
        });
        Schema::create('firebase_import_batches', function (Blueprint $table) {
            $table->id();
            $table->char('source_sha256', 64)->unique();
            $table->string('project_id', 128);
            $table->json('counts');
            $table->timestamp('imported_at');
        });
        Schema::create('firebase_import_records', function (Blueprint $table) {
            $table->id();
            $table->foreignId('batch_id')->constrained('firebase_import_batches')->restrictOnDelete();
            $table->text('document_path');
            $table->char('path_hash', 64)->unique();
            $table->char('source_hash', 64);
            // Preserve original business fields not yet represented by SQL columns.
            // Authentication password hashes/salts are never copied here.
            $table->json('document_payload');
        });
    }

    public function down(): void
    {
        foreach (['firebase_import_records', 'firebase_import_batches', 'favorites', 'order_items', 'food_orders', 'menu_items', 'shops'] as $table) {
            Schema::dropIfExists($table);
        }
    }
};
