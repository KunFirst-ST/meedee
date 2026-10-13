<?php

use App\Http\Controllers\Api\AuthController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return response()->json(['service' => 'MSU Food API', 'version' => 'v1']);
});

Route::get('/password/reset/{token}', [AuthController::class, 'resetPage'])->name('password.reset')->middleware(['secure.transport', 'throttle:20,1']);
Route::post('/password/reset', [AuthController::class, 'resetInBrowser'])->name('password.update')->middleware(['secure.transport', 'throttle:10,1']);
