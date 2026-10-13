<?php

namespace App\Http\Controllers;

use App\Models\FoodOrder;
use App\Models\FoodOrderReview;
use App\Models\Shop;
use App\Services\BusinessRules;
use App\Services\OrderService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class OrderController extends Controller
{
    public function __construct(private readonly OrderService $orders) {}

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'shopId' => ['required', 'string', 'max:128', 'not_regex:/\//'],
            'requestId' => ['required', 'string', 'max:128', 'regex:/^[A-Za-z0-9_-]+$/D'],
            'note' => ['sometimes', 'nullable', 'string', 'max:500'],
            'items' => ['required', 'array', 'list', 'min:1', 'max:8'],
            'items.*' => ['required', 'array:menuItemId,qty,expectedPriceSatang'],
            'items.*.menuItemId' => ['required', 'string', 'max:128', 'distinct:strict', 'not_regex:/\//'],
            'items.*.qty' => ['required', 'integer', 'min:1', 'max:99'],
            'items.*.expectedPriceSatang' => ['required', 'integer', 'min:1', 'max:10000000'],
        ]);
        // Laravel's integer validation accepts digit strings. Convert validated
        // numeric values to exact integers before price checks and hashing.
        foreach ($data['items'] as &$line) {
            $line['qty'] = (int) $line['qty'];
            $line['expectedPriceSatang'] = (int) $line['expectedPriceSatang'];
        }
        unset($line);

        return response()->json(['data' => $this->orders->place($request->user(), $data)->toApiArray()], 201);
    }

    public function index(Request $request): JsonResponse
    {
        return response()->json(['data' => FoodOrder::query()->with(['items', 'review'])->where('customer_id', $request->user()->id)->orderByDesc('created_at')->get()->map(fn (FoodOrder $order) => $order->toApiArray())->all()]);
    }

    public function show(Request $request, string $orderId): JsonResponse
    {
        $order = FoodOrder::query()->with(['items', 'review'])->findOrFail($orderId);
        if ($order->customer_id !== $request->user()->id) {
            BusinessRules::owner($request->user(), Shop::findOrFail($order->shop_id));
        }

        return response()->json(['data' => $order->toApiArray()]);
    }

    public function review(Request $request, string $orderId): JsonResponse
    {
        $data = $request->validate([
            'rating' => ['required', 'integer', 'min:1', 'max:5'],
            'comment' => ['sometimes', 'nullable', 'string', 'max:500'],
        ]);

        $review = DB::transaction(function () use ($request, $orderId, $data): FoodOrderReview {
            $order = FoodOrder::query()->lockForUpdate()->findOrFail($orderId);
            abort_unless($order->customer_id === $request->user()->id, 403, 'เฉพาะผู้สั่งอาหารเท่านั้นที่รีวิวออเดอร์นี้ได้');
            abort_unless($order->status === 'completed', 409, 'รีวิวได้หลังจากรับอาหารเรียบร้อยแล้วเท่านั้น');
            abort_if($order->review()->exists(), 409, 'ออเดอร์นี้ส่งรีวิวแล้ว');

            return FoodOrderReview::query()->create([
                'food_order_id' => $order->id,
                'shop_id' => $order->shop_id,
                'customer_id' => $request->user()->id,
                'rating' => (int) $data['rating'],
                'comment' => isset($data['comment']) ? trim($data['comment']) : null,
            ]);
        }, 5);

        return response()->json(['data' => $review->toApiArray()], 201);
    }

    public function shopOrders(Request $request, string $shopId): JsonResponse
    {
        BusinessRules::owner($request->user(), Shop::findOrFail($shopId));
        $request->validate(['history' => ['sometimes', 'in:true,false,1,0']]);
        $history = $request->boolean('history');
        $query = FoodOrder::query()->with(['items', 'review'])->where('shop_id', $shopId);
        if (! $history) {
            $query->whereIn('status', FoodOrder::ACTIVE)->orderBy('created_at');
        } else {
            // Existing merchant history includes all actual receipts; completed
            // reports select completed status using updatedAt as pickup time.
            $query->orderByDesc('created_at');
        }

        return response()->json(['data' => $query->get()->map(fn (FoodOrder $order) => $order->toApiArray())->all()]);
    }

    public function accept(Request $request, string $orderId): JsonResponse
    {
        return response()->json(['data' => $this->orders->transition($request->user(), $orderId, 'pending', 'accepted')->toApiArray()]);
    }

    public function status(Request $request, string $orderId): JsonResponse
    {
        $data = $request->validate(['currentStatus' => ['required', 'in:pending,accepted,cooking,ready,completed,cancelled'], 'nextStatus' => ['required', 'in:accepted,cooking,ready,completed']]);

        return response()->json(['data' => $this->orders->transition($request->user(), $orderId, $data['currentStatus'], $data['nextStatus'])->toApiArray()]);
    }

    public function cancel(Request $request, string $orderId): JsonResponse
    {
        return response()->json(['data' => $this->orders->transition($request->user(), $orderId, 'pending', 'cancelled')->toApiArray()]);
    }
}
