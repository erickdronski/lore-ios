#!/usr/bin/env node
import { existsSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const functionsRoot = join(root, "supabase", "functions");

function walk(dir, found = []) {
  if (!existsSync(dir)) return found;
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const st = statSync(full);
    if (st.isDirectory()) walk(full, found);
    else found.push(full);
  }
  return found;
}

const deployable = walk(functionsRoot).filter((path) => {
  const base = path.split("/").pop();
  return base === "index.ts" || base === "index.js" || base.endsWith(".ts");
});

if (deployable.length > 0) {
  console.error("lore-ios must not ship deployable Edge Functions.");
  console.error("Canonical functions live in the lore backend repo.");
  for (const path of deployable) {
    console.error(`Forbidden: ${relative(root, path)}`);
  }
  process.exit(1);
}

const readme = join(functionsRoot, "README.md");
if (!existsSync(readme)) {
  console.error("Missing supabase/functions/README.md quarantine notice.");
  process.exit(1);
}

console.log("Verified lore-ios is not a second Edge Function deploy source.");
