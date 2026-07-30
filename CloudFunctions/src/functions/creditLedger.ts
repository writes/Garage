import { createHash } from "node:crypto";
import { safeQuotaCount } from "./claudeProxy";

/** The one supported consumable maps to ten confirmed receipt credits. */
export const RECEIPT_CREDITS_PACK_DELTA = 10;

/** Monetary quota values and derived scan ceilings must remain safely bounded. */
export const QUOTA_DOMAIN_MAX = 1_000_000;

export const CREDITS_PRODUCT_IDS = new Set([
  "com.writes.harrysplayhouse.credits.receipts10",
]);

export type ReceiptCreditSource = {
  appId: string;
  environment: string;
  store: string;
  transactionId: string;
};

type SourceComponent = keyof ReceiptCreditSource;

export type ReceiptCreditFact = {
  appUserId: string;
  eventId: string;
  kind: "purchase" | "refund" | "reversal";
  source: ReceiptCreditSource;
  timestampMillis: number;
};

export type ReceiptCreditLedger = {
  appId: string;
  clawApplied: boolean;
  createdAtMillis: number;
  environment: string;
  eventIds: string[];
  grantApplied: boolean;
  packDelta?: number;
  productId: string;
  purchaseAtMillis?: number;
  refundAtMillis?: number;
  reversalAtMillis?: number;
  store: string;
  transactionId: string;
  uid?: string;
  updatedAtMillis: number;
};

export type ReceiptCreditsQuota = {
  clawed: number;
  count: number;
  granted: number;
  kind: "receipt_credits";
  reserved: number;
  uid: string;
  updatedAt: string;
};

export type ReceiptCreditFoldResult =
  | { kind: "applied"; ledger: ReceiptCreditLedger; quota: ReceiptCreditsQuota }
  | { kind: "ledger_only"; ledger: ReceiptCreditLedger }
  | { kind: "invalid"; reason: string };

/**
 * Canonicalizes exactly the fields that RevenueCat represents with casing drift. App identifiers
 * and store transaction identifiers are case-preserving (but trim-normalized); store/environment
 * are trim + upper-case normalized. Every document-id and source comparison uses this helper so
 * a v2 lower-case reconciliation result cannot create a second ledger document.
 */
export function canonicalizeSource(value: string, component: SourceComponent): string {
  const trimmed = value.trim();
  return component === "environment" || component === "store" ? trimmed.toUpperCase() : trimmed;
}

export function sha256Hex(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

export function receiptCreditTransactionDocId(source: ReceiptCreditSource): string {
  const canonical = (component: SourceComponent): string => canonicalizeSource(source[component], component);
  return sha256Hex([
    canonical("appId"),
    canonical("store"),
    canonical("environment"),
    canonical("transactionId"),
  ].join("|"));
}

export function receiptCreditUidHash(uid: string): string {
  return sha256Hex(uid);
}

/** Timestamps are not quota counts: permit valid signed epoch milliseconds only. */
export function isTimestampMillis(value: unknown): value is number {
  return typeof value === "number"
    && Number.isFinite(value)
    && Number.isSafeInteger(value)
    && !Number.isNaN(new Date(value).getTime());
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function domainCount(value: unknown, field: string): number | undefined {
  if (safeQuotaCount(value) !== value || (value as number) > QUOTA_DOMAIN_MAX) return undefined;
  return value as number;
}

function optionalDomainCount(value: unknown, field: string): number | undefined | "invalid" {
  if (value === undefined) return undefined;
  return domainCount(value, field) ?? "invalid";
}

function optionalTimestamp(value: unknown): number | undefined | "invalid" {
  if (value === undefined) return undefined;
  return isTimestampMillis(value) ? value : "invalid";
}

function checkedAdd(left: number, right: number): number | undefined {
  return right > QUOTA_DOMAIN_MAX - left ? undefined : left + right;
}

function checkedScanCeiling(granted: number): number | undefined {
  return granted > Math.floor(QUOTA_DOMAIN_MAX / 4) ? undefined : granted * 4;
}

function existingEventIds(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((eventId): eventId is string => typeof eventId === "string").slice(-20)
    : [];
}

function appendEventId(eventIds: string[], eventId: string): string[] {
  return eventIds.includes(eventId) ? eventIds : [...eventIds, eventId].slice(-20);
}

function parseExistingLedger(
  existing: Record<string, unknown> | undefined,
  fact: ReceiptCreditFact,
): ReceiptCreditLedger | { reason: string } {
  const raw = existing ?? {};
  const sourceComponents: SourceComponent[] = ["appId", "store", "environment", "transactionId"];
  const source = {} as ReceiptCreditSource;

  for (const component of sourceComponents) {
    const previous = raw[component];
    if (previous !== undefined && !isNonEmptyString(previous)) {
      return { reason: `invalid_existing_${component}` };
    }
    if (isNonEmptyString(previous)
      && canonicalizeSource(previous, component) !== canonicalizeSource(fact.source[component], component)) {
      // Retained raw source fields make a theoretical hash collision/invariant failure visible;
      // never co-mingle its facts with this transaction.
      return { reason: `source_invariant_mismatch_${component}` };
    }
    source[component] = isNonEmptyString(previous) ? previous : fact.source[component];
  }

  if (raw.productId !== undefined && raw.productId !== "com.writes.harrysplayhouse.credits.receipts10") {
    return { reason: "source_invariant_mismatch_product" };
  }
  if (raw.uid !== undefined && !isNonEmptyString(raw.uid)) return { reason: "invalid_existing_uid" };
  if (raw.grantApplied !== undefined && typeof raw.grantApplied !== "boolean") return { reason: "invalid_existing_grant_marker" };
  if (raw.clawApplied !== undefined && typeof raw.clawApplied !== "boolean") return { reason: "invalid_existing_claw_marker" };

  const packDelta = optionalDomainCount(raw.packDelta, "packDelta");
  const purchaseAtMillis = optionalTimestamp(raw.purchaseAtMillis);
  const refundAtMillis = optionalTimestamp(raw.refundAtMillis);
  const reversalAtMillis = optionalTimestamp(raw.reversalAtMillis);
  const createdAtMillis = optionalTimestamp(raw.createdAtMillis);
  const updatedAtMillis = optionalTimestamp(raw.updatedAtMillis);
  if (
    packDelta === "invalid"
    || purchaseAtMillis === "invalid"
    || refundAtMillis === "invalid"
    || reversalAtMillis === "invalid"
    || createdAtMillis === "invalid"
    || updatedAtMillis === "invalid"
  ) {
    return { reason: "invalid_existing_ledger_number" };
  }
  // The stored packDelta is FROZEN at grant time: validate it as a positive domain value
  // rather than equating it to today's constant, so a future pack-size change cannot make
  // historic ledgers reject their own refunds/reversals (Gemini code-check #1).
  if (packDelta !== undefined && packDelta < 1) {
    return { reason: "invalid_existing_pack_delta" };
  }

  return {
    ...source,
    clawApplied: raw.clawApplied === true,
    createdAtMillis: createdAtMillis ?? fact.timestampMillis,
    environment: source.environment,
    eventIds: existingEventIds(raw.eventIds),
    grantApplied: raw.grantApplied === true,
    productId: "com.writes.harrysplayhouse.credits.receipts10",
    ...(packDelta !== undefined ? { packDelta } : {}),
    ...(purchaseAtMillis !== undefined ? { purchaseAtMillis } : {}),
    ...(refundAtMillis !== undefined ? { refundAtMillis } : {}),
    ...(reversalAtMillis !== undefined ? { reversalAtMillis } : {}),
    store: source.store,
    transactionId: source.transactionId,
    ...(isNonEmptyString(raw.uid) ? { uid: raw.uid } : {}),
    updatedAtMillis: Math.max(updatedAtMillis ?? fact.timestampMillis, fact.timestampMillis),
  };
}

function parseQuota(
  existing: Record<string, unknown> | undefined,
  uid: string,
  updatedAtMillis: number,
): ReceiptCreditsQuota | { reason: string } {
  const raw = existing ?? {};
  const granted = raw.granted === undefined ? 0 : domainCount(raw.granted, "granted");
  const clawed = raw.clawed === undefined ? 0 : domainCount(raw.clawed, "clawed");
  const count = raw.count === undefined ? 0 : domainCount(raw.count, "count");
  const reserved = raw.reserved === undefined ? 0 : domainCount(raw.reserved, "reserved");
  if (granted === undefined || clawed === undefined || count === undefined || reserved === undefined) {
    return { reason: "invalid_existing_quota_number" };
  }

  return {
    clawed,
    count,
    granted,
    kind: "receipt_credits",
    reserved,
    uid,
    updatedAt: new Date(updatedAtMillis).toISOString(),
  };
}

/**
 * Folds one immutable RevenueCat fact into the transaction ledger and its beneficiary quota.
 * The persisted facts (not webhook arrival order) determine the final grant/claw state. This
 * function is pure so every ingress can use exactly the same checked arithmetic and tie rule.
 */
export function foldReceiptCreditFact(
  existingLedger: Record<string, unknown> | undefined,
  existingQuota: Record<string, unknown> | undefined,
  fact: ReceiptCreditFact,
): ReceiptCreditFoldResult {
  if (!isTimestampMillis(fact.timestampMillis)) return { kind: "invalid", reason: "invalid_fact_timestamp" };

  const parsedLedger = parseExistingLedger(existingLedger, fact);
  if ("reason" in parsedLedger) return { kind: "invalid", reason: parsedLedger.reason };
  const ledger: ReceiptCreditLedger = {
    ...parsedLedger,
    eventIds: appendEventId(parsedLedger.eventIds, fact.eventId),
  };

  if (fact.kind === "purchase") {
    // Only a purchase pins the beneficiary. Refund/reversal aliases must never seize it.
    if (!ledger.uid) ledger.uid = fact.appUserId;
    if (ledger.packDelta === undefined) ledger.packDelta = RECEIPT_CREDITS_PACK_DELTA;
    ledger.purchaseAtMillis = ledger.purchaseAtMillis === undefined
      ? fact.timestampMillis
      : Math.min(ledger.purchaseAtMillis, fact.timestampMillis);
  } else if (fact.kind === "refund") {
    ledger.refundAtMillis = ledger.refundAtMillis === undefined
      ? fact.timestampMillis
      : Math.max(ledger.refundAtMillis, fact.timestampMillis);
  } else {
    ledger.reversalAtMillis = ledger.reversalAtMillis === undefined
      ? fact.timestampMillis
      : Math.max(ledger.reversalAtMillis, fact.timestampMillis);
  }

  if (!ledger.uid || ledger.packDelta === undefined || ledger.purchaseAtMillis === undefined) {
    // Refund-first arrivals are durable facts, but cannot credit an unpinned beneficiary yet.
    return { kind: "ledger_only", ledger };
  }

  const parsedQuota = parseQuota(existingQuota, ledger.uid, ledger.updatedAtMillis);
  if ("reason" in parsedQuota) return { kind: "invalid", reason: parsedQuota.reason };
  const quota = { ...parsedQuota };

  if (!ledger.grantApplied) {
    const granted = checkedAdd(quota.granted, ledger.packDelta);
    if (granted === undefined) return { kind: "invalid", reason: "granted_domain_max" };
    quota.granted = granted;
    ledger.grantApplied = true;
  }

  // Equal refund/reversal timestamps favor the customer: only a strictly earlier reversal heals.
  const refundEffective = ledger.refundAtMillis !== undefined
    && (ledger.reversalAtMillis === undefined || ledger.reversalAtMillis < ledger.refundAtMillis);
  const targetClaw = ledger.grantApplied && refundEffective;
  if (targetClaw && !ledger.clawApplied) {
    const clawed = checkedAdd(quota.clawed, ledger.packDelta);
    if (clawed === undefined) return { kind: "invalid", reason: "clawed_domain_max" };
    quota.clawed = clawed;
    ledger.clawApplied = true;
  }
  if (!targetClaw && ledger.clawApplied) {
    quota.clawed = Math.max(0, quota.clawed - ledger.packDelta);
    ledger.clawApplied = false;
  }

  // Receipt admission later derives 4 * granted. Check it here before a webhook can persist a
  // state whose scan ceiling would escape the same monetary domain.
  if (checkedScanCeiling(quota.granted) === undefined) {
    return { kind: "invalid", reason: "scan_ceiling_domain_max" };
  }

  return { kind: "applied", ledger, quota };
}
