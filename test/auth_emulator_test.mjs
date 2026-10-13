// Start only the isolated Auth emulator (no production configuration):
// firebase emulators:start --only auth --project demo-msu-food-auth --config test/firebase.auth-emulator.json
// Then run: node test/auth_emulator_test.mjs
// Uses Node's built-in fetch and assert; no test dependencies or real email.
import assert from 'node:assert/strict';

const host = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
assert.match(host, /^(127\.0\.0\.1|localhost):\d+$/, 'Use a local Auth emulator only');
const project = 'demo-msu-food-auth';
const origin = `http://${host}`;
const adminPath = `/emulator/v1/projects/${project}`;
// The emulator accepts this dummy key; it is never a Firebase production API key.
const apiKey = 'fake-api-key';
const email = 'msu-auth-integration@example.test';
const password = 'Demo-Original-Password-42';
const newPassword = 'Demo-Reset-Password-84';
let passed = 0;

async function request(path, body, method = 'POST') {
  assert.ok(path.startsWith('/'), 'Request must remain on the local emulator origin');
  const url = new URL(path, origin);
  assert.equal(url.origin, origin, 'Request cannot leave the local emulator');
  const response = await fetch(url, {
    method,
    redirect: 'error',
    signal: AbortSignal.timeout(10000),
    headers: { 'content-type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  return { status: response.status, ok: response.ok, data: text ? JSON.parse(text) : {} };
}

function auth(method, body) {
  return request(`/identitytoolkit.googleapis.com/v1/accounts:${method}?key=${apiKey}`, body);
}

async function allowed(name, operation) {
  const result = await operation;
  assert.equal(result.ok, true, `${name}: HTTP ${result.status} ${result.data.error?.message ?? ''}`);
  passed++;
  console.log(`PASS ${name}`);
  return result.data;
}

async function denied(name, operation, codePattern) {
  const result = await operation;
  assert.equal(result.status, 400, `${name}: expected HTTP 400, got ${result.status}`);
  assert.match(result.data.error?.message ?? '', codePattern, name);
  passed++;
  console.log(`PASS ${name}`);
}

function check(name, assertion) {
  assertion();
  passed++;
  console.log(`PASS ${name}`);
}

function claims(idToken) {
  assert.equal(typeof idToken, 'string', 'Auth must return an ID token');
  return JSON.parse(Buffer.from(idToken.split('.')[1], 'base64url').toString());
}

async function oobCode(type) {
  const data = await allowed(`retrieve local ${type} code`, request(`${adminPath}/oobCodes`, undefined, 'GET'));
  const code = data.oobCodes?.find((entry) => entry.email === email && entry.requestType === type);
  check(`${type} code belongs to the test account and local emulator`, () => {
    assert.ok(code?.oobCode);
    assert.equal(new URL(code.oobLink).origin, origin);
  });
  return code.oobCode;
}

await allowed('clear isolated Auth emulator test accounts', request(`${adminPath}/accounts`, undefined, 'DELETE'));
try {
  const created = await allowed('sign up with email and password', auth('signUp', {
    email, password, returnSecureToken: true,
  }));
  check('new token has the isolated project and unverified email', () => {
    const tokenClaims = claims(created.idToken);
    assert.equal(tokenClaims.aud, project);
    assert.equal(tokenClaims.email, email);
    assert.equal(tokenClaims.email_verified, false);
    assert.equal(tokenClaims.firebase.sign_in_provider, 'password');
  });
  await denied('duplicate email signup is rejected', auth('signUp', {
    email, password, returnSecureToken: true,
  }), /^EMAIL_EXISTS$/);
  await denied('wrong password is rejected', auth('signInWithPassword', {
    email, password: 'Incorrect-Password-99', returnSecureToken: true,
  }), /^(INVALID_PASSWORD|INVALID_LOGIN_CREDENTIALS)$/);
  const initialSignIn = await allowed('correct password signs in', auth('signInWithPassword', {
    email, password, returnSecureToken: true,
  }));
  check('sign-in preserves the account ID and unverified status', () => {
    assert.equal(initialSignIn.localId, created.localId);
    assert.equal(claims(initialSignIn.idToken).email_verified, false);
  });

  await allowed('request a simulated email verification', auth('sendOobCode', {
    requestType: 'VERIFY_EMAIL', idToken: initialSignIn.idToken,
  }));
  const verificationCode = await oobCode('VERIFY_EMAIL');
  await allowed('apply the local verification code', auth('update', { oobCode: verificationCode }));
  const verifiedSignIn = await allowed('sign in after email verification', auth('signInWithPassword', {
    email, password, returnSecureToken: true,
  }));
  check('fresh token contains verified email for the same account', () => {
    const tokenClaims = claims(verifiedSignIn.idToken);
    assert.equal(verifiedSignIn.localId, created.localId);
    assert.equal(tokenClaims.aud, project);
    assert.equal(tokenClaims.email_verified, true);
  });

  await allowed('request a simulated password reset', auth('sendOobCode', {
    requestType: 'PASSWORD_RESET', email,
  }));
  const resetCode = await oobCode('PASSWORD_RESET');
  await allowed('apply the password reset using the local action code', auth('resetPassword', {
    oobCode: resetCode, newPassword,
  }));
  await denied('old password is rejected after reset', auth('signInWithPassword', {
    email, password, returnSecureToken: true,
  }), /^(INVALID_PASSWORD|INVALID_LOGIN_CREDENTIALS)$/);
  const resetSignIn = await allowed('new password signs in after reset', auth('signInWithPassword', {
    email, password: newPassword, returnSecureToken: true,
  }));
  check('password reset preserves verified identity', () => {
    assert.equal(resetSignIn.localId, created.localId);
    assert.equal(claims(resetSignIn.idToken).email_verified, true);
  });
  await denied('a used reset code cannot be replayed', auth('resetPassword', {
    oobCode: resetCode, newPassword: password,
  }), /^(INVALID_OOB_CODE|EXPIRED_OOB_CODE)$/);
} finally {
  await allowed('remove isolated Auth emulator test accounts after the run', request(`${adminPath}/accounts`, undefined, 'DELETE'));
}

console.log(`\n${passed} Firebase Auth emulator assertions passed.`);
