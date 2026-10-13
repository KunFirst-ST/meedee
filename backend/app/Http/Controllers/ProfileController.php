<?php

namespace App\Http\Controllers;

use App\Models\Shop;
use App\Models\User;
use App\Services\BusinessRules;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class ProfileController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        return response()->json(['data' => $request->user()->fresh()->toApiArray()]);
    }

    public function update(Request $request): JsonResponse
    {
        $data = $request->validate(['displayName' => ['required', 'string', 'max:120'], 'phone' => ['present', 'nullable', 'string', 'max:40']]);
        $name = BusinessRules::text($data['displayName'], 'displayName', 120, true);
        $phone = preg_replace('/[\s()\-]/u', '', trim($data['phone'] ?? ''));
        if ($phone !== '' && ! preg_match('/^\+?[0-9]{8,15}$/D', $phone)) {
            BusinessRules::invalid('phone', 'กรอกเบอร์โทร 8–15 หลัก เช่น 0812345678 หรือ +66812345678');
        }
        $actor = $request->user();
        $actor->forceFill(['display_name' => $name, 'phone' => $phone])->save();

        return response()->json(['data' => $actor->fresh()->toApiArray()]);
    }

    public function role(Request $request): JsonResponse
    {
        $data = $request->validate(['role' => ['required', 'in:customer,shop'], 'shopName' => ['nullable', 'string', 'max:120']]);
        $actor = DB::transaction(function () use ($request, $data) {
            $actor = User::query()->lockForUpdate()->findOrFail($request->user()->id);
            BusinessRules::enabled($actor);
            // Find the persisted owner link, including imported accounts.
            $shop = $actor->shop_id ? Shop::query()->lockForUpdate()->find($actor->shop_id) : Shop::query()->where('owner_id', $actor->id)->lockForUpdate()->first();
            abort_if($actor->shop_id !== null && ! $shop, 409, 'ไม่พบร้านเดิมที่เชื่อมกับบัญชี กรุณาตรวจข้อมูลที่ย้ายก่อนสร้างร้านใหม่');
            abort_if($shop && $shop->owner_id !== $actor->id, 409, 'ข้อมูลบัญชีเชื่อมกับร้านที่ไม่ใช่ของคุณ กรุณาติดต่อผู้ดูแล');
            if ($data['role'] === 'shop') {
                if (! $shop) {
                    $shopName = BusinessRules::text($data['shopName'] ?? '', 'shopName', 120, true);
                    // UUID rather than a concatenation prevents IDs exceeding 128 characters.
                    $shop = Shop::create(['id' => (string) Str::uuid(), 'owner_id' => $actor->id, 'name' => $shopName, 'is_open' => false]);
                }
                $actor->shop_id = $shop->id;
            } elseif ($shop) {
                $shop->update(['is_open' => false]);
                $actor->shop_id = $shop->id;
            }
            $actor->role = $data['role'];
            $actor->save();

            return $actor;
        }, 5);

        return response()->json(['data' => $actor->toApiArray()]);
    }

    public function clearRole(Request $request): JsonResponse
    {
        $actor = DB::transaction(function () use ($request) {
            $actor = User::query()->lockForUpdate()->findOrFail($request->user()->id);
            BusinessRules::enabled($actor);
            $shop = Shop::query()->where('owner_id', $actor->id)->lockForUpdate()->first();
            if ($shop) {
                $shop->update(['is_open' => false]);
            }
            $actor->forceFill(['role' => null])->save();

            return $actor;
        }, 5);

        return response()->json(['data' => $actor->toApiArray()]);
    }
}
