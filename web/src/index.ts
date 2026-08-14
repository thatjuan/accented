/**
 * Accented update host. Fronts the R2 RELEASES bucket with cache / content-type /
 * Range / ETag semantics R2 does not give per object.
 *
 *   GET|HEAD /healthz        → 200 ok
 *   GET|HEAD /appcast.xml    → R2 appcast.xml (or 302 to APPCAST_REDIRECT_URL)
 *   GET|HEAD /releases/<f>   → R2 releases/<f>
 *   GET|HEAD /download       → 302 to DOWNLOAD_URL
 *   everything else          → Static Assets, then 404
 */

export interface Env {
  RELEASES: R2Bucket;
  ASSETS: Fetcher;
  APPCAST_REDIRECT_URL?: string;
  DOWNLOAD_URL?: string;
}

const APPCAST_KEY = "appcast.xml";
const CACHE_IMMUTABLE = "public, max-age=31536000, immutable";
const CACHE_REVALIDATE = "public, max-age=300, must-revalidate";

function contentTypeFor(key: string): string {
  if (key.endsWith(".zip")) return "application/zip";
  if (key.endsWith(".dmg")) return "application/x-apple-diskimage";
  if (key.endsWith(".html")) return "text/html; charset=utf-8";
  if (key.endsWith(".xml")) return "application/xml";
  if (key.endsWith(".delta")) return "application/octet-stream";
  return "application/octet-stream";
}

function cacheControlFor(key: string): string {
  if (key === APPCAST_KEY) return CACHE_REVALIDATE;
  if (key.endsWith(".html") || key.endsWith(".xml")) return CACHE_REVALIDATE;
  return CACHE_IMMUTABLE;
}

function notFound(): Response {
  return new Response("Not Found", {
    status: 404,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function methodNotAllowed(): Response {
  return new Response("Method Not Allowed", {
    status: 405,
    headers: { Allow: "GET, HEAD", "Cache-Control": "no-store" },
  });
}

function baseHeaders(key: string, object: R2Object): Headers {
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("Content-Type", contentTypeFor(key));
  headers.set("Cache-Control", cacheControlFor(key));
  headers.set("Accept-Ranges", "bytes");
  if (object.httpEtag) headers.set("ETag", object.httpEtag);
  headers.set("Last-Modified", object.uploaded.toUTCString());
  return headers;
}

async function serveObject(env: Env, key: string, request: Request): Promise<Response> {
  if (request.method !== "GET" && request.method !== "HEAD") return methodNotAllowed();

  const hasRange = request.headers.has("range");

  if (request.method === "HEAD" && !hasRange) {
    const head = await env.RELEASES.head(key);
    if (head === null) return notFound();
    const headers = baseHeaders(key, head);
    headers.set("Content-Length", String(head.size));
    return new Response(null, { status: 200, headers });
  }

  const object = await env.RELEASES.get(key, {
    range: hasRange ? request.headers : undefined,
    onlyIf: request.headers,
  });
  if (object === null) return notFound();

  const headers = baseHeaders(key, object);
  if (!("body" in object)) {
    const precondition =
      request.headers.has("if-match") || request.headers.has("if-unmodified-since");
    return new Response(null, { status: precondition ? 412 : 304, headers });
  }

  let status = 200;
  if (hasRange && object.range) {
    const offset = "offset" in object.range ? (object.range.offset ?? 0) : 0;
    const length =
      "length" in object.range ? (object.range.length ?? object.size - offset) : object.size - offset;
    if (offset === 0 && length >= object.size) {
      headers.set("Content-Length", String(object.size));
    } else {
      headers.set("Content-Range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
      headers.set("Content-Length", String(length));
      status = 206;
    }
  } else {
    headers.set("Content-Length", String(object.size));
  }

  const body = request.method === "HEAD" ? null : object.body;
  return new Response(body, { status, headers });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/healthz") {
      return new Response("ok", {
        status: 200,
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
      });
    }

    if (path === "/appcast.xml") {
      const redirect = env.APPCAST_REDIRECT_URL?.trim();
      if (redirect) {
        return new Response(null, {
          status: 302,
          headers: { Location: redirect, "Cache-Control": CACHE_REVALIDATE },
        });
      }
      return serveObject(env, APPCAST_KEY, request);
    }

    if (path.startsWith("/releases/")) {
      const file = path.slice("/releases/".length);
      if (!file || file.includes("..") || file.includes("/")) return notFound();
      return serveObject(env, `releases/${file}`, request);
    }

    if (path === "/download") {
      const target = env.DOWNLOAD_URL?.trim();
      if (!target) return notFound();
      return new Response(null, {
        status: 302,
        headers: { Location: target, "Cache-Control": "no-store" },
      });
    }

    return env.ASSETS.fetch(request);
  },
};
