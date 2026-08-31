# Cadence provisioning — team XF783932R2, no Mac

Built on the method proven by `nearfield` (iOS + watchOS, same shape as Cadence)
and `parking-sentry`. Nothing here needs macOS, Xcode, or a Keychain.

## Non-negotiables, each one already paid for with a failed run

- **The repo must be PUBLIC.** Private repos on this account hit the Actions
  spending limit and fail in 2–5 seconds with an empty steps array — it looks
  like a broken workflow file and is not. Public repos are unmetered.
- **Certificate type is `DISTRIBUTION`, never `IOS_DISTRIBUTION`.** Apple issues
  the legacy type happily and `security find-identity` calls it valid, but
  Xcode 26 rejects it as "invalid... may have been revoked or expired".
- **POST the CSR as raw PEM text.** Base64-encoding it returns
  `409 ENTITY_ERROR.ATTRIBUTE.INVALID`.
- **A `409 "You already have a current Distribution certificate"` is often
  transient.** Retry the same CSR before concluding anything about caps.
- **Register the new cert ID in Groove's `PROTECTED_CERT_IDS` immediately, with
  no Groove run in flight.** Cert `842Y3PX35F` was destroyed within a minute of
  being minted by a Groove run that was still executing with an empty variable.
- **Never run Xcode automatic signing with `-allowProvisioningUpdates` against
  this team.** That is what caused the August cert churn that killed four
  pipelines. CI-only signing.
- **File the `.p12` base64 in `credentials_registry.value`.** Certs that live
  only in GitHub secrets cannot be read back, which forced a brand-new cert
  every time another repo needed signing.

## Steps

1. Register bundle IDs via `POST /v1/bundleIds` with the ADMIN key `36HS532VZU`:
   `com.connor.cadence` and `com.connor.cadence.watchkitapp`.
2. Enable capabilities on the phone bundle. Cadence needs background audio,
   which is an Info.plist `UIBackgroundModes` entry rather than a capability, so
   there may be nothing to enable here — verify before assuming.
3. Mint the cert: openssl RSA key + CSR, POST raw PEM to `/v1/certificates`,
   type `DISTRIBUTION`. Retain the private key. Build the `.p12` with
   `openssl pkcs12 -export -legacy`.
4. Add the cert ID to `PROTECTED_CERT_IDS` on `Sharplifee/Groove`.
5. Mint two profiles, `IOS_APP_STORE`, both bound to that cert, named exactly
   **"Cadence CI"** and **"Cadence Watch CI"** — `project.yml` and the workflow's
   `ExportOptions.plist` reference them by name, so the names must match.
6. Set eight repo secrets: `APPLE_TEAM_ID`, `APPLE_DIST_P12`,
   `APPLE_DIST_P12_PASSWORD`, `APPLE_PROVISION_PROFILE`,
   `APPLE_PROVISION_PROFILE_WATCH`, `ASC_KEY_ID` (36HS532VZU),
   `ASC_ISSUER_ID`, `ASC_KEY_P8`. Set them **before** pushing the workflow that
   consumes them, or you get a confusing empty-value failure.
7. File the `.p12` base64 in `credentials_registry`.

## The one browser step

`POST /v1/apps` is permanently 403 — Apple only allows app records to be created
in the UI. Until it exists, altool fails with "Cannot determine the Apple ID from
Bundle ID". Create at App Store Connect → **+ New App**: bundle
`com.connor.cadence`, SKU `cadence-001`, name Cadence, iOS, en-US, Full Access.
CI matches on bundle ID, not name, so a name variant needs no code change.
