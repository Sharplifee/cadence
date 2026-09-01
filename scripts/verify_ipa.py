#!/usr/bin/env python3
"""Check the IPA for the things Apple rejects silently.

Apple accepts the bytes, returns "UPLOAD SUCCEEDED", then creates no build and
emails hours later. Everything checked here is a defect that produces exactly
that behaviour, so it is worth catching on the runner instead.
"""
import plistlib, sys, zipfile, pathlib

REQUIRED = ["CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString",
            "CFBundleExecutable", "CFBundleIconName"]

def main() -> None:
    ipa = pathlib.Path(sys.argv[1])
    problems, checked = [], 0
    with zipfile.ZipFile(ipa) as z:
        plists = [n for n in z.namelist()
                  if n.endswith(".app/Info.plist") and n.startswith("Payload/")]
        for name in sorted(plists):
            d = plistlib.loads(z.read(name))
            bundle = name.split("/")[-2]
            checked += 1
            for key in REQUIRED:
                if key not in d:
                    problems.append(f"{bundle}: missing {key}")
            if "/Watch/" in name:
                if not d.get("WKApplication") and not d.get("WKWatchKitApp"):
                    problems.append(f"{bundle}: neither WKApplication nor WKWatchKitApp")
                if not d.get("WKCompanionAppBundleIdentifier"):
                    problems.append(f"{bundle}: missing WKCompanionAppBundleIdentifier")
            print(f"  checked {bundle}: {d.get('CFBundleIdentifier')} "
                  f"v{d.get('CFBundleShortVersionString')} ({d.get('CFBundleVersion')}) "
                  f"icon={d.get('CFBundleIconName')}")

    if checked < 2:
        problems.append("watch app is not embedded in the IPA")
    if problems:
        print("\nIPA WILL BE REJECTED:")
        for p in problems:
            print("  -", p)
        sys.exit(1)
    print(f"\nIPA looks shippable ({checked} bundles).")

if __name__ == "__main__":
    main()
