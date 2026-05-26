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

  if (!hasRecentSignIn(data.user)) {
    return json({ error: "Recent email verification is required before deleting this account" }, 401);
  }

  const userID = data.user.id;
  const deletionSteps = [
    admin.from("note_history").delete().eq("user_id", userID),
    admin.from("notes").delete().eq("user_id", userID),
    admin.from("folders").delete().eq("user_id", userID),
    admin.from("sync_keys").delete().eq("user_id", userID),
    admin.from("widget_snapshot_receipts").delete().eq("user_id", userID),
    admin.from("widget_push_receipts").delete().eq("user_id", userID),
    admin.from("widget_push_tokens").delete().eq("user_id", userID),
    admin.from("widget_refresh_tokens").delete().eq("user_id", userID),
  ];

  for (const step of deletionSteps) {
    const { error } = await step;
    if (error) {
      return json({ error: error.message }, 500);
    }
  }

  const { error: deleteUserError } = await admin.auth.admin.deleteUser(userID);
  if (deleteUserError) {
    return json({ error: deleteUserError.message }, 500);
  }

  return json({ deleted: true });
});

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

function hasRecentSignIn(user: { last_sign_in_at?: string | null }) {
  const lastSignInAt = user.last_sign_in_at ? Date.parse(user.last_sign_in_at) : NaN;
  if (!Number.isFinite(lastSignInAt)) {
    return false;
  }

  const maxAgeMs = 5 * 60 * 1000;
  return Date.now() - lastSignInAt <= maxAgeMs;
}
