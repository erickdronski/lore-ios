const ACTIVE_STATUSES = new Set(["active", "trialing", "grace"]);

/**
 * Return whether a server-owned entitlement row grants production Lore+.
 * Missing or malformed values fail closed; null expiry supports manual grants.
 *
 * @param {unknown} row
 * @param {Date} [now]
 * @returns {boolean}
 */
export function isActiveProductionPlus(row, now = new Date()) {
  if (!row || typeof row !== "object" || Array.isArray(row)) return false;

  const entitlement = row.entitlement;
  const status = row.status;
  if (entitlement !== "plus" || !ACTIVE_STATUSES.has(status)) return false;

  const environment = row.environment;
  if (environment !== null && environment !== undefined) {
    if (typeof environment !== "string") return false;
    const normalizedEnvironment = environment.trim().toLowerCase();
    if (normalizedEnvironment !== "" && normalizedEnvironment !== "production") {
      return false;
    }
  }

  if (!(now instanceof Date) || !Number.isFinite(now.getTime())) return false;

  const expiresAt = row.expires_at;
  if (expiresAt === null || expiresAt === undefined) return true;
  if (typeof expiresAt !== "string" && !(expiresAt instanceof Date)) return false;

  const expiry = expiresAt instanceof Date ? expiresAt : new Date(expiresAt);
  return Number.isFinite(expiry.getTime()) && expiry.getTime() > now.getTime();
}
