import assert from 'node:assert/strict';
import test from 'node:test';
import { collectExport, parseArguments, serializeValue } from './export.mjs';

class Timestamp { constructor(seconds, nanoseconds) { this.seconds = seconds; this.nanoseconds = nanoseconds; } }
class GeoPoint { constructor(latitude, longitude) { this.latitude = latitude; this.longitude = longitude; } }
class DocumentReference { constructor(path) { this.path = path; this.firestore = { projectId: 'msu-foodnaja' }; } }
const types = { Timestamp, GeoPoint, DocumentReference };
const now = () => new Date('2026-10-13T10:00:00Z');

function user(uid) {
  return { uid, email: `${uid}@example.org`, emailVerified: true, disabled: false,
    displayName: uid, providerData: [{ providerId: 'password', uid: `${uid}@example.org` }],
    metadata: { creationTime: '2025-01-01T00:00:00Z', lastSignInTime: '2026-01-01T00:00:00Z' },
    passwordHash: 'secret-must-not-export', passwordSalt: 'secret-salt' };
}

function fixture(rows) {
  const reads = [];
  const collectionPaths = new Set();
  const references = new Map();
  for (const row of rows) {
    const segments = row.path.split('/');
    for (let length = 1; length < segments.length; length += 2) {
      const collectionPath = segments.slice(0, length).join('/');
      collectionPaths.add(collectionPath);
      const documentPath = segments.slice(0, length + 1).join('/');
      if (!references.has(documentPath)) references.set(documentPath, { path: documentPath, id: segments[length] });
    }
  }
  const collection = (collectionPath) => ({ path: collectionPath, async listDocuments() {
    reads.push(['listDocuments', collectionPath]);
    return [...references.values()].filter((ref) => ref.path.slice(0, ref.path.lastIndexOf('/')) === collectionPath);
  } });
  for (const ref of references.values()) {
    ref.listCollections = async () => {
      reads.push(['listCollections', ref.path]);
      return [...collectionPaths].filter((candidate) => candidate.slice(0, candidate.lastIndexOf('/')) === ref.path).map(collection);
    };
  }
  const db = {
    async listCollections() { reads.push(['roots']); return [...collectionPaths].filter((candidate) => !candidate.includes('/')).map(collection); },
    async getAll(...refs) { reads.push(['getAll', refs.map((ref) => ref.path)]); return refs.map((ref) => {
      const row = rows.find((candidate) => candidate.path === ref.path);
      return { ref, exists: Boolean(row), data: () => row.data, createTime: new Timestamp(1, 2), updateTime: new Timestamp(3, 4) };
    }); },
  };
  return { db, reads };
}

test('typed archive retains nanoseconds, GeoPoint, cross-document references, bytes and signed int64', () => {
  const value = { date: new Timestamp(1791885600, 123456789), location: new GeoPoint(16.2, 103.3),
    link: new DocumentReference('shops/shop-1'), bytes: Buffer.from([0, 255]), integer: 9223372036854775807n, count: 2n, nonfinite: NaN };
  const archive = serializeValue(value, { types, typedIntegers: true });
  assert.equal(archive.date._nanoseconds, 123456789);
  assert.deepEqual(archive.location, { __firestoreType: 'geoPoint', latitude: 16.2, longitude: 103.3 });
  assert.equal(archive.link.path, 'shops/shop-1');
  assert.equal(archive.bytes.base64, 'AP8=');
  assert.equal(archive.integer.value, '9223372036854775807');
  assert.equal(archive.count.value, '2');
  assert.equal(archive.nonfinite.value, 'NaN');
  assert.equal(serializeValue(value, { types }).count, 2);
});

test('recursive export includes unknown collections, favorites and children below missing parents', async () => {
  const { db, reads } = fixture([
    { path: 'users/customer', data: { role: 'customer', displayName: 'ลูกค้า' } },
    { path: 'users/customer/favorites/shop-a', data: { shopId: 'shop-a', createdAt: new Timestamp(1, 9) } },
    { path: 'shops/shop-a', data: { name: 'ร้าน', ownerId: 'merchant', preparationMinutes: 10n } },
    { path: 'unknown/missingParent/nested/actualChild', data: { counter: 9223372036854775807n } },
  ]);
  const result = await collectExport({ auth: { listUsers: async () => ({ users: [user('customer'), user('merchant')] }) }, db, types, now });
  assert.equal(result.manifest.firestoreDocuments, 4);
  assert.equal(result.users.length, 1);
  assert.equal(result.shops[0].data.preparationMinutes, 10);
  assert.equal(result.favorites[0].shopId, 'shop-a');
  assert.ok(result.documents.some((record) => record.path === 'unknown/missingParent/nested/actualChild'));
  assert.deepEqual(result.manifest.missingParentDocumentPaths, ['unknown/missingParent']);
  assert.equal(result.manifest.collections['unknown/missingParent/nested'], 1);
  assert.equal(result.documents.find((record) => record.path === 'shops/shop-a').rawData.preparationMinutes.value, '10');
  assert.equal(result.documents[0].createTime._nanoseconds, 2);
  assert.ok(reads.every(([method]) => ['roots', 'listCollections', 'listDocuments', 'getAll'].includes(method)));
  assert.ok(!JSON.stringify(result).includes('secret-must-not-export'));
  assert.match(result.manifest.contentSha256, /^[a-f0-9]{64}$/);
});

test('Auth pagination visits every page and rejects duplicate identities', async () => {
  const { db } = fixture([]);
  const tokens = [];
  const auth = { async listUsers(size, token) { assert.equal(size, 1000); tokens.push(token); return token ? { users: [user('second')] } : { users: [user('first')], pageToken: 'next-page' }; } };
  const result = await collectExport({ auth, db, now });
  assert.equal(result.authUsers.length, 2);
  assert.deepEqual(tokens, [undefined, 'next-page']);
  await assert.rejects(collectExport({ auth: { listUsers: async (_size, token) => token ? { users: [user('same')] } : { users: [user('same')], pageToken: 'next' } }, db, now }), /duplicate UID/);
});

test('permission failure propagates; no fabricated empty-success export', async () => {
  const denied = new Error('PERMISSION_DENIED');
  await assert.rejects(collectExport({ auth: { listUsers: async () => { throw denied; } }, db: {}, now }), /PERMISSION_DENIED/);
  const { db } = fixture([]);
  db.listCollections = async () => { throw denied; };
  await assert.rejects(collectExport({ auth: { listUsers: async () => ({ users: [] }) }, db, now }), /PERMISSION_DENIED/);
});

test('limit and unsupported value stop export rather than silently dropping source data', async () => {
  const { db } = fixture([{ path: 'unknown/one', data: { x: 1 } }, { path: 'unknown/two', data: { x: 2 } }]);
  await assert.rejects(collectExport({ auth: { listUsers: async () => ({ users: [] }) }, db, types, maxDocuments: 1, now }), /limit reached/);
  assert.throws(() => serializeValue(new Date(), { types }), /Unsupported Firestore value type/);
});

test('CLI confines the source project and rejects incomplete or unsafe arguments', () => {
  assert.equal(parseArguments(['--help']).help, true);
  assert.throws(() => parseArguments(['--out', 'backup.json', '--project', 'different-project']), /only reads/);
  assert.throws(() => parseArguments([]), /Provide --out/);
  assert.throws(() => parseArguments(['--out', 'backup.json', '--max-documents', '1.5']), /integer/);
  assert.throws(() => parseArguments(['--out']), /incomplete/);
  assert.throws(() => parseArguments(['--reset', 'true']), /Unknown/);
});
