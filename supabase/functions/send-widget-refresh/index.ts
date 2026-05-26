import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const invalidTokenReasons = new Set([
  "BadDeviceToken",
  "Unregistered",
]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = getSecretKey();
  if (!supabaseURL || !serviceRoleKey) {
    return json({ error: "Server is not configured" }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) {
    return json({ error: "Missing bearer token" }, 401);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const { data, error: userError } = await admin.auth.getUser(token);
  if (userError || !data.user) {
    return json({ error: "Invalid session" }, 401);
  }

  const apnsConfig = readAPNSConfig();
  if (!apnsConfig) {
    return json({ sent: 0, skipped: true, reason: "APNs is not configured" });
  }

  const { data: tokens, error: tokenError } = await admin
    .from("widget_push_tokens")
    .select("token,environment")
    .eq("user_id", data.user.id);

  if (tokenError) {
    return json({ error: tokenError.message }, 500);
  }

  if (!tokens?.length) {
    return json({ sent: 0 });
  }

  const jwt = await createAPNSJWT(apnsConfig);
  let sent = 0;
  let removed = 0;
  let failed = 0;
  const sentByEnvironment = {
    sandbox: 0,
    production: 0,
  };

  for (const row of tokens as WidgetPushTokenRow[]) {
    const environment = row.environment === "production" ? "production" : "sandbox";
    let result: APNSPushResult;
    try {
      result = await sendAPNSWidgetRefresh(row.token, environment, jwt, apnsConfig);
    } catch (error) {
      result = {
        ok: false,
        shouldRemoveToken: false,
        error: error instanceof Error ? error.message : String(error),
      };
    }

    await recordPushAttempt(admin, data.user.id, row.token, environment, apnsConfig.topic, result);

    if (result.ok) {
      sent += 1;
      sentByEnvironment[environment] += 1;
      continue;
    }

    failed += 1;
    if (result.shouldRemoveToken) {
      removed += 1;
      await admin
        .from("widget_push_tokens")
        .delete()
        .eq("token", row.token);
    }
  }

  return json({ sent, failed, removed, sent_by_environment: sentByEnvironment });
});

interface WidgetPushTokenRow {
  token: string;
  environment?: "sandbox" | "production";
}

interface APNSConfig {
  keyID: string;
  teamID: string;
  privateKey: string;
  topic: string;
}

interface APNSPushResult {
  ok: boolean;
  shouldRemoveToken: boolean;
  status?: number;
  reason?: string;
  error?: string;
  apnsID?: string;
}

function readAPNSConfig(): APNSConfig | null {
  const keyID = Deno.env.get("APNS_KEY_ID")?.trim();
  const teamID = Deno.env.get("APNS_TEAM_ID")?.trim();
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY")?.replaceAll("\\n", "\n").trim();
  const topic = Deno.env.get("APNS_WIDGET_TOPIC")?.trim() ?? "me.johnstonliu.cache.push-type.widgets";

  if (!keyID || !teamID || !privateKey || !topic) {
    return null;
  }

  return { keyID, teamID, privateKey, topic };
}

async function sendAPNSWidgetRefresh(
  deviceToken: string,
  environment: "sandbox" | "production",
  jwt: string,
  config: APNSConfig,
): Promise<APNSPushResult> {
  const host = environment === "production"
    ? "api.push.apple.com"
    : "api.sandbox.push.apple.com";

  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-push-type": "widgets",
      "apns-topic": config.topic,
      "apns-priority": "5",
      "apns-expiration": "0",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        "content-changed": true,
      },
    }),
  });

  const apnsID = response.headers.get("apns-id") ?? undefined;
  if (response.ok) {
    return { ok: true, shouldRemoveToken: false, status: response.status, apnsID };
  }

  const responseBody = await response.text();
  let reason = "";
  try {
    reason = (JSON.parse(responseBody) as { reason?: string }).reason ?? "";
  } catch {
    reason = responseBody;
  }

  return {
    ok: false,
    shouldRemoveToken: response.status === 410 || invalidTokenReasons.has(reason),
    status: response.status,
    reason,
    apnsID,
  };
}

async function recordPushAttempt(
  admin: ReturnType<typeof createClient>,
  userID: string,
  token: string,
  environment: "sandbox" | "production",
  topic: string,
  result: APNSPushResult,
) {
  const now = new Date().toISOString();
  const tokenHash = await sha256Hex(token);
  const tokenUpdate: Record<string, unknown> = {
    last_push_at: now,
    last_push_status: result.status ?? null,
    last_push_reason: result.reason ?? null,
    last_push_error: result.error ?? null,
    last_push_environment: environment,
    last_push_apns_id: result.apnsID ?? null,
  };

  if (result.ok) {
    tokenUpdate.last_push_success_at = now;
  }

  const receipt = {
    user_id: userID,
    token_hash: tokenHash,
    environment,
    topic,
    sent_at: now,
    apns_status: result.status ?? null,
    apns_reason: result.reason ?? null,
    apns_error: result.error ?? null,
    apns_id: result.apnsID ?? null,
    removed: result.shouldRemoveToken,
  };

  const [tokenResult, receiptResult] = await Promise.all([
    admin
      .from("widget_push_tokens")
      .update(tokenUpdate)
      .eq("token", token),
    admin
      .from("widget_push_receipts")
      .insert(receipt),
  ]);

  if (tokenResult.error) {
    console.error("Failed to update widget push token diagnostics", tokenResult.error.message);
  }

  if (receiptResult.error) {
    console.error("Failed to insert widget push receipt", receiptResult.error.message);
  }
}

async function createAPNSJWT(config: APNSConfig) {
  const header = base64URL(JSON.stringify({ alg: "ES256", kid: config.keyID }));
  const claims = base64URL(JSON.stringify({
    iss: config.teamID,
    iat: Math.floor(Date.now() / 1000),
  }));
  const signingInput = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64URL(new Uint8Array(signature))}`;
}

async function sha256Hex(value: string) {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function pemToArrayBuffer(pem: string) {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function base64URL(value: string | Uint8Array) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function getSecretKey() {
  const secretKeysJSON = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (secretKeysJSON) {
    try {
      const secretKeys = JSON.parse(secretKeysJSON) as Record<string, string>;
      return secretKeys.default ?? Object.values(secretKeys)[0];
    } catch {
      return undefined;
    }
  }

  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
}
