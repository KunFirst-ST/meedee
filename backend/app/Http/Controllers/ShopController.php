<?php

namespace App\Http\Controllers;

use App\Models\Favorite;
use App\Models\FoodOrderReview;
use App\Models\Shop;
use App\Models\User;
use App\Services\BusinessRules;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ShopController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(['data' => Shop::query()->withAvg('reviews', 'rating')->withCount('reviews')->orderBy('name')->get()->map(fn (Shop $shop) => $shop->toApiArray())->all()]);
    }

    public function show(string $shopId): JsonResponse
    {
        return response()->json(['data' => Shop::query()->withAvg('reviews', 'rating')->withCount('reviews')->findOrFail($shopId)->toApiArray()]);
    }

    public function reviews(Request $request, string $shopId): JsonResponse
    {
        $request->validate(['page' => ['sometimes', 'integer', 'min:1']]);
        $shop = Shop::query()->withAvg('reviews', 'rating')->findOrFail($shopId);
        $reviews = $shop->reviews()
            ->with('customer:id,display_name')
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate(20);

        return response()->json(['data' => [
            'items' => $reviews->getCollection()->map(fn (FoodOrderReview $review) => $review->toShopApiArray())->all(),
            'currentPage' => $reviews->currentPage(),
            'lastPage' => $reviews->lastPage(),
            'total' => $reviews->total(),
            'ratingAverage' => $shop->reviews_avg_rating === null ? null : round((float) $shop->reviews_avg_rating, 1),
        ]]);
    }

    public function update(Request $request, string $shopId): JsonResponse
    {
        $data = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:120'],
            'description' => ['sometimes', 'nullable', 'string', 'max:500'],
            'category' => ['sometimes', 'nullable', 'string', 'max:80'],
            'location' => ['sometimes', 'nullable', 'string', 'max:200'],
            'preparationMinutes' => ['sometimes', 'integer', 'min:1', 'max:240'],
        ]);
        $shop = DB::transaction(function () use ($request, $shopId, $data) {
            $actor = User::query()->lockForUpdate()->findOrFail($request->user()->id);
            $shop = Shop::query()->lockForUpdate()->findOrFail($shopId);
            BusinessRules::owner($actor, $shop);
            foreach (['name' => 120, 'description' => 500, 'category' => 80, 'location' => 200] as $field => $maximum) {
                if (array_key_exists($field, $data)) {
                    $shop->{$field} = BusinessRules::text($data[$field] ?? '', $field, $maximum, $field === 'name');
                }
            }
            if (array_key_exists('preparationMinutes', $data)) {
                $shop->preparation_minutes = $data['preparationMinutes'];
            }
            if ($shop->is_open) {
                BusinessRules::ready($shop);
            }
            $shop->save();

            return $shop;
        }, 5);

        return response()->json(['data' => $shop->toApiArray()]);
    }

    public function open(Request $request, string $shopId): JsonResponse
    {
        $data = $request->validate(['isOpen' => ['required', 'boolean']]);
        $shop = DB::transaction(function () use ($request, $shopId, $data) {
            $actor = User::query()->lockForUpdate()->findOrFail($request->user()->id);
            $shop = Shop::query()->lockForUpdate()->findOrFail($shopId);
            BusinessRules::owner($actor, $shop);
            if ($data['isOpen']) {
                BusinessRules::ready($shop);
            }
            $shop->update(['is_open' => $data['isOpen']]);

            return $shop;
        }, 5);

        return response()->json(['data' => $shop->toApiArray()]);
    }

    public function favorites(Request $request): JsonResponse
    {
        return response()->json(['data' => Favorite::query()->where('user_id', $request->user()->id)->orderBy('shop_id')->pluck('shop_id')->all()]);
    }

    public function favorite(Request $request, string $shopId): JsonResponse
    {
        $data = $request->validate(['favorite' => ['required', 'boolean']]);
        Shop::findOrFail($shopId);
        if ($data['favorite']) {
            DB::table('favorites')->insertOrIgnore(['user_id' => $request->user()->id, 'shop_id' => $shopId, 'created_at' => now()]);
        } else {
            DB::table('favorites')->where('user_id', $request->user()->id)->where('shop_id', $shopId)->delete();
        }

        return $this->favorites($request);
    }
}
