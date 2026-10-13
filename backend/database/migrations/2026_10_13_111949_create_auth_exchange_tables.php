<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('personal_access_tokens', function (Blueprint $table): void {
            $table->id();
            $table->string('tokenable_type');
            $tokenableId = $table->string('tokenable_id', 128);
            if (Schema::getConnection()->getDriverName() === 'mysql') {
                $tokenableId->collation('utf8mb4_bin');
            }
            $table->index(['tokenable_type', 'tokenable_id']);
            $table->string('name', 80);
            $table->string('token', 64)->unique();
            $table->text('abilities')->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable()->index();
            $table->timestamps();
        });

        Schema::create('oauth_attempts', function (Blueprint $table): void {
            $table->string('state_hash', 64)->primary();
            $table->string('client_state_hash', 64);
            $table->string('client_state', 128);
            $table->string('challenge', 43);
            $table->string('redirect_uri', 2048);
            $table->timestamp('expires_at')->index();
            $table->timestamp('consumed_at')->nullable();
            $table->timestamps();
        });

        Schema::create('oauth_exchange_codes', function (Blueprint $table): void {
            $table->string('code_hash', 64)->primary();
            $userId = $table->string('user_id', 128);
            if (Schema::getConnection()->getDriverName() === 'mysql') {
                $userId->collation('utf8mb4_bin');
            }
            $table->foreign('user_id')->references('id')->on('users')->cascadeOnDelete();
            $table->string('state_hash', 64);
            $table->string('challenge', 43);
            $table->timestamp('expires_at')->index();
            $table->timestamp('consumed_at')->nullable();
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('oauth_exchange_codes');
        Schema::dropIfExists('oauth_attempts');
        Schema::dropIfExists('personal_access_tokens');
    }
};
