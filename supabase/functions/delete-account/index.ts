// In-app account deletion (App Store Guideline 5.1.1(v)): any app that creates
// accounts must let the user delete theirs from within the app.
//
// Security: verify_jwt=true (the gateway rejects malformed tokens), AND we
// re-resolve the caller with their own token via auth.getUser() — the public
// anon key resolves to NO user, so it can never delete anyone (401). The uid
// comes from the verified token, never from the request body, so a caller can
// only ever delete THEIR OWN account. Deletion then runs with the service role
// (available to edge functions as SUPABASE_SERVICE_ROLE_KEY): every user-owned
// row + their private journal-photos objects + the auth user itself.
//
// DEPLOYED to Supabase project uiuwzymvyrgfyiugqlkp (verify_jwt: true).
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Every table that stores this user's rows, with its owning column.
const USER_TABLES: [string, string][] = [
  ["anchor", "created_by"],
  ["badge_award", "user_id"],
  ["contributor_stats", "user_id"],
  ["dive_reads", "user_id"],
  ["entitlements", "user_id"],
  ["lore_entry", "author_id"],
  ["place_media", "user_id"],
  ["saved_place", "user_id"],
  ["user_achievement", "user_id"],
  ["user_prefs", "user_id"],
  ["visit", "user_id"],
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return new Response("POST only", { status: 405, headers: CORS });

  const url = Deno.env.get("SUPABASE_URL")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  // Resolve the caller from THEIR token. The anon key yields no user → 401.
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userErr } = await caller.auth.getUser();
  if (userErr || !user) {
    return new Response(JSON.stringify({ error: "not authenticated" }), {
      status: 401, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
  const uid = user.id;

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // 1. Delete every user-owned row. Continue past a missing table so one gap
  // never leaves the account half-deleted.
  for (const [table, col] of USER_TABLES) {
    const { error } = await admin.from(table).delete().eq(col, uid);
    if (error) console.error(`delete ${table}.${col}`, error.message);
  }

  // 2. Delete the user's private journal photos. Layout is {uid}/{placeID}/*,
  // so walk two levels (storage.list is not recursive).
  try {
    const bucket = admin.storage.from("journal-photos");
    const { data: folders } = await bucket.list(uid, { limit: 1000 });
    const paths: string[] = [];
    for (const folder of folders ?? []) {
      const { data: files } = await bucket.list(`${uid}/${folder.name}`, { limit: 1000 });
      for (const f of files ?? []) paths.push(`${uid}/${folder.name}/${f.name}`);
    }
    if (paths.length) await bucket.remove(paths);
  } catch (e) {
    console.error("journal-photos cleanup", String(e));
  }

  // 3. Delete the auth user itself (GoTrue admin; needs the service role).
  const { error: delErr } = await admin.auth.admin.deleteUser(uid);
  if (delErr) {
    return new Response(JSON.stringify({ error: "auth deletion failed" }), {
      status: 500, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ deleted: true }), {
    headers: { ...CORS, "Content-Type": "application/json" },
  });
});
