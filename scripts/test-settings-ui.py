#!/usr/bin/env python3
"""Run settings lifecycle tests in nDOS using a temporary Xcode test target.

Example: python3 scripts/test-settings-ui.py --destination 'platform=iOS Simulator,id=DEVICE_UUID'
The repository's Xcode project is read, never modified. Requires a simulator runtime.
"""
import argparse
import json
import plistlib
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--derived-data", default="/tmp/ndos-settings-ui-build")
    parser.add_argument("--host", choices=["nDOS", "nDOS-X"], default="nDOS")
    parser.add_argument("--source", default="scripts/test-settings-ui.m")
    parser.add_argument("--test-name", default="SettingsTests")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    project = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-", str(repo / "ndos.xcodeproj/project.pbxproj")
    ]))
    objects = project["objects"]
    root = objects[project["rootObject"]]
    host = next(key for key, value in objects.items()
                if value["isa"] == "PBXNativeTarget" and value.get("name") == args.host)
    ids = {name: f"A174000000000000000000{index:02X}" for index, name in enumerate(
        ["target", "config_list", "config", "sources", "source", "build_file", "product", "dependency"], 1)}
    assert not set(ids.values()).intersection(objects)
    objects[ids["target"]] = {
        "isa": "PBXNativeTarget", "name": args.test_name, "productName": args.test_name,
        "productType": "com.apple.product-type.bundle.unit-test",
        "productReference": ids["product"], "buildConfigurationList": ids["config_list"],
        "buildPhases": [ids["sources"]], "dependencies": [ids["dependency"]], "buildRules": []
    }
    objects[ids["config_list"]] = {
        "isa": "XCConfigurationList", "buildConfigurations": [ids["config"]],
        "defaultConfigurationName": "Debug", "defaultConfigurationIsVisible": "0"
    }
    includes = ["dospad/Main", "dospad/Views", "dospad/Theme", "dospad/Util", "SDL/include",
                "SDL/src/video/uikit", "SDL/src/events"]
    if args.host == "nDOS-X":
        includes = ["Experimental/Compatibility", "Experimental/Host", "vendor/SDL2/include",
                    "dospad/**", "SDL/src/video/uikit"]
    objects[ids["config"]] = {
        "isa": "XCBuildConfiguration", "name": "Debug", "buildSettings": {
            "PRODUCT_BUNDLE_IDENTIFIER": "io.turley.ndos.SettingsTests",
            "PRODUCT_NAME": "$(TARGET_NAME)", "GENERATE_INFOPLIST_FILE": "YES",
            "CLANG_ENABLE_OBJC_ARC": "YES", "SDKROOT": "iphonesimulator",
            "USE_HEADERMAP": "NO" if args.host == "nDOS-X" else "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": "15.4", "TARGETED_DEVICE_FAMILY": "1,2",
            "HEADER_SEARCH_PATHS": [str(repo / path) for path in includes],
            "OTHER_LDFLAGS": ["-framework", "UIKit", "-framework", "CoreGraphics"],
            "GCC_PREPROCESSOR_DEFINITIONS": ["NDOS_X_HOST"] if args.host == "nDOS-X" else [],
            "TEST_TARGET_NAME": args.host,
            "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{args.host}.app/{args.host}",
            "BUNDLE_LOADER": "$(TEST_HOST)"
        }
    }
    objects[ids["sources"]] = {"isa": "PBXSourcesBuildPhase", "buildActionMask": "2147483647",
                               "files": [ids["build_file"]], "runOnlyForDeploymentPostprocessing": "0"}
    objects[ids["source"]] = {"isa": "PBXFileReference", "lastKnownFileType": "sourcecode.c.objc",
                              "path": str(repo / args.source), "sourceTree": "<absolute>"}
    objects[ids["build_file"]] = {"isa": "PBXBuildFile", "fileRef": ids["source"]}
    objects[ids["product"]] = {"isa": "PBXFileReference", "explicitFileType": "wrapper.cfbundle",
                               "path": f"{args.test_name}.xctest", "sourceTree": "BUILT_PRODUCTS_DIR"}
    objects[ids["dependency"]] = {"isa": "PBXTargetDependency", "target": host}
    root["targets"].append(ids["target"])
    root["projectDirPath"] = str(repo)
    root.setdefault("attributes", {}).setdefault("TargetAttributes", {})[ids["target"]] = {"TestTargetID": host}
    objects[root["mainGroup"]]["children"].append(ids["source"])
    products = next(value for value in objects.values()
                    if value["isa"] == "PBXGroup" and value.get("name") == "Products")
    products["children"].append(ids["product"])
    with tempfile.TemporaryDirectory(prefix="ndos-settings-tests-") as directory:
        path = Path(directory) / "SettingsTests.xcodeproj"
        path.mkdir()
        (path / "project.pbxproj").write_bytes(plistlib.dumps(project))
        subprocess.run([
            "xcodebuild", "test", "-project", str(path), "-scheme", args.test_name,
            "-destination", args.destination, "-derivedDataPath", str(Path(args.derived_data).resolve()),
            "CODE_SIGNING_ALLOWED=NO", f"SRCROOT={repo}"
        ], cwd=repo, check=True)


if __name__ == "__main__":
    main()
