import { initializeApp } from "firebase-admin/app";
import { parseOilAnalysis } from "./functions/claudeProxy";
import { voiceQuickAdd } from "./functions/voiceQuickAdd";
import { handleRevenueCatWebhook } from "./functions/revenueCatWebhook";
import { lookupRecalls } from "./functions/nhtsaRecalls";
import { deleteAccount } from "./functions/deleteAccount";

initializeApp();

export {
  deleteAccount,
  handleRevenueCatWebhook,
  lookupRecalls,
  parseOilAnalysis,
  voiceQuickAdd,
};
