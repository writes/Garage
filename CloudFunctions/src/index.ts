import { initializeApp } from "firebase-admin/app";
import { parseOilAnalysis } from "./functions/claudeProxy";
import { voiceQuickAdd } from "./functions/voiceQuickAdd";
import { receiptQuickAdd } from "./functions/receiptQuickAdd";
import { confirmReceiptScan } from "./functions/confirmReceiptScan";
import { receiptQuotaStatus } from "./functions/receiptQuotaStatus";
import { handleRevenueCatWebhook } from "./functions/revenueCatWebhook";
import { lookupRecalls } from "./functions/nhtsaRecalls";
import { deleteAccount } from "./functions/deleteAccount";
import { deleteVehicle } from "./functions/deleteVehicle";
import { recomputeVehicleOdometer } from "./functions/recomputeVehicleOdometer";
import { enforceAttachmentProGate } from "./functions/enforceAttachmentProGate";
import { experimentConfig } from "./functions/experimentConfig";

initializeApp();

export {
  deleteAccount,
  deleteVehicle,
  confirmReceiptScan,
  enforceAttachmentProGate,
  experimentConfig,
  handleRevenueCatWebhook,
  lookupRecalls,
  parseOilAnalysis,
  receiptQuickAdd,
  receiptQuotaStatus,
  recomputeVehicleOdometer,
  voiceQuickAdd,
};
