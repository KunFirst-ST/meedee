<?php

namespace App\Services;

use App\Models\FoodOrder;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class FirebaseImporter
{
    private array $records = [];

    /** Validate the complete source before any database write. */
    public function prepare(array $source): array
    {
        $this->records = [];
        Validator::make($source, [
            'schemaVersion' => ['required', 'integer', 'in:1'], 'projectId' => ['required', 'in:msu-foodnaja'],
            'authUsers' => ['present', 'array'], 'users' => ['present', 'array'], 'shops' => ['present', 'array'],
            'menuItems' => ['present', 'array'], 'orders' => ['present', 'array'], 'favorites' => ['present', 'array'], 'documents' => ['sometimes', 'array'],
        ])->validate();
        foreach (['authUsers', 'users', 'shops', 'menuItems', 'orders', 'favorites', 'documents'] as $section) {
            if (isset($source[$section]) && ! array_is_list($source[$section])) {
                BusinessRules::invalid($section, 'Export sections must be JSON lists.');
            }
        }
        $users = [];
        $emails = [];
        $identities = [];
        foreach ($source['authUsers'] as $row) {
            $id = $this->id($row['uid'] ?? null, 'authUsers.uid');
            $email = mb_strtolower(trim($row['email'] ?? ''));
            if (isset($users[$id]) || ! filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 254 || isset($emails[$email])) {
                BusinessRules::invalid('authUsers', "Duplicate UID or missing/invalid/duplicate email for {$id}; no placeholder user will be created.");
            }
            $emails[$email] = true;
            $googleId = null;
            $password = false;
            foreach ($row['providerData'] ?? [] as $provider) {
                if (($provider['providerId'] ?? null) === 'google.com') {
                    $googleId = $this->id($provider['uid'] ?? null, 'providerData.uid');
                } elseif (($provider['providerId'] ?? null) === 'password') {
                    $password = true;
                } else {
                    BusinessRules::invalid('authUsers', "Unsupported identity provider for {$id}; review before migrating.");
                }
            }
            if ($googleId && isset($identities[$googleId])) {
                BusinessRules::invalid('authUsers', 'Duplicate Google provider identity.');
            }
            if ($googleId) {
                $identities[$googleId] = true;
            }
            $created = $this->timestamp($row['createdAt'] ?? $row['metadata']['creationTime'] ?? null, 'authUsers.createdAt');
            if (! is_bool($row['emailVerified'] ?? false)) {
                BusinessRules::invalid('authUsers.emailVerified', 'Email verification must be a boolean.');
            }
            $verifiedAt = ($row['emailVerified'] ?? false) ? $this->timestamp($row['emailVerifiedAt'] ?? $created, 'emailVerifiedAt') : null;
            if (($row['emailVerified'] ?? false) && $verifiedAt === null) {
                BusinessRules::invalid('authUsers', "Verified identity {$id} needs its actual verification or creation timestamp.");
            }
            if (! is_bool($row['disabled'] ?? false)) {
                BusinessRules::invalid('authUsers.disabled', 'Disabled status must be a boolean.');
            }
            $disabledAt = ($row['disabled'] ?? false) ? $this->timestamp($row['disabledAt'] ?? $source['exportedAt'] ?? null, 'authUsers.disabledAt') : null;
            if (($row['disabled'] ?? false) && $disabledAt === null) {
                BusinessRules::invalid('authUsers.disabledAt', 'Disabled accounts require disabledAt or the actual exportedAt observation timestamp.');
            }
            $users[$id] = [
                'id' => $id, 'email' => $email, 'display_name' => BusinessRules::text($row['displayName'] ?? '', 'displayName', 120),
                'phone' => null, 'role' => null, 'shop_id' => null, 'password' => null, 'legacy_password_user' => $password,
                'google_id' => $googleId, 'legacy_firebase_uid' => $id, 'email_verified_at' => $verifiedAt,
                'disabled_at' => $disabledAt,
                'created_at' => $created, 'updated_at' => $this->timestamp($row['updatedAt'] ?? null, 'authUsers.updatedAt'),
            ];
            // Keep identity metadata while excluding hashes, salts and tokens.
            $this->record('firebaseAuth/'.$id, array_intersect_key($row, array_flip(['uid', 'email', 'emailVerified', 'displayName', 'phoneNumber', 'photoURL', 'providerData', 'customClaims', 'tenantId', 'lastSignInAt', 'lastRefreshAt', 'createdAt', 'updatedAt', 'emailVerifiedAt', 'metadata', 'disabled'])));
        }
        foreach ($this->documents($source['users'], 'users') as $id => $data) {
            if (! isset($users[$id])) {
                BusinessRules::invalid('users', "Profile {$id} has no exported Auth identity. Import Auth users too; no fake user is created.");
            }
            $role = ($data['role'] ?? null) === 'unassigned' ? null : ($data['role'] ?? null);
            $phone = $data['phone'] ?? '';
            if (! in_array($role, [null, 'customer', 'shop'], true) || ! is_string($phone) || ($phone !== '' && ! preg_match('/^\+?[0-9]{8,15}$/D', $phone))) {
                BusinessRules::invalid('users', "Invalid saved role or phone for {$id}.");
            }
            $users[$id] = [...$users[$id],
                'display_name' => BusinessRules::text($data['displayName'] ?? $users[$id]['display_name'], 'displayName', 120),
                'phone' => $phone, 'role' => $role, 'shop_id' => isset($data['shopId']) ? $this->id($data['shopId'], 'users.shopId') : null,
                'created_at' => $this->timestamp($data['createdAt'] ?? $users[$id]['created_at'], 'users.createdAt'),
                'updated_at' => $this->timestamp($data['updatedAt'] ?? $users[$id]['updated_at'], 'users.updatedAt'),
            ];
        }
        $shops = [];
        $owners = [];
        foreach ($this->documents($source['shops'], 'shops') as $id => $data) {
            $owner = $this->id($data['ownerId'] ?? null, 'shops.ownerId');
            if (! isset($users[$owner]) || isset($owners[$owner]) || ! is_bool($data['isOpen'] ?? null)) {
                BusinessRules::invalid('shops', "Shop {$id} has a missing/duplicate owner or invalid open state.");
            }
            $owners[$owner] = true;
            $minutes = $data['preparationMinutes'] ?? null;
            if ($minutes !== null && (! is_int($minutes) || $minutes < 1 || $minutes > 240)) {
                BusinessRules::invalid('shops.preparationMinutes', "Invalid preparation time for {$id}.");
            }
            $shops[$id] = [
                'id' => $id, 'owner_id' => $owner, 'name' => BusinessRules::text($data['name'] ?? '', 'shops.name', 120, true), 'is_open' => $data['isOpen'],
                'description' => BusinessRules::text($data['description'] ?? '', 'shops.description', 500), 'category' => BusinessRules::text($data['category'] ?? '', 'shops.category', 80),
                'location' => BusinessRules::text($data['location'] ?? '', 'shops.location', 200), 'preparation_minutes' => $minutes,
                'created_at' => $this->timestamp($data['createdAt'] ?? null, 'shops.createdAt'), 'updated_at' => $this->timestamp($data['updatedAt'] ?? null, 'shops.updatedAt'),
            ];
        }
        foreach ($users as $id => $user) {
            $link = $user['shop_id'];
            if (($link !== null && (! isset($shops[$link]) || $shops[$link]['owner_id'] !== $id)) || ($user['role'] === 'shop' && $link === null)) {
                BusinessRules::invalid('users.shopId', "User {$id} has an invalid or missing owner link.");
            }
        }
        $menus = [];
        foreach ($this->documents($source['menuItems'], 'menuItems') as $id => $data) {
            $shopId = $this->id($data['shopId'] ?? null, 'menuItems.shopId');
            if (! isset($shops[$shopId]) || ! is_bool($data['available'] ?? null)) {
                BusinessRules::invalid('menuItems', "Menu {$id} has a missing shop or invalid availability.");
            }
            $menus[$id] = [
                'id' => $id, 'shop_id' => $shopId, 'name' => BusinessRules::text($data['name'] ?? '', 'menuItems.name', 120, true),
                'price_satang' => BusinessRules::price($data), 'available' => $data['available'], 'image_base64' => BusinessRules::image($data['imageBase64'] ?? null),
                'description' => BusinessRules::text($data['description'] ?? '', 'menuItems.description', 500), 'category' => BusinessRules::text($data['category'] ?? '', 'menuItems.category', 80),
                'created_at' => $this->timestamp($data['createdAt'] ?? null, 'menuItems.createdAt'), 'updated_at' => $this->timestamp($data['updatedAt'] ?? null, 'menuItems.updatedAt'),
            ];
        }
        $orders = [];
        $items = [];
        $requests = [];
        foreach ($this->documents($source['orders'], 'orders') as $id => $data) {
            $shopId = $this->id($data['shopId'] ?? null, 'orders.shopId');
            $customerId = $this->id($data['customerId'] ?? null, 'orders.customerId');
            if (! isset($shops[$shopId]) || ! isset($users[$customerId]) || ! in_array($data['status'] ?? null, FoodOrder::STATUSES, true) || ! is_array($data['items'] ?? null) || ! array_is_list($data['items']) || count($data['items']) < 1) {
                BusinessRules::invalid('orders', "Order {$id} has a missing shop/customer, invalid status or empty receipt.");
            }
            $requestId = $data['requestId'] ?? null;
            $key = $customerId.'/'.($requestId ?? '');
            if ($requestId !== null && (! is_string($requestId) || ! preg_match('/^[A-Za-z0-9_-]{1,128}$/D', $requestId) || isset($requests[$key]))) {
                BusinessRules::invalid('orders.requestId', "Invalid or duplicate idempotency key for {$id}.");
            }
            $requests[$key] = true;
            $note = BusinessRules::text($data['note'] ?? '', 'orders.note', 500);
            $total = 0;
            $fingerprint = [];
            $canFingerprint = true;
            foreach ($data['items'] as $position => $line) {
                if (! is_int($line['qty'] ?? null) || $line['qty'] < 1 || $line['qty'] > 99 || $position > 65535) {
                    BusinessRules::invalid('orders.items.qty', "Invalid receipt quantity in {$id}.");
                }
                $satang = BusinessRules::baht($line['price'] ?? null, 'orders.items.price');
                $menuId = isset($line['menuItemId']) ? $this->id($line['menuItemId'], 'orders.items.menuItemId') : null;
                $total += $satang * $line['qty'];
                $items[] = ['food_order_id' => $id, 'menu_item_id' => $menuId, 'position' => $position, 'name' => BusinessRules::text($line['name'] ?? '', 'orders.items.name', 120, true), 'price_satang' => $satang, 'qty' => $line['qty']];
                if ($menuId === null) {
                    $canFingerprint = false;
                } else {
                    $fingerprint[] = ['menuItemId' => $menuId, 'qty' => $line['qty'], 'expectedPriceSatang' => $satang];
                }
            }
            if (! is_numeric($data['total'] ?? null) || abs((float) $data['total'] * 100 - $total) > 0.000001) {
                BusinessRules::invalid('orders.total', "Receipt {$id} total differs from historical lines; no recalculation is silently saved.");
            }
            $orders[$id] = [
                'id' => $id, 'shop_id' => $shopId, 'customer_id' => $customerId,
                'shop_name' => BusinessRules::text($data['shopName'] ?? '', 'orders.shopName', 120, true), 'customer_name' => BusinessRules::text($data['customerName'] ?? '', 'orders.customerName', 120, true),
                'status' => $data['status'], 'note' => $note, 'total_satang' => $total, 'request_id' => $requestId,
                'request_hash' => $requestId && $canFingerprint ? BusinessRules::requestHash($shopId, $note, $fingerprint) : null,
                'created_at' => $this->timestamp($data['createdAt'] ?? null, 'orders.createdAt'), 'updated_at' => $this->timestamp($data['updatedAt'] ?? null, 'orders.updatedAt'),
            ];
        }
        $favorites = [];
        foreach ($source['favorites'] as $row) {
            $userId = $this->id($row['userId'] ?? null, 'favorites.userId');
            $shopId = $this->id($row['shopId'] ?? null, 'favorites.shopId');
            $key = $userId.'/'.$shopId;
            if (! isset($users[$userId]) || ! isset($shops[$shopId]) || isset($favorites[$key])) {
                BusinessRules::invalid('favorites', "Favorite {$key} is duplicate or references a missing user/shop.");
            }
            $data = $row['data'] ?? [];
            $favorites[$key] = ['user_id' => $userId, 'shop_id' => $shopId, 'created_at' => $this->timestamp($data['createdAt'] ?? null, 'favorites.createdAt')];
            $this->record("users/{$userId}/favorites/{$shopId}", $data);
        }
        foreach ($source['documents'] ?? [] as $row) {
            $path = $row['path'] ?? null;
            if (! is_string($path) || $path === '' || strlen($path) > 2048 || ! is_array($row['data'] ?? null) || str_starts_with($path, 'firebaseAuth/')) {
                BusinessRules::invalid('documents', 'Invalid additional Firestore document path or payload.');
            }
            if (array_key_exists('rawData', $row) && ! is_array($row['rawData'])) {
                BusinessRules::invalid('documents.rawData', 'Raw Firestore field archive must be an object.');
            }
            $rawArchive = array_key_exists('rawData', $row) ? ['fields' => $row['rawData'], 'createTime' => $row['createTime'] ?? null, 'updateTime' => $row['updateTime'] ?? null] : null;
            $this->record($path, $row['data'], $rawArchive);
        }

        return [
            'projectId' => $source['projectId'],
            'tables' => ['users' => array_values($users), 'shops' => array_values($shops), 'menu_items' => array_values($menus), 'food_orders' => array_values($orders), 'order_items' => $items, 'favorites' => array_values($favorites)],
            'records' => array_values($this->records),
            'counts' => ['users' => count($users), 'shops' => count($shops), 'menuItems' => count($menus), 'orders' => count($orders), 'orderItems' => count($items), 'favorites' => count($favorites), 'archivedDocuments' => count($this->records)],
        ];
    }

    public function commit(array $prepared, string $sha256): array
    {
        return DB::transaction(function () use ($prepared, $sha256) {
            $previous = DB::table('firebase_import_batches')->where('source_sha256', $sha256)->lockForUpdate()->first();
            if ($previous) {
                return ['alreadyImported' => true, 'counts' => json_decode($previous->counts, true, 512, JSON_THROW_ON_ERROR)];
            }
            foreach (array_keys($prepared['tables']) as $table) {
                if (DB::table($table)->exists()) {
                    BusinessRules::invalid('database', "Target table {$table} is not empty. Import never overwrites live data; use a dedicated empty database.");
                }
            }
            if (DB::table('firebase_import_batches')->exists()) {
                BusinessRules::invalid('database', 'A different source was already imported. Merge requires review.');
            }
            $batch = DB::table('firebase_import_batches')->insertGetId(['source_sha256' => $sha256, 'project_id' => $prepared['projectId'], 'counts' => json_encode($prepared['counts'], JSON_THROW_ON_ERROR), 'imported_at' => now()]);
            foreach ($prepared['tables'] as $table => $rows) {
                foreach (array_chunk($rows, 100) as $chunk) {
                    DB::table($table)->insert($chunk);
                }
            }
            foreach ($prepared['records'] as $record) {
                DB::table('firebase_import_records')->insert(['batch_id' => $batch, ...$record]);
            }

            return ['alreadyImported' => false, 'counts' => $prepared['counts']];
        }, 5);
    }

    private function documents(array $rows, string $collection): array
    {
        $documents = [];
        foreach ($rows as $row) {
            $id = $this->id($row['id'] ?? null, "{$collection}.id");
            if (isset($documents[$id]) || ! is_array($row['data'] ?? null)) {
                BusinessRules::invalid($collection, "Duplicate or invalid document {$id}.");
            }
            $documents[$id] = $row['data'];
            $this->record($collection.'/'.$id, $row['data']);
        }

        return $documents;
    }

    private function id(mixed $value, string $field): string
    {
        if (! is_string($value) || $value === '' || mb_strlen($value) > 128 || str_contains($value, '/') || preg_match('/[\x00-\x1f\x7f]/', $value)) {
            BusinessRules::invalid($field, 'Imported IDs must be strings of 1–128 characters without slashes or control characters.');
        }

        return $value;
    }

    private function timestamp(mixed $value, string $field): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }
        if (is_array($value)) {
            if (isset($value['timestampValue'])) {
                $value = $value['timestampValue'];
            } elseif (isset($value['_seconds']) || isset($value['seconds'])) {
                $seconds = $value['_seconds'] ?? $value['seconds'];
                if (! is_numeric($seconds)) {
                    BusinessRules::invalid($field, 'Invalid Firebase timestamp seconds.');
                }

                return CarbonImmutable::createFromTimestampUTC((float) $seconds)->format('Y-m-d H:i:s');
            }
        }
        if (! is_string($value) || ! preg_match('/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}/', $value)) {
            BusinessRules::invalid($field, 'Use actual ISO8601 dates, timestampValue or seconds objects.');
        }
        try {
            return CarbonImmutable::parse($value, 'UTC')->utc()->format('Y-m-d H:i:s');
        } catch (\Throwable) {
            BusinessRules::invalid($field, 'Invalid timestamp; no replacement date is invented.');
        }
    }

    private function record(string $path, array $payload, ?array $rawArchive = null): void
    {
        $json = json_encode($payload, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        $key = hash('sha256', $path);
        $hash = hash('sha256', $json);
        if (isset($this->records[$key])) {
            if ($this->records[$key]['source_hash'] !== $hash) {
                BusinessRules::invalid('documents', "Conflicting duplicate export document {$path}.");
            }
            if ($rawArchive !== null) {
                $this->records[$key]['document_payload'] = json_encode($rawArchive, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
            }

            return;
        }
        $this->records[$key] = ['document_path' => $path, 'path_hash' => $key, 'source_hash' => $hash, 'document_payload' => $rawArchive !== null ? json_encode($rawArchive, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) : $json];
    }
}
