#!/usr/bin/env python3
"""Decide whether an altool non-zero exit actually meant failure.

altool exits 31 on a 409 from Apple's delivery service even after the binary has
landed, and blind-retrying makes it worse — the retry re-uploads a build that is
already present and Apple answers "The entity has been replaced by another
entity". So: upload once, then ask whether the build exists.
"""
import os, sys, time, jwt, requests

APP_BUNDLE = "com.connor.cadence"

def token() -> str:
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "exp": int(time.time()) + 900,
         "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )

def main() -> None:
    wanted = sys.argv[1]
    h = {"Authorization": f"Bearer {token()}"}
    apps = requests.get("https://api.appstoreconnect.apple.com/v1/apps",
                        headers=h, params={"filter[bundleId]": APP_BUNDLE},
                        timeout=30).json().get("data", [])
    if not apps:
        sys.exit("App Store Connect record for "
                 f"{APP_BUNDLE} does not exist — create it in the browser.")
    app_id = apps[0]["id"]

    # Processing is not instant; give it a few minutes before calling it dead.
    for attempt in range(10):
        builds = requests.get("https://api.appstoreconnect.apple.com/v1/builds",
                              headers=h,
                              params={"filter[app]": app_id, "limit": 200},
                              timeout=30).json().get("data", [])
        if any(b["attributes"].get("version") == wanted for b in builds):
            print(f"Build {wanted} is present in App Store Connect — upload succeeded.")
            return
        time.sleep(30)
    sys.exit(
        f"Build {wanted} never appeared in App Store Connect after 5 minutes.\n"
        "altool accepted the bytes but Apple created no build. Usual causes:\n"
        "  - this version+build pair was uploaded and rejected before, so Apple\n"
        "    now discards it silently. Bump the build number.\n"
        "  - processing rejected the binary; Apple emails the account holder\n"
        "    with an ITMS-xxxxx code. Check that mail.")

if __name__ == "__main__":
    main()
