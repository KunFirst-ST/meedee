<?php

namespace App\Services;

use App\Models\User;

class TokenIssuer
{
    /** @return array{token: string, user: array<string, mixed>} */
    public function issue(User $user, string $deviceName = 'MSU Food'): array
    {
        $token = $user->createToken($deviceName, ['*'], now()->addDays((int) config('food.token_lifetime_days', 30)));

        return ['token' => $token->plainTextToken, 'user' => $user->toApiArray()];
    }
}
