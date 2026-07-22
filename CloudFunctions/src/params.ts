import { defineSecret } from "firebase-functions/params";

// Firebase Functions v2 only injects Secret Manager values into a function's runtime when the
// secret is declared in its `secrets: [...]` options. Declaring them here (once) and binding them
// per-function is what makes `.value()` return the real secret in prod. Set them with:
//   firebase functions:secrets:set ANTHROPIC_API_KEY
//   firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH
export const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
export const revenueCatWebhookAuth = defineSecret("REVENUECAT_WEBHOOK_AUTH");
