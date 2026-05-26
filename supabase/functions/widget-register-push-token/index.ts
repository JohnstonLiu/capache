import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

  const body = await req.json().catch(() => null) as WidgetPushTokenRequest | null;
  const refreshToken = body?.refresh_token?.trim();
  const pushToken = body?.push_token?.trim().toLowerCase();
  const environment = body?.environment === "production" ? "production" : "sandbox";

  if (!refreshToken || !pushToken) {
    return json({ error: "Missing refresh token or push token" }, 400);
  }

  if (!isValidRefreshToken(refreshToken)) {
    return json({ error: "Invalid refresh token format" }, 400);
  }

  if (!isValidPushToken(pushToken)) {
    return json({ error: "Invalid push token" }, 400);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const tokenHash = await sha256Hex(refreshToken);
  const { data: tokenRow, error: tokenError } = await admin
    .from("widget_refresh_tokens")
    .select("user_id")
    .eq("token_hash", tokenHash)
    .maybeSingle();

  if (tokenError) {
    return json({ error: tokenError.message }, 500);
  }

  if (!tokenRow) {
    return json({ error: "Invalid refresh token" }, 401);
  }

  const now = new Date().toISOString();
  const { error: upsertError } = await admin
    .from("widget_push_tokens")
    .upsert({
      token: pushToken,
      user_id: tokenRow.user_id,
      environment,
      platform: "ios",
      updated_at: now,
    }, { onConflict: "token" });

  if (upsertError) {
    return json({ error: upsertError.message }, 500);
  }

  return json({ registered: true });
});

interface WidgetPushTokenRequest {
  refresh_token?: string;
  push_token?: string;
  environment?: string;
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

async function sha256Hex(value: string) {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function isValidRefreshToken(value: string) {
  return /^[A-Za-z0-9_-]{43}$/.test(value);
}

function isValidPushToken(value: string) {
  return value.length >= 32 &&
    value.length <= 512 &&
    value.length % 2 === 0 &&
    /^[0-9a-f]+$/.test(value);
}
