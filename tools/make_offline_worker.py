#!/usr/bin/env python3
"""Turns web/mq_sw.js into build/web/flutter_service_worker.js.

Usage: python3 tools/make_offline_worker.py build/web

Fills BUILD (changes whenever any file of the build changes, so browsers
install the new worker) and PRECACHE (every file of the build that the app can
need offline), and writes the result over the stub that Flutter generates at
build/web/flutter_service_worker.js. Exits with an error if the build does not
contain the files the app cannot start without.
"""
import hashlib
import json
import os
import sys

SKIP_PREFIXES = ("diagnose/",)
SKIP_NAMES = {"mq_sw.js", "flutter_service_worker.js", ".last_build_id"}
SKIP_SUFFIXES = (".map",)
SKIP_CONTAINS = ("canvaskit/skwasm",)  # the wasm renderer is not used by this build
REQUIRED = ("index.html", "main.dart.js", "flutter_bootstrap.js")


def main(root: str) -> int:
    tpl_path = os.path.join(root, "mq_sw.js")
    if not os.path.isfile(tpl_path):
        print(f"ERROR: {tpl_path} missing (is web/mq_sw.js in the repository?)")
        return 1
    template = open(tpl_path, encoding="utf-8").read()
    if "/*MQ_FILES*/" not in template or "__MQ_BUILD__" not in template:
        print("ERROR: the template lost its placeholders")
        return 1

    files = []
    digest = hashlib.sha256()
    total = 0
    for base, _dirs, names in os.walk(root):
        for name in sorted(names):
            full = os.path.join(base, name)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            if rel in SKIP_NAMES or rel.startswith(SKIP_PREFIXES):
                continue
            if rel.endswith(SKIP_SUFFIXES) or any(s in rel for s in SKIP_CONTAINS):
                continue
            data = open(full, "rb").read()
            digest.update(rel.encode() + b"\0" + hashlib.sha256(data).digest())
            total += len(data)
            files.append(rel)
    files.sort()

    missing = [r for r in REQUIRED if r not in files]
    if missing:
        print("ERROR: the build lacks required files:", ", ".join(missing))
        return 1

    # Folder URLs (".../" and ".../teacher/") are navigations too.
    entries = [""]
    for rel in files:
        entries.append(rel)
        if rel.endswith("/index.html"):
            entries.append(rel[: -len("index.html")])
    entries = sorted(set(entries), key=lambda e: (e != "", e))

    build_id = digest.hexdigest()[:16]
    out = template.replace("__MQ_BUILD__", build_id).replace(
        "/*MQ_FILES*/", ",".join(json.dumps(e, ensure_ascii=False) for e in entries)
    )
    target = os.path.join(root, "flutter_service_worker.js")
    open(target, "w", encoding="utf-8").write(out)
    print(f"offline worker written: build {build_id}, {len(entries)} entries, "
          f"{total / 1048576:.1f} MB of files")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "build/web"))
