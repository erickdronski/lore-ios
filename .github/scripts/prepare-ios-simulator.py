"""Prepare the selected Xcode's simulator runtime on a clean GitHub runner."""
import json
import os
import subprocess
import sys
import time


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def runtime_for(inventory, version):
    return next((r for r in inventory["runtimes"]
                 if r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
                 and r["version"] == version and r["isAvailable"]), None)


def main():
    screenshots = sys.argv[1:] == ["screenshots"]
    version = output("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version")
    # CoreSimulator may still be registering the runner's preinstalled image.
    for attempt in range(7):
        inventory = json.loads(output("xcrun", "simctl", "list", "--json"))
        runtime = runtime_for(inventory, version)
        if runtime:
            break
        if attempt < 6:
            time.sleep(5)
    if not runtime:
        subprocess.run(["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", version], check=True)
        inventory = json.loads(output("xcrun", "simctl", "list", "--json"))
        runtime = runtime_for(inventory, version)
    if not runtime:
        sys.exit(f"CoreSimulator has no available iOS {version} runtime after provisioning")

    runtime_id = runtime["identifier"]
    devices = [d for d in inventory["devices"].get(runtime_id, []) if d["isAvailable"]]
    types = runtime.get("supportedDeviceTypes", [])
    # Store screenshots require the exact storefront sizes in fastlane/Snapfile.
    # Unit and StoreKit tests can use any iPhone on the matching runtime.
    requested = ["iPhone 17 Pro Max", "iPad Pro 13-inch (M5)"] if screenshots else [None]
    chosen = []
    for name in requested:
        def matches(label):
            return label == name if name else label.startswith("iPhone ")

        existing = sorted((d for d in devices if matches(d["name"])),
                          key=lambda d: (d["state"] != "Booted", d["name"], d["udid"]))
        if existing:
            device_name, udid = existing[0]["name"], existing[0]["udid"]
        else:
            suitable = sorted((t for t in types if matches(t["name"])), key=lambda t: t["name"])
            if not suitable:
                sys.exit(f"No compatible {name or 'iPhone'} device type on iOS {version}")
            device_name = suitable[0]["name"]
            udid = output("xcrun", "simctl", "create", device_name, suitable[0]["identifier"], runtime_id)
        chosen.append(udid)
        print(f"Selected {device_name}, iOS {version}, {udid}", flush=True)

    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as env:
        print(f"LORE_SIMULATOR_UDID={chosen[0]}", file=env)
        print(f"LORE_SIMULATOR_OS={version}", file=env)


if __name__ == "__main__":
    main()
