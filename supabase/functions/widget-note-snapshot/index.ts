import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const noteColumns = [
  "id",
  "title",
  "rtf_data",
  "plain_text",
  "encrypted_payload",
  "encryption_version",
  "updated_at",
  "folder_id",
  "is_pinned",
  "is_archived",
  "content_hash",
].join(",");

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

  const body = await req.json().catch(() => null) as WidgetNoteSnapshotRequest | null;
  const refreshToken = body?.refresh_token?.trim();
  const noteID = body?.note_id?.trim();
  if (!refreshToken || !noteID) {
    return json({ error: "Missing refresh token or note ID" }, 400);
  }

  if (!isValidRefreshToken(refreshToken)) {
    return json({ error: "Invalid refresh token format" }, 400);
  }

  if (!isValidUUID(noteID)) {
    return json({ error: "Invalid note ID" }, 400);
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

  const { data: note, error: noteError } = await admin
    .from("notes")
    .select(noteColumns)
    .eq("user_id", tokenRow.user_id)
    .eq("id", noteID)
    .maybeSingle();

  if (noteError) {
    await recordSnapshotAttempt(admin, tokenRow.user_id, tokenHash, noteID, 500, noteError.message);
    return json({ error: noteError.message }, 500);
  }

  if (!note) {
    await recordSnapshotAttempt(admin, tokenRow.user_id, tokenHash, noteID, 404, "Note not found");
    return json({ error: "Note not found" }, 404);
  }

  await recordSnapshotAttempt(admin, tokenRow.user_id, tokenHash, noteID, 200);

  return json({ note });
});

interface WidgetNoteSnapshotRequest {
  refresh_token?: string;
  note_id?: string;
}

async function recordSnapshotAttempt(
  admin: ReturnType<typeof createClient>,
  userID: string,
  tokenHash: string,
  noteID: string,
  status: number,
  error?: string,
) {
  const now = new Date().toISOString();
  const [tokenResult, receiptResult] = await Promise.all([
    admin
      .from("widget_refresh_tokens")
      .update({
        updated_at: now,
        last_snapshot_at: now,
        last_snapshot_note_id: noteID,
        last_snapshot_status: status,
        last_snapshot_error: error ?? null,
      })
      .eq("token_hash", tokenHash),
    admin
      .from("widget_snapshot_receipts")
      .insert({
        user_id: userID,
        token_hash: tokenHash,
        note_id: noteID,
        requested_at: now,
        status,
        error: error ?? null,
      }),
  ]);

  if (tokenResult.error) {
    console.error("Failed to update widget snapshot diagnostics", tokenResult.error.message);
  }

  if (receiptResult.error) {
    console.error("Failed to insert widget snapshot receipt", receiptResult.error.message);
  }
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

function isValidUUID(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
