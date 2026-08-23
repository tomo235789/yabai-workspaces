# Monetization (open-core, offline licenses)

ywr is **open-core**: this repository (core + free CLI + free menu-bar app) is
MIT. **Pro** features and the paid build live in a separate private repo. Pro is
unlocked by a **license file verified offline** — no servers, no network, so the
"collects nothing, sends nothing" privacy promise holds.

## How it works

- A **license** (`License`) is signed with an **Ed25519 private key** the seller
  holds. The app embeds only the matching **public key** and verifies signatures
  offline (`Sources/YWRCore/Licensing/`).
- A buyer drops the signed `license.json` at
  `~/.config/yabai-workspaces/license.json`. On launch the app loads it; a valid,
  unexpired license lifts the free-tier limits (e.g. the 3-snapshot cap) and
  unlocks Pro features.
- **Until a real public key is embedded, no limits are enforced** — nobody is
  capped without a way to upgrade. Embedding the key "turns on" monetization.

## One-time setup (seller)

1. Generate the signing keypair:
   ```sh
   swift run license-keygen keypair
   # PRIVATE (keep secret): …    ← store in a secrets manager, NEVER commit
   # PUBLIC  (LicensePublicKey.base64): …
   ```
2. Paste the **public** key into `LicensePublicKey.base64`
   (`Sources/YWRCore/Licensing/License.swift`) and release. Keep the **private**
   key only in your fulfillment secret store.

## Per-purchase fulfillment

On a completed purchase, sign a license for the buyer and deliver the file. The
private key is read from the environment (never an argument — that would leak it
via process listings / shell history / logs):

```sh
export YWR_LICENSE_PRIVATE_KEY="<privateBase64>"   # from your secret store
swift run license-keygen sign "buyer@example.com" > license.json
# optional expiry (subscriptions):
swift run license-keygen sign "buyer@example.com" 2027-01-01T00:00:00Z > license.json
```

Automate this in a serverless function / webhook that holds the private key:

- **Store**: [LemonSqueezy](https://www.lemonsqueezy.com/) or
  [Paddle](https://www.paddle.com/) (both handle checkout, VAT, receipts).
- On the store's **order-created / license webhook**, call the signing step and
  email/deliver `license.json` to the buyer.
- A one-time-purchase "Pro" (perpetual) fits a local utility best; use `expiresAt`
  only for subscriptions.

## Notes

- The signature scheme is offline by design; the checkout/webhook integration is
  the only part that touches a network, and it runs on the seller's side, not in
  the app.
- Open-core protection is intentionally *soft*: a technical user can build from
  source or patch the check. Most users buy the notarized, auto-updating build —
  that convenience is what's sold, not obscurity.
