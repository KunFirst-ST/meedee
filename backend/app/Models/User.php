<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Contracts\Auth\MustVerifyEmail;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable implements MustVerifyEmail
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, HasUuids, Notifiable;

    protected $keyType = 'string';

    public $incrementing = false;

    protected $fillable = ['id', 'display_name', 'email', 'password', 'phone', 'role', 'shop_id', 'email_verified_at', 'google_id', 'legacy_firebase_uid', 'legacy_password_user', 'disabled_at'];

    protected $hidden = ['password', 'remember_token', 'google_id'];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'legacy_password_user' => 'boolean',
            'disabled_at' => 'datetime',
        ];
    }

    /** @return array<string, mixed> */
    public function toApiArray(): array
    {
        $providers = [];
        if ($this->password !== null || $this->legacy_password_user) {
            $providers[] = 'password';
        }
        if ($this->google_id !== null) {
            $providers[] = 'google';
        }

        return [
            'uid' => (string) $this->id,
            'displayName' => $this->display_name,
            'email' => $this->email,
            'emailVerified' => $this->hasVerifiedEmail(),
            'phone' => $this->phone ?? '',
            'role' => $this->role,
            'shopId' => $this->shop_id,
            'providers' => $providers,
            'createdAt' => $this->created_at?->toISOString(),
            'updatedAt' => $this->updated_at?->toISOString(),
        ];
    }
}
