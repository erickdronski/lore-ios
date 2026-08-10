#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = dirname(dirname(fileURLToPath(import.meta.url)));

function read(path) {
  return readFileSync(join(root, path), "utf8");
}

function requireText(source, needle, label) {
  if (!source.includes(needle)) {
    console.error(`Edge contract failed: ${label}`);
    console.error(`Missing: ${needle}`);
    process.exitCode = 1;
  }
}

function forbidText(source, needle, label) {
  if (source.includes(needle)) {
    console.error(`Edge contract failed: ${label}`);
    console.error(`Forbidden: ${needle}`);
    process.exitCode = 1;
  }
}

const landmark = read("supabase/functions/landmark-id/index.ts");
const plus = read("supabase/functions/_shared/plusEntitlement.mjs");

requireText(
  landmark,
  'import { isActiveProductionPlus } from "../_shared/plusEntitlement.mjs";',
  "landmark-id must use the shared production entitlement guard",
);
requireText(
  landmark,
  '.select("entitlement,status,expires_at,environment")',
  "landmark-id must read entitlement environment and expiry",
);
requireText(
  landmark,
  'JSON.stringify({ error: "plus required" })',
  "landmark-id must fail closed for non-Plus users",
);
requireText(
  landmark,
  '.select("id,slug,city,lat,lng")',
  "landmark-id must fetch stable place id and city for cross-city routing",
);
requireText(
  landmark,
  "place.distance <= 250",
  "landmark-id must enforce the nearest-place distance cutoff",
);
requireText(
  landmark,
  "place_id: matchedPlace?.id ?? null",
  "landmark-id response must include place_id",
);
requireText(
  landmark,
  "place_city: matchedPlace?.city ?? null",
  "landmark-id response must include place_city",
);
requireText(
  landmark,
  'JSON.stringify({ error: "vision failed" })',
  "landmark-id must return a generic Vision failure to clients",
);
requireText(
  landmark,
  'console.error("vision request failed", e);',
  "landmark-id must keep Vision exceptions in server logs",
);
forbidText(
  landmark,
  "String(e)",
  "landmark-id must not return stack trace text to clients",
);
forbidText(
  landmark,
  "json?.error?.message",
  "landmark-id must not return raw provider messages to clients",
);
requireText(
  plus,
  'const ACTIVE_STATUSES = new Set(["active", "trialing", "grace"]);',
  "Plus guard must restrict active statuses",
);
requireText(
  plus,
  'normalizedEnvironment !== "" && normalizedEnvironment !== "production"',
  "Plus guard must reject non-production entitlements",
);

if (process.exitCode) {
  process.exit(process.exitCode);
}

console.log("Verified Lore Edge Function release contracts.");
