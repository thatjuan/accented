#!/usr/bin/env node
/**
 * Publish pipeline for accented.app release artifacts.
 *
 *   node scripts/publish.mjs pull   Sync the host's releases/ down into release-archives/
 *                                   BEFORE generate_appcast runs, so the regenerated feed
 *                                   covers full history (not a single-entry feed that
 *                                   clobbers the host's). The host (R2) is the source of truth.
 *
 *   node scripts/publish.mjs push   Upload release-archives/ to R2. Enclosures, release-notes,
 *                                   and the DMG go up FIRST; appcast.xml goes up LAST,
 *                                   so no client ever fetches a feed entry whose enclosure 404s.
 *
 * Credentials come from .dev.vars (gitignored) or the environment — see .dev.vars.example.
 * Talks to R2 over its S3-compatible API.
 *
 *   Typical release (maintainer machine):
 *     cd web && npm run sync
 *     RELEASE_VERSION=0.1.1 SPARKLE_ED_KEY_FILE=~/accented-sparkle-ed25519-private.key \
 *       NOTARY_KEYCHAIN_PROFILE=… ../Scripts/release.sh
 *     cd web && npm run publish:r2   # only if you used SKIP_PUBLISH=1
 */

import { readFileSync, readdirSync, existsSync, statSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve, basename } from "node:path";
import { fileURLToPath } from "node:url";
import {
  S3Client,
  ListObjectsV2Command,
  GetObjectCommand,
  PutObjectCommand,
} from "@aws-sdk/client-s3";

const __dirname = dirname(fileURLToPath(import.meta.url));
const WEB_DIR = resolve(__dirname, "..");

const RELEASES_PREFIX = "releases/";
const APPCAST_KEY = "appcast.xml";

/** Load KEY=VALUE pairs from web/.dev.vars (if present); process.env always wins. */
function loadEnv() {
  const env = {};
  const devVars = join(WEB_DIR, ".dev.vars");
  if (existsSync(devVars)) {
    for (const raw of readFileSync(devVars, "utf8").split("\n")) {
      const line = raw.trim();
      if (!line || line.startsWith("#")) continue;
      const eq = line.indexOf("=");
      if (eq === -1) continue;
      env[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
    }
  }
  return { ...env, ...process.env };
}

function requireVar(env, name) {
  const v = env[name];
  if (!v) {
    console.error(`ERROR: ${name} is not set. Copy web/.dev.vars.example → web/.dev.vars and fill it in.`);
    process.exit(1);
  }
  return v;
}

function contentTypeFor(name) {
  if (name.endsWith(".zip")) return "application/zip";
  if (name.endsWith(".dmg")) return "application/x-apple-diskimage";
  if (name.endsWith(".html")) return "text/html; charset=utf-8";
  if (name.endsWith(".xml")) return "application/xml";
  if (name.endsWith(".delta")) return "application/octet-stream";
  return "application/octet-stream";
}

const env = loadEnv();
const cmd = process.argv[2];

const BUCKET = env.R2_BUCKET || "accented-releases";
const ARCHIVES_DIR = env.RELEASE_ARCHIVES
  ? resolve(env.RELEASE_ARCHIVES)
  : resolve(WEB_DIR, "..", "release-archives");

let _client;
function getClient() {
  if (!_client) {
    _client = new S3Client({
      region: "auto",
      endpoint: `https://${requireVar(env, "R2_ACCOUNT_ID")}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: requireVar(env, "R2_ACCESS_KEY_ID"),
        secretAccessKey: requireVar(env, "R2_SECRET_ACCESS_KEY"),
      },
    });
  }
  return _client;
}

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks);
}

async function pull() {
  console.log(`==> Pulling ${RELEASES_PREFIX} from r2://${BUCKET} into ${ARCHIVES_DIR}`);
  mkdirSync(ARCHIVES_DIR, { recursive: true });

  let token;
  let count = 0;
  do {
    const list = await getClient().send(
      new ListObjectsV2Command({ Bucket: BUCKET, Prefix: RELEASES_PREFIX, ContinuationToken: token }),
    );
    for (const obj of list.Contents ?? []) {
      const name = basename(obj.Key);
      if (!name) continue;
      const res = await getClient().send(new GetObjectCommand({ Bucket: BUCKET, Key: obj.Key }));
      writeFileSync(join(ARCHIVES_DIR, name), await streamToBuffer(res.Body));
      console.log(`    ↓ ${obj.Key} (${obj.Size} bytes)`);
      count++;
    }
    token = list.IsTruncated ? list.NextContinuationToken : undefined;
  } while (token);

  console.log(`==> Pulled ${count} object(s). generate_appcast will now see full history.`);
}

async function putFile(path, key) {
  await getClient().send(
    new PutObjectCommand({
      Bucket: BUCKET,
      Key: key,
      Body: readFileSync(path),
      ContentType: contentTypeFor(key),
    }),
  );
}

async function push() {
  if (!existsSync(ARCHIVES_DIR)) {
    console.error(`ERROR: ${ARCHIVES_DIR} does not exist. Run a release (release.sh) first.`);
    process.exit(1);
  }
  const entries = readdirSync(ARCHIVES_DIR).filter((n) => statSync(join(ARCHIVES_DIR, n)).isFile());
  const hasAppcast = entries.includes(APPCAST_KEY);
  const artifacts = entries.filter((n) => n !== APPCAST_KEY);

  if (artifacts.length === 0 && !hasAppcast) {
    console.error(`ERROR: ${ARCHIVES_DIR} is empty — nothing to publish.`);
    process.exit(1);
  }

  console.log(`==> Uploading ${artifacts.length} artifact(s) to r2://${BUCKET}/${RELEASES_PREFIX}`);
  for (const name of artifacts) {
    const key = `${RELEASES_PREFIX}${name}`;
    await putFile(join(ARCHIVES_DIR, name), key);
    console.log(`    ↑ ${key} (${contentTypeFor(name)})`);
  }

  if (hasAppcast) {
    console.log("==> Uploading appcast.xml LAST (after all enclosures are live)");
    await putFile(join(ARCHIVES_DIR, APPCAST_KEY), APPCAST_KEY);
    console.log(`    ↑ ${APPCAST_KEY}`);
  } else {
    console.warn("WARNING: no appcast.xml in release-archives/ — uploaded enclosures only.");
  }

  console.log("==> Done. Remember: set the DOWNLOAD_URL var to the new DMG if it changed.");
}

switch (cmd) {
  case "pull":
    await pull();
    break;
  case "push":
    await push();
    break;
  default:
    console.error("Usage: node scripts/publish.mjs <pull|push>");
    process.exit(1);
}
