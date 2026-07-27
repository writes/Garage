# Garage — Privacy Policy (DRAFT)

> ⚠️ **DRAFT for operator + legal review.** This is a starting draft grounded in the app's actual
> data flows (see `Garage/Resources/PrivacyInfo.xcprivacy`). Have counsel review it, fill the
> bracketed `[…]` fields, **host it at a stable HTTPS URL**, and set
> `Constants.privacyPolicyURLString` to that URL. Do the same for the Terms. `release-checks.sh`
> blocks release until the `.invalid` placeholders are gone.

**Effective date:** [DATE]
**Contact:** [SUPPORT EMAIL] · **Data controller:** [LEGAL ENTITY / ADDRESS]

## What Garage is
Garage is an iOS app for tracking vehicle ownership, service history, and resale-ready records.

## Information we collect
- **Account identifiers** — when you sign in with **Apple** or **Google**, we receive a user ID and
  email address to create and secure your account.
- **Content you create** — vehicles, service/maintenance logs, photos, receipts, and notes you add.
  Photos/receipts are stored in Firebase Storage; records in Firestore.
- **Voice input (optional, Pro)** — if you use "Speak an Entry", audio is transcribed on-device and
  the resulting **text** is sent to our AI provider to draft an entry you confirm. We do not store
  the audio.
- **Documents you submit (optional, Pro)** — oil-analysis PDFs you choose to import are sent to our
  AI provider for parsing.
- **Usage & diagnostics** — product-interaction analytics (only if you consent) and crash
  diagnostics, to keep the app reliable.
- **Purchases** — subscription status is managed by Apple and our subscription provider
  (RevenueCat). We do **not** receive your full payment-card details.

## How we use it
To provide and sync your records, enable Pro features, process subscriptions, keep the app secure
and reliable, and (with consent) improve the product. We do **not** use your data for third-party
advertising and we do **not** track you across other companies' apps.

## Third parties (sub-processors)
- **Google Firebase** (Authentication, Firestore, Storage, App Check, Crashlytics) — backend + data
  storage. [LINK to Firebase/Google terms]
- **RevenueCat** — subscription management.
  [Privacy policy](https://www.revenuecat.com/privacy)
- **Anthropic** — AI processing of the voice transcript / oil-analysis text you submit.
  [Privacy policy](https://www.anthropic.com/legal/privacy)
- **Apple / Google** — sign-in.

## Data retention & deletion
Your data is retained while your account is active. **You can delete your account and all
associated data at any time from Settings → Delete Account**, which permanently removes your
vehicles, logs, photos, records, and account. Deletion is immediate and irreversible.

## Your rights
Depending on where you live (e.g. GDPR/CCPA), you may have rights to access, correct, export, or
delete your data. Account deletion is available in-app; for other requests contact
[SUPPORT EMAIL].

## Children
Garage is not directed to children under [13/16]. We do not knowingly collect their data.

## Security
Data is encrypted in transit (HTTPS/TLS). Access is scoped per account via server-side security
rules and App Check.

## Changes
We will post changes here and update the effective date.
