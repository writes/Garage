#!/usr/bin/env python3
"""Create the receipt-credits consumable IAP in App Store Connect.

One command, idempotent PER STEP: creates the +10-per-$1 consumable decided
2026-07-29 (HANDOFF / quota spec), its en-US localization, its $0.99 base
price, and its availability — each step is skipped when already present, so a
partial failure (2026-08-03: the localization 409'd on ASC's 55-char
description cap after the record was created) resumes instead of stranding a
half-configured product behind an "already exists" early return.

    python3 scripts/release/create_receipt_credits_iap.py

Credentials resolve exactly as asc.py's (flags/env/config/autodiscovery).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc  # noqa: E402

APP_ID = "6794430547"
PRODUCT_ID = "com.writes.harrysplayhouse.credits.receipts10"
REFERENCE_NAME = "Receipt Saves 10-Pack"
DISPLAY_NAME = "10 Receipt Saves"
# ASC hard-caps IAP localization descriptions at 55 characters (ENTITY_ERROR
# ...TOO_LONG); keep the assert so a copy edit fails HERE, not mid-create.
DESCRIPTION = "Adds 10 receipt-scan saves. Credits never expire."
USD_PRICE = "0.99"
REVIEW_NOTE = (
    "Consumable credit pack: grants 10 additional confirmed receipt-scan saves. "
    "Credits are consumed server-side when a scanned receipt is saved as a service entry."
)


def find_iap(client: asc.AppStoreConnectClient) -> dict | None:
    existing = client.get(f"/v1/apps/{APP_ID}/inAppPurchasesV2", params={"limit": 200})
    return next(
        (i for i in existing.get("data", []) if i["attributes"].get("productId") == PRODUCT_ID),
        None,
    )


def ensure_record(client: asc.AppStoreConnectClient) -> str:
    iap = find_iap(client)
    if iap is not None:
        print(f"record exists: {iap['id']} ({iap['attributes'].get('state')})")
        return iap["id"]
    created = client.post("/v2/inAppPurchases", {
        "data": {
            "type": "inAppPurchases",
            "attributes": {
                "name": REFERENCE_NAME,
                "productId": PRODUCT_ID,
                "inAppPurchaseType": "CONSUMABLE",
                "reviewNote": REVIEW_NOTE,
            },
            "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}},
        }
    })
    iap_id = created["data"]["id"]
    print(f"created IAP {iap_id} {PRODUCT_ID}")
    return iap_id


def ensure_localization(client: asc.AppStoreConnectClient, iap_id: str) -> None:
    locs = client.get(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations", params={"limit": 20})
    if any(l["attributes"].get("locale") == "en-US" for l in locs.get("data", [])):
        print("localization exists")
        return
    client.post("/v1/inAppPurchaseLocalizations", {
        "data": {
            "type": "inAppPurchaseLocalizations",
            "attributes": {"locale": "en-US", "name": DISPLAY_NAME, "description": DESCRIPTION},
            "relationships": {
                "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}
            },
        }
    })
    print("localized en-US")


def ensure_price(client: asc.AppStoreConnectClient, iap_id: str) -> int:
    try:
        schedule = client.get(f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule")
        if schedule.get("data"):
            print("price schedule exists")
            return 0
    except asc.ASCError:
        pass
    points = client.get(
        f"/v2/inAppPurchases/{iap_id}/pricePoints",
        params={"filter[territory]": "USA", "limit": 200},
    )
    point_id = next(
        (p["id"] for p in points.get("data", [])
         if p["attributes"].get("customerPrice") == USD_PRICE),
        None,
    )
    if point_id is None:
        print(f"ERROR: no USA price point at customerPrice={USD_PRICE}; pick one in ASC UI")
        return 1
    client.post("/v1/inAppPurchasePriceSchedules", {
        "data": {
            "type": "inAppPurchasePriceSchedules",
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price-1}"}]},
            },
        },
        "included": [{
            "id": "${price-1}",
            "type": "inAppPurchasePrices",
            "attributes": {"startDate": None},
            "relationships": {
                "inAppPurchasePricePoint": {
                    "data": {"type": "inAppPurchasePricePoints", "id": point_id}
                },
                "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}},
            },
        }],
    })
    print(f"priced at USD {USD_PRICE} (base territory USA)")
    return 0


def ensure_availability(client: asc.AppStoreConnectClient, iap_id: str) -> None:
    try:
        avail = client.get(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseAvailability")
        if avail.get("data"):
            print("availability exists")
            return
    except asc.ASCError:
        pass
    client.post("/v1/inAppPurchaseAvailabilities", {
        "data": {
            "type": "inAppPurchaseAvailabilities",
            "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "availableTerritories": {"data": [{"type": "territories", "id": "USA"}]},
            },
        }
    })
    print("availability set (USA + new territories)")


def main() -> int:
    assert len(DESCRIPTION) <= 55, f"description {len(DESCRIPTION)} chars > ASC cap 55"
    ns = argparse.Namespace(key_id=None, issuer_id=None, key_path=None, scope=None)
    creds = asc.resolve_credentials(ns)
    client = asc.AppStoreConnectClient(creds, timeout_seconds=60.0, scopes=None)

    iap_id = ensure_record(client)
    ensure_localization(client, iap_id)
    if ensure_price(client, iap_id) != 0:
        return 1
    ensure_availability(client, iap_id)
    final = client.get(f"/v2/inAppPurchases/{iap_id}")
    print(f"final state: {final['data']['attributes'].get('state')}")
    print("REMAINING MANUAL STEPS: review screenshot upload + submit alongside an app "
          "version; then map the product in RevenueCat if it should grant via RC instead "
          "of the StoreKit-direct webhook path.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
