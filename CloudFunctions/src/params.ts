import { defineSecret } from "firebase-functions/params";

// Firebase Functions v2 only injects Secret Manager values into a function's runtime when the
// secret is declared in its `secrets: [...]` options. Declaring them here (once) and binding them
// per-function is what makes `.value()` return the real secret in prod. Set them with:
//   firebase functions:secrets:set ANTHROPIC_API_KEY
//   firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH
//   firebase functions:secrets:set REVENUECAT_SECRET_API_KEY
export const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
export const revenueCatWebhookAuth = defineSecret("REVENUECAT_WEBHOOK_AUTH");
export const revenueCatSecretApiKey = defineSecret("REVENUECAT_SECRET_API_KEY");

/**
 * Webhook source checks are deliberately ordinary runtime configuration, not secrets. Reading
 * through these accessors keeps local `.env` deployments and deployed function environments on
 * the same code path while leaving reconciliation-only credentials out of webhook availability.
 */
export function revenueCatExpectedAppId(): string | undefined {
  return process.env.RC_EXPECTED_APP_ID;
}

export function revenueCatExpectedStore(): string | undefined {
  return process.env.RC_EXPECTED_STORE;
}

export function revenueCatAllowedEnvironments(): string | undefined {
  return process.env.RC_ALLOWED_ENVIRONMENTS;
}

/** Required only by the RC v2 reconciliation/erasure callables; webhooks must never depend on it. */
export function revenueCatProjectId(): string | undefined {
  return process.env.RC_PROJECT_ID;
}
