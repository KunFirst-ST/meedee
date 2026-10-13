<?php

namespace App\Http\Controllers;

use App\Models\MenuItem;
use App\Models\Shop;
use App\Models\User;
use App\Services\BusinessRules;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class MenuController extends Controller
{
    public function index(string $shopId): JsonResponse
    {
        Shop::findOrFail($shopId);

        return response()->json(['data' => MenuItem::query()->where('shop_id', $shopId)->orderBy('name')->get()->map(fn (MenuItem $item) => $item->toApiArray())->all()]);
    }

    private function input(Request $request, bool $creating): array
    {
        $data = $request->validate([
            'name' => [$creating ? 'required' : 'sometimes', 'required', 'string', 'max:120'],
            'priceSatang' => ['sometimes', 'integer', 'min:1', 'max:10000000'],
            'price' => ['sometimes', 'numeric', 'gt:0', 'max:100000'],
            'imageBase64' => ['sometimes', 'nullable', 'string', 'max:280000'],
            'removeImage' => ['sometimes', 'boolean'],
            'category' => ['sometimes', 'nullable', 'string', 'max:80'],
            'description' => ['sometimes', 'nullable', 'string', 'max:500'],
        ]);
        $result = [];
        foreach (['name' => 120, 'category' => 80, 'description' => 500] as $field => $maximum) {
            if (array_key_exists($field, $data)) {
                $result[$field] = BusinessRules::text($data[$field] ?? '', $field, $maximum, $field === 'name');
            }
        }
        if ($creating || array_key_exists('price', $data) || array_key_exists('priceSatang', $data)) {
            $result['price_satang'] = BusinessRules::price($data);
        }
        if (array_key_exists('imageBase64', $data)) {
            $result['image_base64'] = BusinessRules::image($data['imageBase64']);
        } elseif ($data['removeImage'] ?? false) {
            $result['image_base64'] = null;
        }

        return $result;
    }

    public function store(Request $request, string $shopId): JsonResponse
    {
        $data = $this->input($request, true);
        $item = DB::transaction(function () use ($request, $shopId, $data) {
            $actor = User::query()->lockForUpdate()->findOrFail($request->user()->id);
            $shop = Shop::query()->lockForUpdate()->findOrFail($shopId);
            BusinessRules::owner($actor, $shop);

            return MenuItem::create(['id' => (string) Str::uuid(), 'shop_id' => $shopId, 'available' => true, ...$data]);
        }, 5);

        return response()->json(['data' => $item->toApiArray()], 201);
    }

    private function mutate(Request $request, string $menuId, callable $change): JsonResponse
    {
        $item = DB::transaction(function () use ($request, $menuId, $change) {
            $actor = User::query()->lockForUpdate()->findOrFail($request->user()->id);
            $reference = MenuItem::query()->findOrFail($menuId);
            $shop = Shop::query()->lockForUpdate()->findOrFail($reference->shop_id);
            BusinessRules::owner($actor, $shop);
            $item = MenuItem::query()->lockForUpdate()->findOrFail($menuId);
            $change($item);

            return $item;
        }, 5);

        return response()->json(['data' => $item->exists ? $item->toApiArray() : ['deleted' => true, 'id' => $menuId]]);
    }

    public function update(Request $request, string $menuId): JsonResponse
    {
        $data = $this->input($request, false);

        return $this->mutate($request, $menuId, fn (MenuItem $item) => $item->update($data));
    }

    public function available(Request $request, string $menuId): JsonResponse
    {
        $data = $request->validate(['available' => ['required', 'boolean']]);

        return $this->mutate($request, $menuId, fn (MenuItem $item) => $item->update(['available' => $data['available']]));
    }

    public function destroy(Request $request, string $menuId): JsonResponse
    {
        return $this->mutate($request, $menuId, fn (MenuItem $item) => $item->delete());
    }
}
