import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const jsonHeaders = { "Content-Type": "application/json" };
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const APPLE_AUD = "https://appleid.apple.com";

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

type AuthUser = {
  id: string;
  identities?: Array<{ provider?: string; id?: string }>;
  app_metadata?: { provider?: string; providers?: string[] };
};

function hasAppleIdentity(user: AuthUser): boolean {
  if (user.identities?.some((identity) => identity.provider?.toLowerCase() === "apple")) {
    return true;
  }
  const meta = user.app_metadata;
  if (meta?.provider?.toLowerCase() === "apple") return true;
  if (meta?.providers?.some((provider) => provider.toLowerCase() === "apple")) return true;
  return false;
}

function appleSubjectIds(user: AuthUser): Set<string> {
  const ids = new Set<string>();
  for (const identity of user.identities ?? []) {
    if (identity.provider?.toLowerCase() === "apple" && identity.id) {
      ids.add(identity.id);
    }
  }
  return ids;
}

async function readAppleAuthorizationCode(req: Request): Promise<string | null> {
  const text = await req.text();
  if (!text.trim()) return null;
  try {
    const parsed = JSON.parse(text) as { appleAuthorizationCode?: unknown };
    if (typeof parsed.appleAuthorizationCode !== "string") return null;
    const code = parsed.appleAuthorizationCode.trim();
    return code.length > 0 ? code : null;
  } catch {
    return null;
  }
}

function b64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function utf8(text: string): Uint8Array {
  return new TextEncoder().encode(text);
}

function normalizeApplePrivateKeyPem(raw: string): string {
  const unescaped = raw.replace(/\\n/g, "\n").trim();
  if (unescaped.includes("BEGIN PRIVATE KEY")) return unescaped;
  const body = unescaped.replace(/\s+/g, "");
  const lines = body.match(/.{1,64}/g)?.join("\n") ?? body;
  return `-----BEGIN PRIVATE KEY-----\n${lines}\n-----END PRIVATE KEY-----`;
}

async function importApplePrivateKey(pem: string): Promise<CryptoKey> {
  const b64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(b64), (char) => char.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

async function appleClientSecret(): Promise<string | null> {
  const teamId = Deno.env.get("APPLE_TEAM_ID")?.trim() ?? "";
  const keyId = Deno.env.get("APPLE_KEY_ID")?.trim() ?? "";
  const clientId = Deno.env.get("APPLE_CLIENT_ID")?.trim() ?? "";
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY")?.trim() ?? "";
  if (!teamId || !keyId || !clientId || !privateKey) return null;

  const now = Math.floor(Date.now() / 1000);
  const header = b64url(utf8(JSON.stringify({ alg: "ES256", kid: keyId })));
  const payload = b64url(utf8(JSON.stringify({
    iss: teamId,
    iat: now,
    exp: now + 300,
    aud: APPLE_AUD,
    sub: clientId,
  })));
  const signingInput = `${header}.${payload}`;
  const key = await importApplePrivateKey(normalizeApplePrivateKeyPem(privateKey));
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, utf8(signingInput)),
  );
  return `${signingInput}.${b64url(signature)}`;
}

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split(".");
  if (parts.length < 2) return null;
  try {
    const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/") + "===".slice((parts[1].length + 3) % 4);
    return JSON.parse(atob(padded)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function revokeAppleAuthorization(
  authorizationCode: string,
  expectedSubs: Set<string>,
): Promise<{ ok: true } | { ok: false; error: string; status: number }> {
  const clientId = Deno.env.get("APPLE_CLIENT_ID")?.trim() ?? "";
  const clientSecret = await appleClientSecret();
  if (!clientId || !clientSecret) {
    return { ok: false, error: "apple_misconfigured", status: 500 };
  }

  const tokenBody = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    code: authorizationCode,
    grant_type: "authorization_code",
  });
  const tokenResponse = await fetch(APPLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: tokenBody,
  });
  if (!tokenResponse.ok) {
    return { ok: false, error: "apple_token_exchange_failed", status: 400 };
  }

  const tokenJson = await tokenResponse.json() as {
    access_token?: string;
    refresh_token?: string;
    id_token?: string;
  };
  if (typeof tokenJson.id_token === "string") {
    const payload = decodeJwtPayload(tokenJson.id_token);
    const sub = typeof payload?.sub === "string" ? payload.sub : "";
    if (!sub || (expectedSubs.size > 0 && !expectedSubs.has(sub))) {
      return { ok: false, error: "apple_identity_mismatch", status: 403 };
    }
  }

  const token = tokenJson.refresh_token || tokenJson.access_token;
  if (!token) {
    return { ok: false, error: "apple_token_exchange_failed", status: 400 };
  }
  const hint = tokenJson.refresh_token ? "refresh_token" : "access_token";
  const revokeBody = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    token,
    token_type_hint: hint,
  });
  const revokeResponse = await fetch(APPLE_REVOKE_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: revokeBody,
  });
  if (!revokeResponse.ok) {
    return { ok: false, error: "apple_revoke_failed", status: 502 };
  }
  return { ok: true };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ ok: false, error: "misconfigured" }, 500);
  }

  const appleAuthorizationCode = await readAppleAuthorizationCode(req);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();
  if (userError || !user) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  const authUser = user as AuthUser;
  if (hasAppleIdentity(authUser)) {
    if (!appleAuthorizationCode) {
      return json({ ok: false, error: "apple_reauth_required" }, 400);
    }
    const revocation = await revokeAppleAuthorization(
      appleAuthorizationCode,
      appleSubjectIds(authUser),
    );
    if (!revocation.ok) {
      return json({ ok: false, error: revocation.error }, revocation.status);
    }
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) {
    return json({ ok: false, error: "delete_failed" }, 500);
  }

  return json({ ok: true }, 200);
});
