"""Turn the Studio dumps in .dump/ into src/ and regenerate the Rojo project files.

.dump/lobby.json and .dump/campaign.json come from tools/dump.luau (see README).
A script whose class, source and Enabled match in both places goes to src/common;
everything else goes to src/lobby or src/campaign. Those three folders are rewritten from scratch.

The Endless reference (src/endless, endless.project.json) is a standalone place: it shares nothing
with src/common. Its dump (.dump/endless.json) only ever rewrites src/endless.

Usage: python tools/split.py                  (dumps -> src/ + projects)
       python tools/split.py --projects-only  (src/ -> projects, after hand-moving files)
       python tools/split.py --endless-only   (.dump/endless.json -> src/endless + projects)
"""
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
PLACES = ("lobby", "campaign")
# Places with their own folder only (no src/common).
STANDALONE = ("endless",)
# Separate ports so every place can be served at once.
PORTS = {"lobby": 34872, "campaign": 34873, "endless": 34874}
SERVICES = {"ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer"}
SUFFIX = {"ModuleScript": ".luau", "Script": ".server.luau", "LocalScript": ".client.luau"}
# Containers that are not Folders, for when no dump says so (--projects-only).
KNOWN_CLASSES = {
    "StarterPlayer/StarterPlayerScripts": "StarterPlayerScripts",
    "StarterPlayer/StarterCharacterScripts": "StarterCharacterScripts",
}


def dump_path(place):
    return os.path.join(ROOT, ".dump", place + ".json")


def load(place):
    with open(dump_path(place), encoding="utf-8") as f:
        data = json.load(f)
    entries = {"/".join(e["path"]): e for e in data["entries"]}
    folders = {"/".join(o["path"]): o["class"] for o in data["others"]}
    return entries, folders


def key(e):
    return (e["class"], e["source"], e.get("enabled", True))


def write_script(bucket, e):
    *parents, name = e["path"]
    folder = os.path.join(SRC, bucket, *parents)
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, name + SUFFIX[e["class"]]), "w", encoding="utf-8", newline="") as f:
        f.write(e["source"])
    if e.get("enabled", True) is False:
        with open(os.path.join(folder, name + ".meta.json"), "w", encoding="utf-8") as f:
            json.dump({"properties": {"Enabled": False}}, f, indent=2)
            f.write("\n")


def build_tree(place, folder_classes):
    """Project tree for one place: every script file listed explicitly, from common + place."""
    tree = {"$className": "DataModel"}
    for bucket in (place,) if place in STANDALONE else ("common", place):
        base = os.path.join(SRC, bucket)
        for dirpath, dirnames, files in os.walk(base):
            # Walk in name order so the project files come out the same on every OS.
            dirnames.sort()
            for fn in sorted(files):
                if fn.endswith(".meta.json"):
                    continue
                name = next((fn[: -len(s)] for s in (".server.luau", ".client.luau", ".luau") if fn.endswith(s)), None)
                if name is None:
                    continue
                rel_dir = os.path.relpath(dirpath, base)
                parts = [] if rel_dir == "." else rel_dir.replace("\\", "/").split("/")
                node = tree
                for i, part in enumerate(parts):
                    if part not in node:
                        if i == 0:
                            assert part in SERVICES, part
                            node[part] = {"$className": part, "$ignoreUnknownInstances": True}
                        else:
                            path = "/".join(parts[: i + 1])
                            cls = folder_classes.get(path, KNOWN_CLASSES.get(path, "Folder"))
                            node[part] = {"$className": cls, "$ignoreUnknownInstances": True}
                    node = node[part]
                if name in node:
                    sys.exit(f"duplicate instance {'/'.join(parts + [name])} in {place}")
                rel_file = os.path.relpath(os.path.join(dirpath, fn), ROOT).replace("\\", "/")
                node[name] = {"$path": rel_file}
    return tree


def write_projects(folder_classes):
    for place in PLACES + STANDALONE:
        project = {"name": f"last-light-{place}", "servePort": PORTS[place], "tree": build_tree(place, folder_classes.get(place, {}))}
        with open(os.path.join(ROOT, f"{place}.project.json"), "w", encoding="utf-8") as f:
            json.dump(project, f, indent=2)
            f.write("\n")


def split_standalone(place):
    """A standalone place's dump rewrites its own folder only. Returns its folder classes."""
    entries, folders = load(place)
    shutil.rmtree(os.path.join(SRC, place), ignore_errors=True)
    for e in entries.values():
        write_script(place, e)
    print(f"{place} scripts:", len(entries))
    return folders


def dumped_folders():
    return {p: load(p)[1] for p in PLACES + STANDALONE if os.path.exists(dump_path(p))}


def main():
    if "--projects-only" in sys.argv:
        write_projects({})
        print("projects regenerated")
        return
    if "--endless-only" in sys.argv:
        if os.path.exists(dump_path("endless")):
            split_standalone("endless")
        write_projects(dumped_folders())
        print("projects regenerated")
        return

    dumps = {p: load(p) for p in PLACES}
    (le, lf), (ce, cf) = dumps["lobby"], dumps["campaign"]

    for bucket in ("common",) + PLACES:
        shutil.rmtree(os.path.join(SRC, bucket), ignore_errors=True)

    counts = {"common": 0, "lobby": 0, "campaign": 0}
    for path, e in le.items():
        if path in ce and key(ce[path]) == key(e):
            write_script("common", e)
            counts["common"] += 1
        else:
            write_script("lobby", e)
            counts["lobby"] += 1
    for path, e in ce.items():
        if not (path in le and key(le[path]) == key(e)):
            write_script("campaign", e)
            counts["campaign"] += 1

    folders = {"lobby": lf, "campaign": cf}
    for place in STANDALONE:
        if os.path.exists(dump_path(place)):
            folders[place] = split_standalone(place)
    write_projects(folders)
    print("scripts:", counts)


if __name__ == "__main__":
    main()
