#!/usr/bin/env python3
"""Create the receipt-credits consumable IAP in App Store Connect (operator-run).

One command, idempotent: creates the +10-per-$1 consumable decided 2026-07-29
(HANDOFF / quota spec), its en-US localization, its $0.99 base price, and its
availability. Agents cannot run this (the permission classifier blocks App Store
catalog mutations); the operator runs:

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
DESCRIPTION = "Add 10 more receipt-scan saves to your account. Credits never expire."
USD_PRICE = "0.99"
REVIEW_NOTE = (
    "Consumable credit pack: grants 10 additional confirmed receipt-scan saves. "
    "Credits are consumed server-side when a scanned receipt is saved as a service entry."
)


def main() -> int:
    ns = argparse.Namespace(key_id=None, issuer_id=None, key_path=None, scope=None)
    creds = asc.resolve_credentials(ns)
    client = asc.AppStoreConnectClient(creds, timeout_seconds=60.0, scopes=None)

    existing = client.get(f"/v1/apps/{APP_ID}/inAppPurchasesV2", params={"limit": 200})
    for item in existing.get("data", []):
        if item["attributes"].get("productId") == PRODUCT_ID:
            print(f"already exists: {item['id']} {PRODUCT_ID} ({item['attributes'].get('state')})")
            return 0

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
    print("REMAINING MANUAL STEPS: review screenshot upload + submit alongside an app "
          "version; then map the product in RevenueCat if it should grant via RC instead "
          "of the StoreKit-direct webhook path.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
