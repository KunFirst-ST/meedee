import { createHash, randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { access, link, lstat, open, realpath, unlink } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const PROJECT_ID = 'msu-foodnaja';
const MAX_SAFE = BigInt(Number.MAX_SAFE_INTEGER);

/** Preserve native Firestore types without losing timestamp nanoseconds/int64. */
export function serializeValue(value, { types = {}, typedIntegers = false, databaseId = '(default)' } = {}) {
  const recurse = (item) => serializeValue(item, { types, typedIntegers, databaseId });
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return value;
  if (typeof value === 'bigint') {
    return typedIntegers || value > MAX_SAFE || value < -MAX_SAFE
      ? { __firestoreType: 'integer', value: value.toString() }
      : Number(value);
  }
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : { __firestoreType: 'double', value: String(value) };
  }
  if (types.Timestamp && value instanceof types.Timestamp) {
    return { __firestoreType: 'timestamp', _seconds: value.seconds, _nanoseconds: value.nanoseconds };
  }
  if (types.GeoPoint && value instanceof types.GeoPoint) {
    return { __firestoreType: 'geoPoint', latitude: value.latitude, longitude: value.longitude };
  }
  if (types.DocumentReference && value instanceof types.DocumentReference) {
    return { __firestoreType: 'reference', projectId: value.firestore.projectId, databaseId, path: value.path };
  }
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    return { __firestoreType: 'bytes', base64: Buffer.from(value).toString('base64') };
  }
  if (Array.isArray(value)) return value.map(recurse);
  if (typeof value === 'object') {
    if (Object.getPrototypeOf(value) !== Object.prototype && Object.getPrototypeOf(value) !== null) {
      throw new Error(`Unsupported Firestore value type: ${value.constructor?.name ?? 'unknown'}. Export stopped without dropping it.`);
    }
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, recurse(value[key])]));
  }
  throw new Error(`Unsupported Firestore value: ${typeof value}. Export stopped without dropping it.`);
}

function actualDate(value) {
  if (!value) return null;
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) throw new Error('Firebase Auth returned an invalid metadata date.');
  return date.toISOString();
}

function authRecord(user) {
  return {
    uid: user.uid, email: user.email ?? null, emailVerified: user.emailVerified,
    displayName: user.displayName ?? '', phoneNumber: user.phoneNumber ?? null,
    photoURL: user.photoURL ?? null, disabled: user.disabled,
    providerData: user.providerData.map((provider) => ({
      providerId: provider.providerId, uid: provider.uid, displayName: provider.displayName ?? null,
      email: provider.email ?? null, phoneNumber: provider.phoneNumber ?? null, photoURL: provider.photoURL ?? null,
    })),
    customClaims: user.customClaims ?? {}, tenantId: user.tenantId ?? null,
    createdAt: actualDate(user.metadata.creationTime),
    lastSignInAt: actualDate(user.metadata.lastSignInTime),
    lastRefreshAt: actualDate(user.metadata.lastRefreshTime),
    metadata: { creationTime: actualDate(user.metadata.creationTime), lastSignInTime: actualDate(user.metadata.lastSignInTime) },
  };
}

/** Only list/get methods are accepted. No create/update/delete calls exist. */
export async function collectExport({ auth, db, types = {}, databaseId = '(default)', maxDocuments = 50000, now = () => new Date() }) {
  const startedAt = now().toISOString();
  const result = {
    schemaVersion: 1, projectId: PROJECT_ID, databaseId, exportedAt: startedAt,
    authUsers: [], users: [], shops: [], menuItems: [], orders: [], favorites: [], documents: [],
  };
  const userIds = new Set();
  const pageTokens = new Set();
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      if (userIds.has(user.uid)) throw new Error('Auth listing returned a duplicate UID; stop writes and repeat the export.');
      userIds.add(user.uid);
      result.authUsers.push(authRecord(user));
      if (result.authUsers.length > maxDocuments) throw new Error('Auth export limit reached; increase --max-documents explicitly.');
    }
    pageToken = page.pageToken;
    if (pageToken && pageTokens.has(pageToken)) throw new Error('Auth pagination repeated a page token; export refused.');
    if (pageToken) pageTokens.add(pageToken);
  } while (pageToken);

  const seenPaths = new Set();
  const collections = new Map();
  const missingParents = [];
  async function readCollection(collection, depth) {
    if (depth > 100) throw new Error('Firestore nesting exceeds supported depth; export stopped rather than truncating.');
    const refs = await collection.listDocuments();
    refs.sort((left, right) => left.path.localeCompare(right.path, 'en'));
    let count = 0;
    for (let offset = 0; offset < refs.length; offset += 100) {
      const snapshots = await db.getAll(...refs.slice(offset, offset + 100));
      for (const snapshot of snapshots) {
        const ref = snapshot.ref;
        if (seenPaths.has(ref.path)) throw new Error(`Duplicate document path ${ref.path}; export refused.`);
        seenPaths.add(ref.path);
        if (snapshot.exists) {
          if (result.documents.length >= maxDocuments) throw new Error('Firestore document export limit reached; increase --max-documents explicitly.');
          const sourceData = snapshot.data();
          const data = serializeValue(sourceData, { types, databaseId });
          const rawData = serializeValue(sourceData, { types, databaseId, typedIntegers: true });
          result.documents.push({ path: ref.path, data, rawData, createTime: snapshot.createTime ? serializeValue(snapshot.createTime, { types, databaseId }) : null, updateTime: snapshot.updateTime ? serializeValue(snapshot.updateTime, { types, databaseId }) : null });
          count++;
          const segments = ref.path.split('/');
          if (segments.length === 2 && ['users', 'shops', 'menuItems', 'orders'].includes(segments[0])) {
            result[segments[0]].push({ id: ref.id, data });
          } else if (segments.length === 4 && segments[0] === 'users' && segments[2] === 'favorites') {
            result.favorites.push({ userId: segments[1], shopId: segments[3], data });
          }
        } else {
          // listDocuments also returns missing parents with surviving children.
          missingParents.push(ref.path);
        }
        const children = await ref.listCollections();
        children.sort((left, right) => left.path.localeCompare(right.path, 'en'));
        for (const child of children) await readCollection(child, depth + 1);
      }
    }
    collections.set(collection.path, count);
  }
  const roots = await db.listCollections();
  roots.sort((left, right) => left.path.localeCompare(right.path, 'en'));
  for (const root of roots) await readCollection(root, 1);
  result.authUsers.sort((left, right) => left.uid.localeCompare(right.uid, 'en'));
  result.documents.sort((left, right) => left.path.localeCompare(right.path, 'en'));
  result.exportCompletedAt = now().toISOString();
  result.manifest = {
    authUsers: result.authUsers.length, firestoreDocuments: result.documents.length,
    users: result.users.length, shops: result.shops.length, menuItems: result.menuItems.length,
    orders: result.orders.length, favorites: result.favorites.length,
    collections: Object.fromEntries([...collections.entries()].sort(([left], [right]) => left.localeCompare(right, 'en'))),
    missingParentDocumentPaths: missingParents.sort(),
    authPasswordHashesExcluded: true,
    snapshotConsistency: 'sequential-read: pause source writes during final export and reconcile counts/checksums before cutover',
  };
  result.manifest.contentSha256 = createHash('sha256').update(JSON.stringify({ authUsers: result.authUsers, documents: result.documents })).digest('hex');
  return result;
}

export function parseArguments(args) {
  const options = { projectId: PROJECT_ID, databaseId: '(default)', maxDocuments: 50000, out: null, help: false };
  for (let index = 0; index < args.length; index++) {
    const flag = args[index];
    if (flag === '--help' || flag === '-h') { options.help = true; continue; }
    if (!['--project', '--database', '--max-documents', '--out'].includes(flag) || !args[index + 1] || args[index + 1].startsWith('--')) throw new Error(`Unknown or incomplete argument: ${flag}`);
    const value = args[++index];
    if (flag === '--project') options.projectId = value;
    if (flag === '--database') options.databaseId = value;
    if (flag === '--out') options.out = path.resolve(value);
    if (flag === '--max-documents') options.maxDocuments = Number(value);
  }
  if (options.projectId !== PROJECT_ID) throw new Error('This migration only reads project msu-foodnaja.');
  if (!options.help && !options.out) throw new Error('Provide --out pointing to a private JSON file outside the application source.');
  if (!Number.isSafeInteger(options.maxDocuments) || options.maxDocuments < 1 || options.maxDocuments > 1000000) throw new Error('--max-documents must be an integer from 1 to 1000000.');
  if (!/^[A-Za-z0-9()_-]{1,128}$/.test(options.databaseId)) throw new Error('Invalid database ID.');
  return options;
}

async function privateOutput(out) {
  const projectRoot = await realpath(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..'));
  const directory = await realpath(path.dirname(out));
  const relative = path.relative(projectRoot, directory);
  if (relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative))) throw new Error('Store private export outside application source to prevent accidental deployment or packaging.');
  try { await lstat(out); throw new Error('Output already exists; choose a new name. This exporter never overwrites backups.'); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  await access(directory, constants.W_OK);
}

export async function main(args) {
  const options = parseArguments(args);
  if (options.help) {
    console.log('Read-only Firebase migration export (Node >=22)\nnode scripts/export-firebase.mjs --project msu-foodnaja --out C:/private-backups/msu-foodnaja.json\nCredentials: GOOGLE_APPLICATION_CREDENTIALS path or existing authorized Google ADC. Never paste the key into code/chat.\nReads all Auth users and all Firestore root/subcollections including missing parents. No Firebase writes.\nOptional: --max-documents 50000 --database "(default)". Existing backups are never overwritten.');
    return;
  }
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Unset Firebase emulator variables before exporting real source data.');
  await privateOutput(options.out);
  const [{ initializeApp, applicationDefault, deleteApp }, { getAuth }, firestore] = await Promise.all([
    import('firebase-admin/app'), import('firebase-admin/auth'), import('firebase-admin/firestore'),
  ]);
  const app = initializeApp({ credential: applicationDefault(), projectId: options.projectId }, 'msu-food-read-only-migration');
  const db = firestore.getFirestore(app, options.databaseId);
  db.settings({ useBigInt: true });
  try {
    const result = await collectExport({ auth: getAuth(app), db, databaseId: options.databaseId, maxDocuments: options.maxDocuments, types: firestore });
    const bytes = JSON.stringify(result, null, 2)+'\n';
    if (Buffer.byteLength(bytes) > 128 * 1024 * 1024) throw new Error('Export exceeds importer 128 MB limit; no incomplete output was saved. Plan a chunked migration first.');
    const temporary = `${options.out}.partial-${randomUUID()}`;
    const handle = await open(temporary, 'wx', 0o600);
    try {
      try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); }
      // A hard link makes the complete file visible atomically and fails if a
      // backup appeared after the initial check. Existing files stay intact.
      await link(temporary, options.out);
    } finally {
      await unlink(temporary);
    }
    console.log(JSON.stringify({ file: options.out, sourceSha256: createHash('sha256').update(bytes).digest('hex'), manifest: result.manifest }, null, 2));
  } finally {
    await db.terminate();
    await deleteApp(app);
  }
}
