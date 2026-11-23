"""Extract XCResult attachments using the names used by the listing."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


SHOT_NAME = re.compile(r"^(store-(?:zh-Hans|zh-Hant|en)-\d{2}-[a-z-]+|paid-01-paywall)(?=[_.]|$)")
ROOT = Path(__file__).resolve().parents[1]


def expected_names():
    config = json.loads((ROOT / "上架资料" / "商店截图.json").read_text(encoding="utf-8"))
    return {"paid-01-paywall.png"} | {
        f"store-{language}-{page['shot']}.png"
        for page in config["pages"] for language in ("en", "zh-Hans", "zh-Hant")
    }


def collect(folder, output):
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    output.mkdir(parents=True, exist_ok=True)
    found = {}
    for test in manifest:
        for attachment in test["attachments"]:
            match = SHOT_NAME.match(attachment.get("suggestedHumanReadableName", ""))
            source = folder / attachment["exportedFileName"]
            if match and source.suffix.lower() == ".png" and source.is_file():
                found[match[1] + ".png"] = source
    missing = expected_names() - found.keys()
    if missing:
        raise ValueError("Missing screenshot attachments: " + ", ".join(sorted(missing)))
    for name, source in found.items():
        shutil.copy2(source, output / name)
    print(f"Exported {len(found)} named screenshots to {output}")


def main():
    result, output = map(Path, sys.argv[1:3])
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as directory:
        folder = Path(directory)
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                        "--output-path", str(folder)], check=True)
        collect(folder, output)


if __name__ == "__main__":
    main()
