#!/usr/bin/env python3
"""Resolve the next build number from TestFlight rather than from a commit.

Build numbers that live in the repo collide the moment two runs overlap and
need a commit to bump. Asking App Store Connect what the highest build already
is costs one API call and never collides.
"""
import os, time, jwt, requests

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
    # The run number is the floor and the safety net: it is strictly increasing
    # for the life of the repo, so a build number derived from it can never
    # land on a number Apple has already seen and thrown away.
    run = int(os.environ.get("GITHUB_RUN_NUMBER", "0"))

    h = {"Authorization": f"Bearer {token()}"}
    apps = requests.get("https://api.appstoreconnect.apple.com/v1/apps",
                        headers=h, params={"filter[bundleId]": APP_BUNDLE},
                        timeout=30).json().get("data", [])
    highest = 0
    if apps:
        builds = requests.get("https://api.appstoreconnect.apple.com/v1/builds",
                              headers=h,
                              params={"filter[app]": apps[0]["id"], "limit": 200},
                              timeout=30).json().get("data", [])
        highest = max((int(b["attributes"]["version"])
                       for b in builds
                       if b["attributes"].get("version", "").isdigit()), default=0)

    print(f"BUILD_NUMBER={max(highest + 1, run)}")

if __name__ == "__main__":
    main()
