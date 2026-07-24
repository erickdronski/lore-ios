// Cloud landmark identification for the scanner's opt-in "What is this?" tap.
// Calls Google Cloud Vision LANDMARK_DETECTION with a DEDICATED server-side key
// (Vault secret `google_vision_key` — the Street View key is iOS-app-restricted
// and Google blocks a server call with it). Fired ONE frame per explicit user
// tap, only after geospatial + on-device Vision came up empty.
// Returns the top landmark (name + confidence + coords), and if it sits on a
// known Lore place, that place's slug so the app can open the real story.
// Returns 204 when nothing is recognized — never a fabricated name.
//
// Deployed with verify_jwt=true. The function also resolves the caller from the
// bearer token and applies per-user + global daily quotas before a paid call.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { encodeBase64 } from "jsr:@std/encoding/base64";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};
const R = 6371000;
const rad = (d: number) => (d * Math.PI) / 180;
const DAILY_CAP = 400;
const USER_DAILY_CAP = 25;
const MAX_IMAGE_BYTES = 3_000_000;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return new Response("POST only", { status: 405, headers: CORS });

  const url = Deno.env.get("SUPABASE_URL")!;
  const authHeader = req.headers.get("Authorization") ?? "";
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) {
    return new Response("not authenticated", { status: 401, headers: CORS });
  }

  const declaredLength = Number(req.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_IMAGE_BYTES) {
    return new Response("bad image", { status: 413, headers: CORS });
  }

  const bytes = new Uint8Array(await req.arrayBuffer());
  // Cost + abuse guard: a real scanner JPEG frame is between ~1KB and ~3MB.
  if (bytes.length < 1024 || bytes.length > MAX_IMAGE_BYTES) {
    return new Response("bad image", { status: 400, headers: CORS });
  }

  const supa = createClient(
    url,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: quota, error: quotaError } = await supa.rpc(
    "consume_vision_quota",
    { p_user: user.id },
  );
  if (quotaError || !quota || typeof quota !== "object") {
    console.error("vision quota failed", quotaError?.message ?? "invalid response");
    return new Response("quota unavailable", { status: 503, headers: CORS });
  }
  const quotaRecord = quota as Record<string, unknown>;
  const globalCount = Number(quotaRecord.global_count);
  const userCount = Number(quotaRecord.user_count);
  if (!Number.isFinite(globalCount) || !Number.isFinite(userCount)) {
    return new Response("quota unavailable", { status: 503, headers: CORS });
  }
  if (globalCount > DAILY_CAP || userCount > USER_DAILY_CAP) {
    return new Response(JSON.stringify({ error: "daily limit reached" }), {
      status: 429, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  // Uses a DEDICATED Vision key (google_vision_key), not the Street View key:
  // that one is restricted to iOS apps and Google blocks a server-side Vision
  // call with it ("Requests from this iOS client application are blocked").
  const { data: key } = await supa.rpc("get_app_secret", { secret_name: "google_vision_key" });
  if (!key) return new Response("no key", { status: 500, headers: CORS });

  const visionReq = {
    requests: [{
      image: { content: encodeBase64(bytes) },
      features: [{ type: "LANDMARK_DETECTION", maxResults: 3 }],
    }],
  };

  let annotations: any;
  try {
    const resp = await fetch(`https://vision.googleapis.com/v1/images:annotate?key=${key}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(visionReq),
    });
    const json = await resp.json();
    if (!resp.ok) {
      const providerCode = typeof json?.error?.status === "string"
        ? json.error.status
        : "VISION_FAILED";
      console.error("vision provider error", { status: resp.status, code: providerCode });
      return new Response(JSON.stringify({
        error: "vision provider request failed",
        code: providerCode,
      }), {
        status: 502, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    annotations = json?.responses?.[0]?.landmarkAnnotations;
  } catch (e) {
    console.error("vision request failed", e instanceof Error ? e.name : "unknown error");
    return new Response(JSON.stringify({ error: "vision request failed" }), {
      status: 502, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  const top = Array.isArray(annotations) ? annotations[0] : null;
  if (!top?.description) return new Response(null, { status: 204, headers: CORS });

  const loc = top.locations?.[0]?.latLng;
  const lat = typeof loc?.latitude === "number" ? loc.latitude : null;
  const lng = typeof loc?.longitude === "number" ? loc.longitude : null;

  // If the landmark sits on a known Lore place, hand back its slug so the app
  // opens the real dossier instead of a bare name (~220m box).
  let slug: string | null = null;
  if (lat !== null && lng !== null) {
    const dLat = 0.002, dLng = 0.002 / Math.max(0.2, Math.cos(rad(lat)));
    const { data: near } = await supa.from("place_explore").select("slug")
      .gte("lat", lat - dLat).lte("lat", lat + dLat)
      .gte("lng", lng - dLng).lte("lng", lng + dLng).limit(1);
    if (near && near.length) slug = near[0].slug;
  }

  return new Response(JSON.stringify({
    landmark: top.description,
    confidence: typeof top.score === "number" ? top.score : null,
    lat, lng, slug,
  }), { headers: { ...CORS, "Content-Type": "application/json" } });
});
