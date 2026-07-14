// Cloud landmark identification for the scanner's opt-in "What is this?" tap.
// Calls Google Cloud Vision LANDMARK_DETECTION with a DEDICATED server-side key
// (Vault secret `google_vision_key` — the Street View key is iOS-app-restricted
// and Google blocks a server call with it). Fired ONE frame per explicit user
// tap, only after geospatial + on-device Vision came up empty.
// Returns the top landmark (name + confidence + coords), and if it sits on a
// known Lore place, that place's slug so the app can open the real story.
// Returns 204 when nothing is recognized — never a fabricated name.
//
// DEPLOYED to Supabase project uiuwzymvyrgfyiugqlkp (verify_jwt: false, guarded
// by the anon key + a frame-size cap).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { encodeBase64 } from "jsr:@std/encoding/base64";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};
const R = 6371000;
const rad = (d: number) => (d * Math.PI) / 180;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return new Response("POST only", { status: 405, headers: CORS });

  const bytes = new Uint8Array(await req.arrayBuffer());
  // Cost + abuse guard: a real scanner JPEG frame is between ~1KB and ~3MB.
  if (bytes.length < 1024 || bytes.length > 3_000_000) {
    return new Response("bad image", { status: 400, headers: CORS });
  }

  const supa = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
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
      // e.g. "Cloud Vision API has not been used in project ... before or it is
      // disabled" — the one owner step. Surface it (server log + body) so it's
      // actionable, never silently swallowed.
      console.error("vision error", JSON.stringify(json));
      return new Response(JSON.stringify({ error: json?.error?.message ?? "vision failed" }), {
        status: 502, headers: { ...CORS, "Content-Type": "application/json" },
      });
    }
    annotations = json?.responses?.[0]?.landmarkAnnotations;
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
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
