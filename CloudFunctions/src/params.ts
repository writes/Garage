import { defineSecret } from "firebase-functions/params";

// Firebase Functions v2 only injects Secret Manager values into a function's runtime when the
// secret is declared in its `secrets: [...]` options. Declaring them here (once) and binding them
// per-function is what makes `.value()` return the real secret in prod. Set them with:
//   firebase functions:secrets:set ANTHROPIC_API_KEY
//   firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH
export const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
export const revenueCatWebhookAuth = defineSecret("REVENUECAT_WEBHOOK_AUTH");

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
