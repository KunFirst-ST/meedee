// Local integration of production rules with actual Auth-emulator ID tokens.
// firebase emulators:start --only auth,firestore --project demo-msu-food-flow --config test/firebase.integration-emulator.json
// node test/production_flow_test.mjs
// No production configuration, live mail, external requests, or dependencies.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const project = 'demo-msu-food-flow';
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8081';
for (const host of [authHost, firestoreHost]) {
  assert.match(host, /^(127\.0\.0\.1|localhost):\d+$/, 'Integration requests must use loopback emulators');
}
const authOrigin = `http://${authHost}`;
const firestoreOrigin = `http://${firestoreHost}`;
const origins = new Set([authOrigin, firestoreOrigin]);
const documentRoot = `projects/${project}/databases/(default)/documents`;
const base = `${firestoreOrigin}/v1/${documentRoot}`;
const testPassword = 'Local-Flow-Password-42';
let passed = 0;

async function request(url, { token, method = 'GET', body } = {}) {
  assert.ok(origins.has(new URL(url).origin), 'Request cannot leave the local emulators');
  const response = await fetch(url, {
    method,
    redirect: 'error',
    signal: AbortSignal.timeout(15000),
    headers: {
      'content-type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  return { ok: response.ok, status: response.status, data: text ? JSON.parse(text) : {} };
}

function auth(method, body) {
  return request(`${authOrigin}/identitytoolkit.googleapis.com/v1/accounts:${method}?key=fake-api-key`, {
    method: 'POST', body,
  });
}

async function allowed(name, operation) {
  const result = await operation;
  assert.equal(result.ok, true, `${name}: HTTP ${result.status} ${result.data.error?.message ?? ''}`);
  passed++;
  console.log(`PASS ${name}`);
  return result.data;
}

async function denied(name, operation) {
  const result = await operation;
  assert.equal(result.status, 403, `${name}: expected permission denied, got HTTP ${result.status}`);
  passed++;
  console.log(`PASS ${name}`);
}

function check(name, assertion) {
  assertion();
  passed++;
  console.log(`PASS ${name}`);
}

function value(input) {
  if (input === null) return { nullValue: null };
  if (Array.isArray(input)) return { arrayValue: { values: input.map(value) } };
  if (typeof input === 'object') return { mapValue: { fields: fields(input) } };
  if (typeof input === 'boolean') return { booleanValue: input };
  if (typeof input === 'number') return Number.isInteger(input)
    ? { integerValue: String(input) } : { doubleValue: input };
  return { stringValue: input };
}

function fields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, input]) => [key, value(input)]));
}

function decode(input) {
  if ('stringValue' in input) return input.stringValue;
  if ('integerValue' in input) return Number(input.integerValue);
  if ('doubleValue' in input) return input.doubleValue;
  if ('booleanValue' in input) return input.booleanValue;
  if ('timestampValue' in input) return input.timestampValue;
  if ('nullValue' in input) return null;
  if ('arrayValue' in input) return (input.arrayValue.values ?? []).map(decode);
  if ('mapValue' in input) return decodeFields(input.mapValue.fields ?? {});
  throw new Error('Unsupported Firestore value in integration test');
}

function decodeFields(data) {
  return Object.fromEntries(Object.entries(data).map(([key, input]) => [key, decode(input)]));
}

function write(path, data, { create = false, update = false, timestamps = [] } = {}) {
  return {
    update: { name: `${documentRoot}/${path}`, fields: fields(data) },
    ...(create ? { currentDocument: { exists: false } } : {}),
    ...(update ? {
      currentDocument: { exists: true }, updateMask: { fieldPaths: Object.keys(data) },
    } : {}),
    ...(timestamps.length ? {
      updateTransforms: timestamps.map((fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })),
    } : {}),
  };
}

function commit(user, writes, transaction) {
  return request(`${base}:commit`, {
    token: user?.token, method: 'POST', body: { writes, ...(transaction ? { transaction } : {}) },
  });
}

function update(user, path, data) {
  return commit(user, [write(path, data, { update: true, timestamps: ['updatedAt'] })]);
}

function read(user, path, transaction) {
  if (!transaction) return request(`${base}/${path}`, { token: user?.token });
  // The emulator's GetDocument query parser does not support BYTE_STRING
  // transaction parameters. BatchGet sends the same transaction in JSON.
  return request(`${base}:batchGet`, {
    token: user?.token, method: 'POST',
    body: { documents: [`${documentRoot}/${path}`], transaction },
  }).then((result) => {
    if (!result.ok) return result;
    const entry = result.data.find((item) => item.found || item.missing);
    if (entry?.found) return { ...result, data: entry.found };
    if (entry?.missing) return { ...result, ok: false, status: 404, data: {} };
    throw new Error('Firestore transaction read returned no document result');
  });
}

function claims(idToken) {
  return JSON.parse(Buffer.from(idToken.split('.')[1], 'base64url').toString());
}

async function signup(label) {
  const email = `${label}@msu-flow.example.test`;
  const created = await allowed(`${label}: create a local email/password account`, auth('signUp', {
    email, password: testPassword, returnSecureToken: true,
  }));
  check(`${label}: actual issued token targets the isolated project and is unverified`, () => {
    assert.equal(claims(created.idToken).aud, project);
    assert.equal(claims(created.idToken).email_verified, false);
    assert.equal(claims(created.idToken).firebase.sign_in_provider, 'password');
  });
  return { uid: created.localId, email, token: created.idToken, unverifiedToken: created.idToken };
}

async function verify(label, user) {
  await allowed(`${label}: request simulated verification email`, auth('sendOobCode', {
    requestType: 'VERIFY_EMAIL', idToken: user.token,
  }));
  const codes = await allowed(`${label}: read local verification code`, request(
    `${authOrigin}/emulator/v1/projects/${project}/oobCodes`,
  ));
  const code = codes.oobCodes?.find((entry) => entry.email === user.email && entry.requestType === 'VERIFY_EMAIL');
  check(`${label}: verification code belongs to this test account and emulator`, () => {
    assert.ok(code?.oobCode);
    assert.equal(new URL(code.oobLink).origin, authOrigin);
  });
  await allowed(`${label}: apply local verification code`, auth('update', { oobCode: code.oobCode }));
  const signedIn = await allowed(`${label}: sign in for a fresh verified ID token`, auth('signInWithPassword', {
    email: user.email, password: testPassword, returnSecureToken: true,
  }));
  check(`${label}: verified token preserves UID and project`, () => {
    assert.equal(signedIn.localId, user.uid);
    assert.equal(claims(signedIn.idToken).aud, project);
    assert.equal(claims(signedIn.idToken).email_verified, true);
  });
  return { ...user, token: signedIn.idToken };
}

async function begin(label, user) {
  const result = await allowed(`${label}: begin authenticated Firestore transaction`, request(`${base}:beginTransaction`, {
    token: user.token, method: 'POST', body: { options: { readWrite: {} } },
  }));
  return result.transaction;
}

async function queryOrders(label, user, field, id) {
  return allowed(label, request(`${base}:runQuery`, {
    token: user.token,
    method: 'POST',
    body: {
      structuredQuery: {
        from: [{ collectionId: 'orders' }],
        where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: value(id) } },
      },
    },
  }));
}

const cleanupFirestore = () => request(`${firestoreOrigin}/emulator/v1/projects/${project}/databases/(default)/documents`, {
  // Emulator administrative bypass is used ONLY to clear this named test dataset.
  token: 'owner', method: 'DELETE',
});
const cleanupAuth = () => request(`${authOrigin}/emulator/v1/projects/${project}/accounts`, { method: 'DELETE' });

// The CLI config lives in test/, so the current production rules are loaded
// directly into this isolated emulator instead of copying or weakening them.
// This is the emulator-specific rules configuration API, not a cloud deployment.
const productionRules = await readFile(new URL('../firestore.rules', import.meta.url), 'utf8');
await allowed('load the current application Firestore rules into the isolated emulator', request(
  `${firestoreOrigin}/emulator/v1/projects/${project}:securityRules`, {
    method: 'PUT', body: { rules: { files: [{ name: 'firestore.rules', content: productionRules }] } },
  },
));
await allowed('clear only the isolated flow Firestore dataset', cleanupFirestore());
await allowed('clear only the isolated flow Auth accounts', cleanupAuth());
try {
  let customer = await signup('customer');
  let merchant = await signup('merchant');
  let outsider = await signup('outsider');
  const shopId = `shop_${merchant.uid}`;
  const shopPath = `shops/${shopId}`;
  const menuPath = 'menuItems/flow-main';
  const drinkPath = 'menuItems/flow-drink';
  await denied('anonymous users cannot read shops', read(null, shopPath));
  await denied('unverified issued token cannot read shops', read(customer, shopPath));
  await denied('unverified issued token cannot create its profile', commit(customer, [write(`users/${customer.uid}`, {
    displayName: 'ลูกค้าทดสอบ', role: 'customer',
  }, { create: true, timestamps: ['createdAt', 'updatedAt'] })]));
  customer = await verify('customer', customer);
  merchant = await verify('merchant', merchant);
  outsider = await verify('outsider', outsider);

  await allowed('customer creates its own account profile', commit(customer, [write(`users/${customer.uid}`, {
    displayName: 'ลูกค้าทดสอบ', phone: '0812345678', role: 'customer',
  }, { create: true, timestamps: ['createdAt', 'updatedAt'] })]));
  await allowed('outsider creates its own separate profile', commit(outsider, [write(`users/${outsider.uid}`, {
    displayName: 'บุคคลอื่น', role: 'customer',
  }, { create: true, timestamps: ['createdAt', 'updatedAt'] })]));
  await allowed('merchant creates its profile and owned shop atomically', commit(merchant, [
    write(`users/${merchant.uid}`, { displayName: 'เจ้าของร้าน', role: 'shop', shopId }, {
      create: true, timestamps: ['createdAt', 'updatedAt'],
    }),
    write(shopPath, { name: 'ครัวทดสอบจริง', ownerId: merchant.uid, isOpen: false }, {
      create: true, timestamps: ['createdAt', 'updatedAt'],
    }),
  ]));
  await allowed('merchant updates shop information and opens for orders', update(merchant, shopPath, {
    name: 'ครัวทดสอบจริง', isOpen: true, category: 'อาหารตามสั่ง',
    description: 'ร้านสำหรับ integration test', location: 'จุดรับทดสอบ', preparationMinutes: 15,
  }));
  await allowed('customer reads the live merchant shop', read(customer, shopPath));
  await denied('customer cannot edit the merchant shop', update(customer, shopPath, { isOpen: false }));
  await denied('outsider cannot claim the merchant shop', update(outsider, `users/${outsider.uid}`, { role: 'shop', shopId }));

  await allowed('merchant creates menu items', commit(merchant, [
    write(menuPath, { shopId, name: 'ข้าวกะเพรา', price: 49.9, available: true }, { create: true, timestamps: ['createdAt'] }),
    write(drinkPath, { shopId, name: 'น้ำมะนาว', price: 20, available: true }, { create: true, timestamps: ['createdAt'] }),
    write('menuItems/flow-delete', { shopId, name: 'เมนูชั่วคราว', price: 10, available: true }, { create: true, timestamps: ['createdAt'] }),
  ]));
  await allowed('merchant updates menu name price and description', update(merchant, menuPath, {
    name: 'ข้าวกะเพราไข่ดาว', price: 55.25, description: 'ปรุงใหม่',
  }));
  await allowed('merchant deletes only its own temporary menu', commit(merchant, [{ delete: `${documentRoot}/menuItems/flow-delete` }]));
  await denied('customer cannot edit merchant menu prices', update(customer, menuPath, { price: 1 }));
  await denied('outsider cannot delete merchant menu', commit(outsider, [{ delete: `${documentRoot}/${menuPath}` }]));
  await allowed('customer edits its display name and canonical phone', update(customer, `users/${customer.uid}`, {
    displayName: 'ลูกค้าชื่อใหม่', phone: '+66812345678',
  }));
  await denied('outsider cannot edit another customer profile', update(outsider, `users/${customer.uid}`, { displayName: 'ปลอมชื่อ' }));
  await allowed('customer saves its own favorite shop', commit(customer, [write(`users/${customer.uid}/favorites/${shopId}`, {
    shopId,
  }, { timestamps: ['createdAt'] })]));
  await allowed('customer reads its saved favorite', read(customer, `users/${customer.uid}/favorites/${shopId}`));
  await denied('outsider cannot read another customer favorite', read(outsider, `users/${customer.uid}/favorites/${shopId}`));

  async function checkout(requestId) {
    const orderPath = `orders/${customer.uid}_${requestId}`;
    const transaction = await begin(requestId, customer);
    const profile = decodeFields((await allowed(`${requestId}: read saved customer name in transaction`, read(customer, `users/${customer.uid}`, transaction))).fields);
    const shop = decodeFields((await allowed(`${requestId}: read live shop in transaction`, read(customer, shopPath, transaction))).fields);
    const main = decodeFields((await allowed(`${requestId}: read current main menu in transaction`, read(customer, menuPath, transaction))).fields);
    const drink = decodeFields((await allowed(`${requestId}: read current drink menu in transaction`, read(customer, drinkPath, transaction))).fields);
    const missing = await read(customer, orderPath, transaction);
    check(`${requestId}: order request has not already been submitted`, () => assert.equal(missing.status, 404));
    const items = [
      { menuItemId: 'flow-main', name: main.name, price: main.price, qty: 2 },
      { menuItemId: 'flow-drink', name: drink.name, price: drink.price, qty: 1 },
    ];
    const data = {
      shopId, shopName: shop.name, customerId: customer.uid, customerName: profile.displayName,
      items, total: items.reduce((sum, item) => sum + Math.round(item.price * 100) * item.qty, 0) / 100,
      status: 'pending', note: 'ไม่เผ็ด', requestId,
    };
    await allowed(`${requestId}: commit canonical order and server timestamps transactionally`, commit(customer, [write(orderPath, data, {
      create: true, timestamps: ['createdAt', 'updatedAt'],
    })], transaction));
    return { orderPath, data };
  }

  const first = await checkout('flow-complete');
  const receipt = decodeFields((await allowed('customer reads its created receipt', read(customer, first.orderPath))).fields);
  check('receipt keeps current profile name menu price exact total and server time', () => {
    assert.equal(receipt.customerName, 'ลูกค้าชื่อใหม่');
    assert.equal(receipt.items[0].name, 'ข้าวกะเพราไข่ดาว');
    assert.equal(receipt.items[0].price, 55.25);
    assert.equal(receipt.total, 130.5);
    assert.ok(Number.isFinite(Date.parse(receipt.createdAt)));
    assert.ok(Number.isFinite(Date.parse(receipt.updatedAt)));
  });
  await allowed('merchant reads incoming order for its shop', read(merchant, first.orderPath));
  await denied('outsider cannot read another customer receipt', read(outsider, first.orderPath));
  await denied('anonymous users cannot read a receipt', read(null, first.orderPath));
  await denied('old unverified token remains denied after account verification', read({ token: customer.unverifiedToken }, first.orderPath));
  await denied('customer cannot accept its own order as merchant', update(customer, first.orderPath, { status: 'accepted' }));
  await denied('merchant cannot skip directly from pending to ready', update(merchant, first.orderPath, { status: 'ready' }));
  await denied('merchant cannot change receipt total', update(merchant, first.orderPath, { total: 1 }));
  const forged = { ...first.data, requestId: 'forged-price', total: 0.01 };
  await denied('customer cannot forge an order total', commit(customer, [write(`orders/${customer.uid}_forged-price`, forged, {
    create: true, timestamps: ['createdAt', 'updatedAt'],
  })]));

  for (const status of ['accepted', 'cooking', 'ready', 'completed']) {
    const transaction = await begin(`merchant ${status}`, merchant);
    await allowed(`${status}: merchant reads current order inside transaction`, read(merchant, first.orderPath, transaction));
    await allowed(`${status}: merchant reads owned shop inside transaction`, read(merchant, shopPath, transaction));
    await allowed(`merchant advances order to ${status}`, commit(merchant, [write(first.orderPath, { status }, {
      update: true, timestamps: ['updatedAt'],
    })], transaction));
    const current = decodeFields((await allowed(`customer observes order status ${status}`, read(customer, first.orderPath))).fields);
    check(`${status}: status changed while receipt amount and created time remain immutable`, () => {
      assert.equal(current.status, status);
      assert.equal(current.total, receipt.total);
      assert.equal(current.createdAt, receipt.createdAt);
    });
  }
  await denied('completed order cannot regress', update(merchant, first.orderPath, { status: 'pending' }));
  const customerHistory = await queryOrders('customer queries only its own order history', customer, 'customerId', customer.uid);
  check('customer history contains its completed receipt', () => {
    assert.ok(customerHistory.some((entry) => entry.document?.name.endsWith(first.orderPath)));
  });
  const merchantHistory = await queryOrders('merchant queries order history of its own shop', merchant, 'shopId', shopId);
  check('merchant history contains the completed receipt', () => {
    assert.ok(merchantHistory.some((entry) => entry.document?.name.endsWith(first.orderPath)));
  });
  await denied('outsider cannot query another customer order history', request(`${base}:runQuery`, {
    token: outsider.token, method: 'POST', body: {
      structuredQuery: { from: [{ collectionId: 'orders' }], where: {
        fieldFilter: { field: { fieldPath: 'customerId' }, op: 'EQUAL', value: value(customer.uid) },
      } },
    },
  }));

  const pending = await checkout('flow-cancel');
  await denied('outsider cannot cancel another customer pending order', update(outsider, pending.orderPath, { status: 'cancelled' }));
  await allowed('customer cancels its own pending order', update(customer, pending.orderPath, { status: 'cancelled' }));
  const cancelled = decodeFields((await allowed('merchant observes customer cancellation', read(merchant, pending.orderPath))).fields);
  check('pending cancellation retains immutable receipt and cancelled status', () => {
    assert.equal(cancelled.status, 'cancelled');
    assert.equal(cancelled.total, pending.data.total);
  });
  await denied('merchant cannot reopen cancelled order', update(merchant, pending.orderPath, { status: 'accepted' }));
  await allowed('customer removes its own favorite', commit(customer, [{ delete: `${documentRoot}/users/${customer.uid}/favorites/${shopId}` }]));
} finally {
  await allowed('remove only isolated flow Firestore test data', cleanupFirestore());
  await allowed('remove only isolated flow Auth test accounts', cleanupAuth());
}

console.log(`\n${passed} Firebase Auth + Firestore flow checks passed.`);
