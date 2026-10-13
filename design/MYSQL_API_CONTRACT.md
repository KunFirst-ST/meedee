# MySQL migration API contract

Flutter remains the customer/merchant UI. Laravel + MySQL replaces all Firebase runtime services. Preserve old Firebase data until an owner-authorized export has been imported and checked. No fake users, business fixtures, successful mail logs, or offline-success fallbacks in production.

## Wire format

- Base: `/api/v1`; JSON, bearer Sanctum tokens on mobile; all successes `{ "data": ... }`.
- Validation/authorization failures use non-2xx status and `{ "message": "...", "errors": {...} }`. Never return success on failed writes.
- IDs are strings up to 128 characters; generated UUIDs for new rows. Preserve imported Firebase IDs and ownership. Timestamps are UTC ISO8601 strings. JSON uses camelCase.
- User: `{uid, displayName, email, emailVerified, phone, role, shopId, providers:["password"|"google"], createdAt, updatedAt}`. Role is null/customer/shop. `shopId` survives role switches.
- Shop: `{id,name,ownerId,isOpen,description,category,location,preparationMinutes}`.
- Menu: `{id,shopId,name,price,priceSatang,available,imageBase64,description,category}`. SQL stores integer satang; JSON `price` is baht for existing UI.
- Order: `{id,shopId,shopName,customerId,customerName,items:[{menuItemId,name,price,qty}],total,totalSatang,status,note,createdAt,updatedAt}`.
- Order statuses: pending -> accepted -> cooking -> ready -> completed. Cancellation only from pending by the customer or owning merchant.

## Auth (backend auth owner)

- POST `/auth/register` `{name,email,password,password_confirmation}` -> `{data:{token,user}}`; actual unverified account. Mail transport must be real/configured, never log-success mail.
- POST `/auth/login` `{email,password,deviceName}` -> `{data:{token,user}}`.
- GET `/auth/me` -> `{data:user}`; POST `/auth/logout` revokes current token.
- POST `/auth/password/forgot` `{email}` neutral success only when mail workflow is available; POST `/auth/password/reset` `{email,token,password,password_confirmation}`.
- POST `/auth/email/resend`; signed GET `/auth/email/verify/{id}/{hash}` with expiry; Flutter refreshes `/auth/me` after actual verification.
- PUT `/auth/password` `{currentPassword,newPassword,newPasswordConfirmation}`; revoke other sessions after success.
- GET `/capabilities` -> `{data:{googleConfigured,emailConfigured}}`.
- Google uses server browser OAuth (Socialite), verified Google identity, whitelisted mobile/web callback, state + PKCE-bound one-time exchange code. Client stores verifier/state securely; POST `/auth/google/exchange` `{code,verifier,state}` -> `{data:{token,user}}`. Never put bearer tokens in redirect URLs. Provider configuration missing -> clear 503, not fake login.
- Backend auth owner owns Laravel bootstrap/composer, User model, users/tokens/OAuth migrations, auth controllers/routes/config/tests, and support helpers for DTO users. Business routes are included separately from `routes/business.php`.

## Business (backend business owner)

All routes require actual authenticated, verified user; ownership/role checked server-side. Profile auth metadata above is backend-auth owned; business may update display_name/phone/role/shop_id safely.

- GET `/profile` -> profile user DTO; PATCH `/profile` `{displayName,phone}`.
- POST `/profile/role` `{role,shopName?}` -> profile. Atomic shop creation/preserved shop ownership; same existing shop reused. DELETE `/profile/role` -> role null, keeps own shop/history.
- GET `/shops`; GET/PATCH `/shops/{shopId}`; PATCH `/shops/{shopId}/open` `{isOpen}`. Opening requires pickup location and preparation 1..240 minutes.
- GET `/favorites` -> string shop IDs; PUT `/favorites/{shopId}` `{favorite}`.
- GET/POST `/shops/{shopId}/menu`; PATCH/DELETE `/menu/{menuId}`; PATCH `/menu/{menuId}/available` `{available}`. Images max 200 KB decoded and valid raster image; no fabricated assets.
- POST `/orders` `{shopId,requestId,note,items:[{menuItemId,qty,expectedPriceSatang}]}` -> order DTO. Transaction locks current shop/menu/profile; canonical names/prices, open/available checks, readiness, distinct 1..8 items, qty 1..99, max note 500. Idempotency unique per customer/requestId, compare same payload on retries.
- GET `/orders` -> own customer orders; GET `/orders/{id}` only customer/owning merchant.
- GET `/shops/{shopId}/orders?history=false|true` -> owning merchant scoped active/history orders, actual dates/statuses.
- POST `/orders/{id}/accept`; PATCH `/orders/{id}/status` `{currentStatus,nextStatus}`; POST `/orders/{id}/cancel` atomic/current-state guarded.
- Business owner owns Shop/MenuItem/FoodOrder/OrderItem/Favorite models, business migrations/controllers/services/routes/business.php/tests and Firebase import command. No auth/bootstrap/User source edits without coordination.

## Flutter ownership

- Flutter auth owner: AppUser domain model, secure session + API client, AuthService, auth screens/gates, all User type/import replacements in screens and auth/account tests, main/pubspec, Google callback Android/web configuration. Preserve UI and actual verification gate. API client exposes `ApiClient.instance`, request(method,path,{body}), authenticated headers, typed ApiException, pollingStream helper or root coordinates exact interface.
- Root: Db REST adapter with existing public signatures/validation, non-auth business models (remove Firestore Timestamp/DocumentSnapshot), customer/merchant business API wiring tests. Polling reads may refresh actual server data and must propagate errors; no offline business success.
- Deployment stays isolated from existing VPS applications. MySQL binds localhost and uses a dedicated limited application DB account; no destructive reset/import. HTTPS before real credentials over public network. User has no domain yet.
