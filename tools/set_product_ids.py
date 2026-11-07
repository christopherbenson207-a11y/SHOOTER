"""Write the ids in docs/product-ids.json into every Catalogue copy and GameConfig.Store (lobby, campaign, duel)."""
import json, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ids = json.load(open(os.path.join(ROOT, "docs", "product-ids.json")))
allids = {**ids["products"], **ids["passes"]}
LEGACY = {"StarterPack": ("Product", "StarterPack"), "Vip": ("Pass", "Vip"), "Revive": ("Product", "Revive"), "K9": ("Pass", "K9")}

def patch_catalogue(s):
    n = 0
    for key, pid in allids.items():
        s, k = re.subn(r'(\n\s*' + key + r' = \{ Type = "(?:Pass|Product)", Id = )0,', r'\g<1>%d,' % pid, s)
        n += k
        if key.startswith("Item_"):
            s, k = re.subn(r'\b(' + key + r' = )0\b', r'\g<1>%d' % pid, s)
            n += k
    return s, n

def patch_config(s):
    n = 0
    for key, (field, idkey) in LEGACY.items():
        s, k = re.subn(r'(\n\s*' + key + r' = \{ ' + field + r' = )0\b', r'\g<1>%d' % allids[idkey], s)
        n += k
    return s, n

for place in ("lobby", "campaign", "duel"):
    for rel, fn in (("ReplicatedStorage/Shared/Catalogue.luau", patch_catalogue), ("ReplicatedStorage/Shared/GameConfig.luau", patch_config)):
        p = os.path.join(ROOT, "src", place, rel)
        s = open(p, encoding="utf-8").read()
        s2, n = fn(s)
        if s2 != s:
            open(p, "w", encoding="utf-8", newline="").write(s2)
        print(place, rel.split("/")[-1], n)
