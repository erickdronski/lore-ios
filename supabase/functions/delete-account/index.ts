// In-app account deletion (App Store Guideline 5.1.1(v)). The caller is
// resolved from their bearer token, storage is removed first, relational data
// is then deleted/anonymized atomically by delete_my_account_data(p_user), and only
// after both succeed is the Auth user removed.
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

async function collectOwnedPaths(
  bucket: ReturnType<ReturnType<typeof createClient>["storage"]["from"]>,
  prefix: string,
  uid: string,
): Promise<string[]> {
  const paths: string[] = [];
  let offset = 0;

  while (true) {
    const { data, error } = await bucket.list(prefix, {
      limit: 100,
      offset,
      sortBy: { column: "name", order: "asc" },
    });
    if (error) throw new Error(error.message);

    for (const item of data ?? []) {
      const path = prefix ? `${prefix}/${item.name}` : item.name;
      if (!item.id) {
        paths.push(...await collectOwnedPaths(bucket, path, uid));
      } else if (item.owner_id === uid || path === uid || path.startsWith(`${uid}/`)) {
        paths.push(path);
      }
    }

    if (!data || data.length < 100) break;
    offset += data.length;
  }

  return paths;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) return json({ error: "not authenticated" }, 401);

  const uid = user.id;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  try {
    const pathsByBucket = new Map<string, Set<string>>();

    // Include database-tracked contribution media even if it was originally
    // uploaded by a service process and therefore has no Storage owner_id.
    const { data: contributions, error: contributionError } = await admin
      .from("contribution")
      .select("id")
      .eq("contributor_id", uid);
    if (contributionError) throw new Error(contributionError.message);

    const contributionIDs = (contributions ?? []).map((row) => row.id);
    const { data: ownedMedia, error: ownedMediaError } = await admin
      .from("media")
      .select("storage_path")
      .eq("uploader_id", uid);
    if (ownedMediaError) throw new Error(ownedMediaError.message);

    let contributionMedia: { storage_path: string }[] = [];
    if (contributionIDs.length > 0) {
      const result = await admin
        .from("media")
        .select("storage_path")
        .in("contribution_id", contributionIDs);
      if (result.error) throw new Error(result.error.message);
      contributionMedia = result.data ?? [];
    }

    const mediaPaths = [...(ownedMedia ?? []), ...contributionMedia]
      .map((row) => row.storage_path)
      .filter((path): path is string => Boolean(path));
    pathsByBucket.set("lore-media", new Set(mediaPaths));

    const { data: buckets, error: bucketsError } = await admin.storage.listBuckets();
    if (bucketsError) throw new Error(bucketsError.message);

    for (const bucketInfo of buckets ?? []) {
      const bucket = admin.storage.from(bucketInfo.id);
      const owned = await collectOwnedPaths(bucket, "", uid);
      const paths = pathsByBucket.get(bucketInfo.id) ?? new Set<string>();
      for (const path of owned) paths.add(path);
      pathsByBucket.set(bucketInfo.id, paths);
    }

    for (const [bucketID, paths] of pathsByBucket) {
      const all = [...paths];
      for (let index = 0; index < all.length; index += 100) {
        const batch = all.slice(index, index + 100);
        if (batch.length === 0) continue;
        const { error } = await admin.storage.from(bucketID).remove(batch);
        if (error) throw new Error(`${bucketID}: ${error.message}`);
      }
    }
  } catch (error) {
    console.error("account storage cleanup failed", String(error));
    return json({ error: "account storage cleanup failed" }, 500);
  }

  const { error: dataError } = await admin.rpc("delete_my_account_data", {
    p_user: uid,
  });
  if (dataError) {
    console.error("account data cleanup failed", dataError.message);
    return json({ error: "account data cleanup failed" }, 500);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(uid);
  if (deleteError) {
    console.error("auth deletion failed", deleteError.message);
    return json({ error: "auth deletion failed" }, 500);
  }

  return json({ deleted: true });
});
