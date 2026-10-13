<?php

use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\GoogleAuthController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function (): void {
    Route::get('/capabilities', [AuthController::class, 'capabilities']);
    Route::post('/auth/register', [AuthController::class, 'register'])->middleware('throttle:5,1');
    Route::post('/auth/login', [AuthController::class, 'login'])->middleware('throttle:auth-login');
    Route::post('/auth/password/forgot', [AuthController::class, 'forgotPassword'])->middleware('throttle:5,1');
    Route::post('/auth/password/reset', [AuthController::class, 'resetPassword'])->middleware('throttle:10,1');
    Route::get('/auth/email/verify/{id}/{hash}', [AuthController::class, 'verifyEmail'])->middleware(['signed', 'throttle:10,1'])->name('verification.verify');
    Route::get('/auth/google/start', [GoogleAuthController::class, 'start'])->middleware('throttle:10,1');
    Route::get('/auth/google/callback', [GoogleAuthController::class, 'callback'])->middleware('throttle:30,1')->name('google.callback');
    Route::post('/auth/google/exchange', [GoogleAuthController::class, 'exchange'])->middleware('throttle:10,1');

    Route::middleware(['auth:sanctum', 'account.enabled'])->group(function (): void {
        Route::get('/auth/me', [AuthController::class, 'me']);
        Route::post('/auth/logout', [AuthController::class, 'logout']);
        Route::post('/auth/email/resend', [AuthController::class, 'resendVerification'])->middleware('throttle:3,1');
        Route::put('/auth/password', [AuthController::class, 'changePassword'])->middleware('throttle:5,1');
    });

    require __DIR__.'/business.php';
});
