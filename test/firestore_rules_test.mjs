// Start with: firebase emulators:start --only firestore --project demo-msu-food
// Then run: node test/firestore_rules_test.mjs
// No production Firebase credentials or npm test dependencies are needed.
import assert from 'node:assert/strict';

const host = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8081';
assert.match(host, /^(127\.0\.0\.1|localhost):\d+$/, 'Use a local emulator only');
const project = 'demo-msu-food';
const documentRoot = `projects/${project}/databases/(default)/documents`;
const base = `http://${host}/v1/${documentRoot}`;
let passed = 0;

function token(uid, { emailVerified = true } = {}) {
  const encode = (data) => Buffer.from(JSON.stringify(data)).toString('base64url');
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({
    sub: uid,
    user_id: uid,
    aud: project,
    iss: `https://securetoken.google.com/${project}`,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 3600,
    ...(emailVerified === null ? {} : { email_verified: emailVerified }),
    firebase: { sign_in_provider: 'custom' },
  })}.`;
}

function value(input) {
  if (input === null) return { nullValue: null };
  if (Array.isArray(input)) return { arrayValue: { values: input.map(value) } };
  if (typeof input === 'object') return { mapValue: { fields: fields(input) } };
  if (typeof input === 'boolean') return { booleanValue: input };
  if (typeof input === 'number') {
    return Number.isInteger(input)
      ? { integerValue: String(input) }
      : { doubleValue: input };
  }
  return { stringValue: input };
}

function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, input]) => [key, value(input)]));
}

function write(path, data, { create = false, update = false, timestamps = [] } = {}) {
  return {
    update: { name: `${documentRoot}/${path}`, fields: fields(data) },
    ...(create ? { currentDocument: { exists: false } } : {}),
    ...(update ? {
      currentDocument: { exists: true },
      updateMask: { fieldPaths: Object.keys(data) },
    } : {}),
    ...(timestamps.length ? {
      updateTransforms: timestamps.map((fieldPath) => ({
        fieldPath,
        setToServerValue: 'REQUEST_TIME',
      })),
    } : {}),
  };
}

async function request(url, uid, method = 'GET', body, claims) {
  const response = await fetch(url, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(uid ? { Authorization: `Bearer ${uid === 'ADMIN' ? 'owner' : token(uid, claims)}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  return { ok: response.ok, status: response.status, text: await response.text() };
}

const commit = (uid, writes, claims) => request(`${base}:commit`, uid, 'POST', { writes }, claims);
const update = (uid, path, data) => commit(uid, [write(path, data, {
  update: true,
  timestamps: ['updatedAt'],
})]);
const read = (uid, path) => request(`${base}/${path}`, uid);

async function allowed(name, operation) {
  const result = await operation;
  assert.equal(result.ok, true, `${name}: ${result.status} ${result.text}`);
  passed++;
  console.log(`PASS ${name}`);
  return result;
}

async function denied(name, operation) {
  const result = await operation;
  assert.equal(result.status, 403, `${name}: expected permission denied, got ${result.status} ${result.text}`);
  passed++;
  console.log(`PASS ${name}`);
}

const menus = Array.from({ length: 9 }, (_, index) => ({
  id: `menu-${index}`,
  shopId: 'shop',
  name: `Menu ${index}`,
  price: index === 0 ? 0.29 : 49,
  available: true,
}));

await allowed('clear isolated demo emulator dataset', request(
  `http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`,
  'ADMIN',
  'DELETE',
));

await allowed('seed isolated emulator data', commit('ADMIN', [
  write('users/customer', { displayName: 'Customer', role: 'customer' }, { timestamps: ['createdAt'] }),
  write('users/stranger', { displayName: 'Stranger', role: 'customer' }, { timestamps: ['createdAt'] }),
  write('users/merchant', { displayName: 'Merchant', role: 'shop', shopId: 'shop' }, { timestamps: ['createdAt'] }),
  write('shops/shop', { name: 'MSU Kitchen', ownerId: 'merchant', isOpen: true }, { timestamps: ['createdAt'] }),
  write('shops/foreign', { name: 'Other Kitchen', ownerId: 'other-merchant', isOpen: true }, { timestamps: ['createdAt'] }),
  write('menuItems/foreign-menu', {
    shopId: 'foreign', name: 'Foreign meal', price: 49, available: true,
  }, { timestamps: ['createdAt'] }),
  ...menus.map(({ id, ...data }) => write(`menuItems/${id}`, data, { timestamps: ['createdAt'] })),
]));

let sequence = 0;
function order(overrides = {}, count = 1) {
  const requestId = `rules-test-${++sequence}`;
  const items = menus.slice(0, count).map((menu) => ({
    menuItemId: menu.id,
    name: menu.name,
    price: menu.price,
    qty: 3,
  }));
  const totalSatang = items.reduce((sum, item) => sum + Math.round(item.price * 100) * item.qty, 0);
  return {
    shopId: 'shop',
    shopName: 'MSU Kitchen',
    customerId: 'customer',
    customerName: 'Customer',
    items,
    total: totalSatang / 100,
    status: 'pending',
    note: '',
    requestId,
    ...overrides,
  };
}

function place(data, uid = 'customer') {
  return commit(uid, [write(`orders/${data.customerId}_${data.requestId}`, data, {
    create: true,
    timestamps: ['createdAt', 'updatedAt'],
  })]);
}

await denied('anonymous shop access', read(null, 'shops/shop'));
await denied('unverified email cannot read shops', request(`${base}/shops/shop`, 'customer', 'GET', undefined, { emailVerified: false }));
await denied('missing email verification claim cannot read shops', request(`${base}/shops/shop`, 'customer', 'GET', undefined, { emailVerified: null }));
await denied('unverified email cannot read its own profile', request(`${base}/users/customer`, 'customer', 'GET', undefined, { emailVerified: false }));
await denied('unverified email cannot read menus', request(`${base}/menuItems/menu-0`, 'customer', 'GET', undefined, { emailVerified: false }));
await denied('unverified email cannot create a profile', commit('unverified-new', [write('users/unverified-new', {
  displayName: 'Unverified', role: 'customer',
}, { create: true, timestamps: ['createdAt', 'updatedAt'] })], { emailVerified: false }));
await denied('unverified email cannot update its profile', commit('customer', [write('users/customer', {
  displayName: 'Unverified edit',
}, { update: true, timestamps: ['updatedAt'] })], { emailVerified: false }));
const unverifiedOrder = order();
await denied('unverified email cannot create orders', commit('customer', [write(
  `orders/customer_${unverifiedOrder.requestId}`, unverifiedOrder,
  { create: true, timestamps: ['createdAt', 'updatedAt'] },
)], { emailVerified: false }));
await allowed('authenticated shop access', read('customer', 'shops/shop'));
await allowed('customer edits its own name and canonical phone', update('customer', 'users/customer', {
  displayName: 'Updated Customer', phone: '+66812345678',
}));
const updatedProfile = JSON.parse((await allowed('customer reads updated own profile', read('customer', 'users/customer'))).text).fields;
assert.equal(updatedProfile.displayName.stringValue, 'Updated Customer');
assert.equal(updatedProfile.phone.stringValue, '+66812345678');
assert.equal(updatedProfile.role.stringValue, 'customer');
await allowed('new receipt uses the saved profile name', place(order({ customerName: 'Updated Customer' })));
await denied('receipt cannot forge a different customer name', place(order({ customerName: 'Forged Customer' })));
await denied('stranger cannot change profile phone', update('stranger', 'users/customer', { phone: '0899999999' }));
for (const invalidPhone of ['1234567', '1234567890123456', '++66812345678', '081-234-5678', 'phone', 812345678, null]) {
  await denied(`profile rejects invalid phone ${JSON.stringify(invalidPhone)}`, update('customer', 'users/customer', { phone: invalidPhone }));
}
for (const invalidName of ['', 'x'.repeat(121)]) {
  await denied(`profile rejects name length ${invalidName.length}`, update('customer', 'users/customer', { displayName: invalidName }));
}
for (const forbiddenField of ['email', 'password', 'accessToken', 'admin']) {
  await denied(`profile cannot store ${forbiddenField}`, update('customer', 'users/customer', { [forbiddenField]: 'forbidden' }));
}
await allowed('phone can be removed without affecting role', update('customer', 'users/customer', {
  displayName: 'Customer', phone: '',
}));
await allowed('new customer profile accepts optional phone', commit('new-customer', [write('users/new-customer', {
  displayName: 'New Customer', phone: '0812345678', role: 'customer',
}, { create: true, timestamps: ['createdAt', 'updatedAt'] })]));
await denied('new profile cannot store password', commit('bad-new-customer', [write('users/bad-new-customer', {
  displayName: 'New Customer', role: 'customer', password: 'do-not-store',
}, { create: true, timestamps: ['createdAt', 'updatedAt'] })]));
await allowed('merchant edits own account without changing shop identity', update('merchant', 'users/merchant', {
  displayName: 'Updated Merchant', phone: '0898765432',
}));
const updatedMerchant = JSON.parse((await allowed('merchant reads preserved role and shop', read('merchant', 'users/merchant'))).text).fields;
assert.equal(updatedMerchant.role.stringValue, 'shop');
assert.equal(updatedMerchant.shopId.stringValue, 'shop');
await allowed('missing order can be checked for idempotency', read('customer', 'orders/customer_not-created').then((result) => {
  // A successful permission check still returns NOT_FOUND for a missing document.
  assert.equal(result.status, 404, result.text);
  return { ...result, ok: true };
}));
await denied('cannot create an admin role', update('customer', 'users/customer', { role: 'admin' }));
await denied('cannot change another profile', update('stranger', 'users/customer', { displayName: 'Hacked' }));
await denied('cannot claim someone else\'s shop', update('customer', 'users/customer', { role: 'shop', shopId: 'foreign' }));
await denied('cannot delete role/profile to orphan a shop', request(`${base}/users/merchant`, 'merchant', 'DELETE'));
await denied('customer cannot edit merchant shop', update('customer', 'shops/shop', { isOpen: false }));
await denied('merchant cannot transfer ownership', update('merchant', 'shops/shop', { ownerId: 'stranger' }));
await denied('customer cannot edit menu prices', update('customer', 'menuItems/menu-1', { price: 1 }));
await allowed('owner can manage menu availability', update('merchant', 'menuItems/menu-1', { available: true }));

const firstOrder = order();
await allowed('decimal-satang receipt creation', place(firstOrder));
for (let count = 2; count <= 8; count++) {
  await allowed(`${count} independently checked menu lines`, place(order({}, count)));
}
// Exercise the final allowed slot, so the expression-budget fix cannot silently
// omit canonical or quantity checks on the eighth menu line.
const wrongLastName = order({}, 8);
wrongLastName.items[7].name = 'Forged menu name';
await denied('eighth line rejects a forged menu name', place(wrongLastName));
const wrongLastPrice = order({}, 8);
wrongLastPrice.items[7].price = 1;
wrongLastPrice.total = wrongLastPrice.items.reduce((sum, item) =>
  sum + Math.round(item.price * 100) * item.qty, 0) / 100;
await denied('eighth line rejects a forged price and matching forged total', place(wrongLastPrice));
const foreignLastItem = order({}, 8);
Object.assign(foreignLastItem.items[7], { menuItemId: 'foreign-menu', name: 'Foreign meal' });
await denied('eighth line must belong to the order shop', place(foreignLastItem));
const missingLastItem = order({}, 8);
missingLastItem.items[7].menuItemId = 'missing-menu';
await denied('eighth line requires an existing menu item', place(missingLastItem));
for (const quantity of [0.5, 100]) {
  const invalidQuantity = order({}, 8);
  invalidQuantity.items[7].qty = quantity;
  invalidQuantity.total = invalidQuantity.items.reduce((sum, item) =>
    sum + Math.round(item.price * 100) * item.qty, 0) / 100;
  await denied(`eighth line rejects quantity ${quantity}`, place(invalidQuantity));
}
const extraLastField = order({}, 8);
extraLastField.items[7].discount = 1;
await denied('eighth line rejects extra client fields', place(extraLastField));
const missingLastField = order({}, 8);
delete missingLastField.items[7].name;
await denied('eighth line requires canonical receipt fields', place(missingLastField));
await allowed('owner can sell out eighth menu item', update('merchant', 'menuItems/menu-7', { available: false }));
await denied('eighth line rejects a sold-out menu item', place(order({}, 8)));
await allowed('owner restores eighth menu item', update('merchant', 'menuItems/menu-7', { available: true }));
await denied('ninth menu exceeds rule read budget', place(order({}, 9)));
await denied('empty order is rejected', place(order({}, 0)));
await denied('merchant role cannot create a customer order', place(order({
  customerId: 'merchant', customerName: 'Merchant',
}), 'merchant'));
const mismatchedRequest = order();
await denied('receipt path must match customer and request ID', commit('customer', [write(
  'orders/customer_forged-request-path', mismatchedRequest,
  { create: true, timestamps: ['createdAt', 'updatedAt'] },
)]));
for (const staleField of ['createdAt', 'updatedAt']) {
  const staleOrder = order();
  const staleWrite = write(`orders/customer_${staleOrder.requestId}`, staleOrder, {
    create: true,
    timestamps: [staleField === 'createdAt' ? 'updatedAt' : 'createdAt'],
  });
  staleWrite.update.fields[staleField] = { timestampValue: '2020-01-01T00:00:00Z' };
  await denied(`order requires server ${staleField}`, commit('customer', [staleWrite]));
}
await denied('forged total rejected', place(order({ total: 0.01 })));
await denied('forged customer ID rejected', place(order({ customerId: 'stranger' })));
const repriced = order();
repriced.items[0].price = 0.01;
repriced.total = 0.03;
await denied('forged price rejected even with matching forged total', place(repriced));
const zeroQuantity = order();
zeroQuantity.items[0].qty = 0;
await denied('zero quantity rejected', place(zeroQuantity));
await allowed('merchant can close shop', update('merchant', 'shops/shop', { isOpen: false }));
await denied('closed shop rejects orders', place(order()));
await allowed('merchant can reopen shop', update('merchant', 'shops/shop', { isOpen: true }));
await allowed('merchant marks item sold out', update('merchant', 'menuItems/menu-0', { available: false }));
await denied('sold-out menu rejects orders', place(order()));
await allowed('merchant restores menu availability', update('merchant', 'menuItems/menu-0', { available: true }));

const receipt = `orders/customer_${firstOrder.requestId}`;
await allowed('customer can read own receipt', read('customer', receipt));
await allowed('merchant can read its shop receipt', read('merchant', receipt));
await denied('other customer cannot read receipt', read('stranger', receipt));
await denied('customer cannot progress merchant lifecycle', update('customer', receipt, { status: 'accepted' }));
await denied('merchant cannot skip lifecycle steps', update('merchant', receipt, { status: 'ready' }));
await denied('merchant cannot alter total', update('merchant', receipt, { total: 100 }));
await denied('customer cannot alter receipt items', update('customer', receipt, { items: [] }));
await allowed('merchant accepts pending order', update('merchant', receipt, { status: 'accepted' }));
await denied('customer cannot cancel accepted order', update('customer', receipt, { status: 'cancelled' }));
await allowed('merchant starts cooking', update('merchant', receipt, { status: 'cooking' }));
await allowed('merchant marks ready', update('merchant', receipt, { status: 'ready' }));
await allowed('merchant completes handoff', update('merchant', receipt, { status: 'completed' }));
await denied('completed order cannot regress', update('merchant', receipt, { status: 'pending' }));
await denied('customer cannot delete receipt', request(`${base}/${receipt}`, 'customer', 'DELETE'));

const cancellable = order();
await allowed('create order for pending cancellation', place(cancellable));
const cancellablePath = `orders/customer_${cancellable.requestId}`;
await denied('stranger cannot cancel another order', update('stranger', cancellablePath, { status: 'cancelled' }));
await allowed('customer cancels own pending order', update('customer', cancellablePath, { status: 'cancelled' }));
await denied('cancelled order cannot be reopened', update('merchant', cancellablePath, { status: 'accepted' }));

await allowed('customer saves own favorite', commit('customer', [write('users/customer/favorites/shop', {
  shopId: 'shop',
}, { timestamps: ['createdAt'] })]));
await denied('stranger cannot save favorites for another user', commit('stranger', [write('users/customer/favorites/foreign', {
  shopId: 'foreign',
}, { timestamps: ['createdAt'] })]));
await allowed('customer removes own favorite', request(`${base}/users/customer/favorites/shop`, 'customer', 'DELETE'));

await allowed('new merchant and owned shop can be created atomically', commit('new-merchant', [
  write('users/new-merchant', {
    displayName: 'New Merchant', role: 'shop', shopId: 'new-shop',
  }, { create: true, timestamps: ['createdAt', 'updatedAt'] }),
  write('shops/new-shop', {
    name: 'New Kitchen', ownerId: 'new-merchant', isOpen: false,
  }, { create: true, timestamps: ['createdAt', 'updatedAt'] }),
]));
await allowed('role reset preserves shop identity and closes shop atomically', commit('merchant', [
  write('users/merchant', { role: 'unassigned' }, { update: true, timestamps: ['updatedAt'] }),
  write('shops/shop', { isOpen: false }, { update: true, timestamps: ['updatedAt'] }),
]));
await allowed('merchant can resume the same shop', update('merchant', 'users/merchant', { role: 'shop' }));
await denied('merchant cannot replace its existing shop link', update('merchant', 'users/merchant', { shopId: 'foreign' }));

console.log(`\n${passed} Firestore emulator assertions passed.`);
