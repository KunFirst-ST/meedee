<?php

use App\Http\Controllers\MenuController;
use App\Http\Controllers\OrderController;
use App\Http\Controllers\ProfileController;
use App\Http\Controllers\ShopController;
use App\Http\Middleware\RequireVerifiedFoodAccount;
use Illuminate\Support\Facades\Route;

// Included inside the /api/v1 group by routes/api.php. Keep verification in
// this group even if the caller accidentally includes it outside auth routes.
Route::middleware(['auth:sanctum', RequireVerifiedFoodAccount::class])->group(function () {
    Route::get('profile', [ProfileController::class, 'show']);
    Route::patch('profile', [ProfileController::class, 'update']);
    Route::post('profile/role', [ProfileController::class, 'role']);
    Route::delete('profile/role', [ProfileController::class, 'clearRole']);
    Route::get('shops', [ShopController::class, 'index']);
    Route::get('shops/{shopId}', [ShopController::class, 'show']);
    Route::get('shops/{shopId}/reviews', [ShopController::class, 'reviews']);
    Route::patch('shops/{shopId}', [ShopController::class, 'update']);
    Route::patch('shops/{shopId}/open', [ShopController::class, 'open']);
    Route::get('favorites', [ShopController::class, 'favorites']);
    Route::put('favorites/{shopId}', [ShopController::class, 'favorite']);
    Route::get('shops/{shopId}/menu', [MenuController::class, 'index']);
    Route::post('shops/{shopId}/menu', [MenuController::class, 'store']);
    Route::patch('menu/{menuId}', [MenuController::class, 'update']);
    Route::delete('menu/{menuId}', [MenuController::class, 'destroy']);
    Route::patch('menu/{menuId}/available', [MenuController::class, 'available']);
    Route::post('orders', [OrderController::class, 'store']);
    Route::post('orders/{orderId}/review', [OrderController::class, 'review'])->middleware('throttle:20,1');
    Route::get('orders', [OrderController::class, 'index']);
    Route::get('orders/{orderId}', [OrderController::class, 'show']);
    Route::get('shops/{shopId}/orders', [OrderController::class, 'shopOrders']);
    Route::post('orders/{orderId}/accept', [OrderController::class, 'accept']);
    Route::patch('orders/{orderId}/status', [OrderController::class, 'status']);
    Route::post('orders/{orderId}/cancel', [OrderController::class, 'cancel']);
});
