#!/usr/bin/env python3
"""Merge control-plane settings before Dokku's native app-json release hook.

Compatibility boundary: Dokku 0.38 app-json's process-specific extraction files.
We leave execution, validation, promotion and cron installation to Dokku.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def merge(base, overlay):
    result = dict(base)
    for key in ("cron", "healthchecks"):
        if key in overlay:
            if key == "healthchecks":
                result[key] = {**result.get(key, {}), **overlay[key]}
            else:
                result[key] = overlay[key]
    if "scripts" in overlay:
        scripts = dict(result.get("scripts", {}))
        dokku = dict(scripts.get("dokku", {}))
        for phase, command in overlay["scripts"].items():
            if command:
                dokku[phase] = command
            else:
                dokku.pop(phase, None)
        if dokku:
            scripts["dokku"] = dokku
        else:
            scripts.pop("dokku", None)
        result["scripts"] = scripts
    return result


def main():
    # pre-release-builder arguments: builder, app, image
    app = sys.argv[2]
    pid = os.environ.get("DOKKU_PID", "")
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]*", app) or not re.fullmatch(r"[A-Za-z0-9_-]+", pid):
        raise RuntimeError("Invalid Dokku deployment identity")
    root = Path(os.environ.get("DOKKU_LIB_ROOT", "/var/lib/dokku"))
    overlay_path = root / "data/raildock-managed" / (app + ".json")
    if not overlay_path.exists():
        return
    overlay = json.loads(overlay_path.read_text())
    if not overlay:
        return
    path = root / "data/app-json" / app / ("app.json." + pid)
    # Absence means this revision has no app.json. Never inherit the last release.
    base = json.loads(path.read_text()) if path.exists() else {}
    result = merge(base, overlay)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(result, stream)
    try:
        subprocess.run(["plugn", "trigger", "app-json-is-valid", app, str(temporary)], check=True)
        os.replace(temporary, path)
        Path(str(path) + ".missing").unlink(missing_ok=True)
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
