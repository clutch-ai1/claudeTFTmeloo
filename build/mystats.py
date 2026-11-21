"""Meine Spiele: holt die eigenen TFT-Spiele über die offizielle Riot API.

Aufruf: python build/mystats.py <workdir mit set19.json und data.json> <docs-ordner> <cache.json>

Umgebung:
  RIOT_API_KEY  persönlicher Schlüssel von developer.riotgames.com (als GitHub-Secret)
  RIOT_ID       z. B. meloo8#EUW
  RIOT_SERVER   euw1 (Standard) oder pbe1, na1, kr ...

Schreibt <docs>/mystats.json. Ohne Schlüssel oder bei Fehlern steht dort ein Hinweis,
die Seite zeigt ihn an. Bereits geladene Spiele liegen im Cache und werden nicht neu geladen.
"""
import json, os, re, sys, time, urllib.error, urllib.parse, urllib.request

WORK, DOCS, CACHE = sys.argv[1], sys.argv[2], sys.argv[3]
KEY = os.environ.get("RIOT_API_KEY", "").strip()
RIOT_ID = os.environ.get("RIOT_ID", "").strip()
SERVER = (os.environ.get("RIOT_SERVER", "") or "euw1").strip().lower()
MAX_NEW = 40          # neue Spiele pro Lauf (Rate-Limit: 100 Anfragen alle 2 Minuten)

REGIONAL = {"euw1": "europe", "eun1": "europe", "tr1": "europe", "ru": "europe", "me1": "europe",
            "na1": "americas", "br1": "americas", "la1": "americas", "la2": "americas", "pbe1": "americas",
            "kr": "asia", "jp1": "asia",
            "oc1": "sea", "ph2": "sea", "sg2": "sea", "th2": "sea", "tw2": "sea", "vn2": "sea"}


def out(status, **kw):
    data = {"status": status, "updated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "riotId": RIOT_ID, "server": SERVER}
    data.update(kw)
    os.makedirs(DOCS, exist_ok=True)
    json.dump(data, open(os.path.join(DOCS, "mystats.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    print("mystats:", status, {k: (len(v) if isinstance(v, list) else v) for k, v in kw.items() if k in ("games",)})


class ApiError(Exception):
    def __init__(self, code, msg):
        super().__init__(msg)
        self.code = code


def get(url):
    for attempt in range(4):
        req = urllib.request.Request(url, headers={"X-Riot-Token": KEY, "User-Agent": "claudeTFTmeloo"})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 429:
                wait = int(e.headers.get("Retry-After", "10"))
                time.sleep(min(wait, 120))
                continue
            raise ApiError(e.code, e.read().decode("utf-8", "ignore")[:200])
    raise ApiError(429, "Rate-Limit")


def pretty(api):
    s = re.sub(r"^(TFT\d*_|DA_|TFT_Item_|TFT\d+_Augment_|Augment_)", "", api or "")
    s = re.sub(r"([a-z])([A-Z])", r"\1 \2", s).replace("_", " ")
    return s.strip()


def main():
    if not KEY or not RIOT_ID or "#" not in RIOT_ID:
        out("setup", message="Noch nicht eingerichtet: RIOT_API_KEY (Secret) und RIOT_ID (Variable) im GitHub-Repo fehlen.")
        return
    regional = REGIONAL.get(SERVER, "europe")
    acc_cluster = "americas" if SERVER == "pbe1" else regional
    name, tag = RIOT_ID.split("#", 1)

    # Namen aus den Set-Daten
    lk = json.load(open(os.path.join(WORK, "set19.json")))
    names = {}
    for sec in ("units", "items", "augments", "traits"):
        for x in lk.get(sec, []):
            if x.get("apiName") and x.get("name"):
                names[x["apiName"]] = x["name"]
                if x.get("characterName"):
                    names[x["characterName"]] = x["name"]
    data = json.load(open(os.path.join(WORK, "data.json")))
    comps = data.get("comps", [])

    cache = {}
    if os.path.exists(CACHE):
        try:
            cache = json.load(open(CACHE))
        except Exception:
            cache = {}
    if cache.get("riotId") != RIOT_ID or cache.get("server") != SERVER:
        cache = {"riotId": RIOT_ID, "server": SERVER, "matches": {}}

    try:
        acc = get("https://%s.api.riotgames.com/riot/account/v1/accounts/by-riot-id/%s/%s"
                  % (acc_cluster, urllib.parse.quote(name), urllib.parse.quote(tag)))
        puuid = acc["puuid"]
        ids = get("https://%s.api.riotgames.com/tft/match/v1/matches/by-puuid/%s/ids?count=60" % (regional, puuid))
    except ApiError as e:
        msg = {401: "Der API-Schlüssel fehlt oder ist ungültig.",
               403: "Der API-Schlüssel ist abgelaufen oder ungültig. Entwicklerschlüssel laufen nach 24 Stunden ab.",
               404: "Riot-ID %s auf %s nicht gefunden." % (RIOT_ID, SERVER)}.get(e.code, "Riot API Fehler %s" % e.code)
        if SERVER == "pbe1" and e.code in (400, 404):
            msg += " Die Riot API liefert für den PBE vermutlich keine Spiele. Trag deine PBE-Spiele solange auf der Seite selbst ein."
        out("error", message=msg, games=build_games(cache, puuid=None, names=names, comps=comps))
        return

    new = [m for m in ids if m not in cache["matches"]][:MAX_NEW]
    for mid in new:
        try:
            m = get("https://%s.api.riotgames.com/tft/match/v1/matches/%s" % (regional, mid))
        except ApiError as e:
            print("Spiel", mid, "Fehler", e.code)
            continue
        me = next((p for p in m["info"]["participants"] if p.get("puuid") == puuid), None)
        if not me:
            continue
        cache["matches"][mid] = {
            "t": m["info"].get("game_datetime"), "set": m["info"].get("tft_set_number"),
            "q": m["info"].get("queue_id"), "type": m["info"].get("tft_game_type"),
            "p": me.get("placement"), "lv": me.get("level"), "gold": me.get("gold_left"),
            "round": me.get("last_round"), "aug": me.get("augments", []),
            "units": [{"c": u.get("character_id"), "s": u.get("tier"), "i": u.get("itemNames", [])} for u in me.get("units", [])],
            "traits": [{"n": t.get("name"), "u": t.get("num_units"), "st": t.get("style", 0)} for t in me.get("traits", []) if t.get("style", 0) > 0],
        }
    cache["puuid"] = puuid
    json.dump(cache, open(CACHE, "w"), separators=(",", ":"))
    out("ok", games=build_games(cache, puuid, names, comps), newGames=len(new))


def build_games(cache, puuid, names, comps):
    games = []
    for mid, g in cache.get("matches", {}).items():
        units = [{"n": names.get(u["c"], pretty(u["c"])), "s": u["s"], "i": [names.get(i, pretty(i)) for i in u["i"]]} for u in g["units"]]
        un = {u["n"] for u in units}
        best, bs = None, 0.0
        for c in comps:
            core = set(c.get("core", []))
            for opt in c.get("opts", {}).values():
                if opt:
                    core |= set(opt[0]["u"])
                    break
            if not core:
                continue
            j = len(un & core) / len(un | core)
            if j > bs:
                bs, best = j, c
        games.append({
            "id": mid, "t": g["t"], "set": g.get("set"), "q": g.get("q"), "p": g["p"], "lv": g["lv"],
            "gold": g["gold"], "round": g["round"],
            "aug": [names.get(a, pretty(a)) for a in g["aug"]],
            "units": units,
            "traits": [{"n": names.get(t["n"], pretty(t["n"])), "u": t["u"], "st": t["st"]} for t in g["traits"]],
            "comp": best["name"] if best and bs >= 0.35 else None,
            "compAvg": best["avg"] if best and bs >= 0.35 else None,
        })
    games.sort(key=lambda x: x["t"] or 0, reverse=True)
    return games


if __name__ == "__main__":
    main()
