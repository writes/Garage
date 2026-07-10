import { initializeApp } from "firebase-admin/app";
import { parseOilAnalysis } from "./functions/claudeProxy";
import { handleRevenueCatWebhook } from "./functions/revenueCatWebhook";
import { lookupRecalls } from "./functions/nhtsaRecalls";

initializeApp();

export {
  handleRevenueCatWebhook,
  lookupRecalls,
  parseOilAnalysis,
};
