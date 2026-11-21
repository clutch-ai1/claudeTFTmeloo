# TFT Set 19 Comp-Planer

Comps, Boards pro Level, Positionen, Items, Champions, Augments, Unlocks, Spiel-Assistent, Item- und Reroll-Rechner für TFT Set 19 (Prismatic Tour).

**Seite:** wird über GitHub Pages aus dem Ordner `docs/` ausgeliefert.

## Wie es funktioniert

- `.github/workflows/update.yml` läuft alle 30 Minuten, holt die aktuellen PBE-Daten von MetaTFT und baut `docs/index.html` neu.
- `sheets/units.png` und `sheets/items.png` sind Screenshots der Unit- und Item-Liste. Das Build-Skript schneidet sie automatisch in einzelne Icons (`docs/icons/`).
  - Unit-Screenshot: kompletter Pool, sortiert nach Kosten und dann Name.
  - Item-Screenshot: Gruppen Tank, Utility, Flex, AD/AP, Mana/Fighter, Components.
- Neue Screenshots einfach hochladen und die alten Dateien ersetzen, die Seite baut sich dann neu.
- `data/history.json` speichert Schnappschüsse für die Trend-Pfeile.

Manuell neu bauen: unter **Actions → Daten aktualisieren → Run workflow**.

Daten: MetaTFT und die offiziellen Set-Daten. Nicht von Riot Games unterstützt oder befürwortet.

## Meine Spiele (Riot API)

Die Seite hat einen Bereich „Meine Spiele“. Er holt deine eigenen TFT-Spiele über die offizielle Riot API.

Einrichten (einmal):
1. Auf https://developer.riotgames.com mit dem Riot-Account einloggen und den API-Schlüssel kopieren.
   Der Entwicklerschlüssel läuft nach 24 Stunden ab. Für dauerhaft: dort „Register Product“ → „Personal API Key“ beantragen.
2. Im Repo: Settings → Secrets and variables → Actions
   - Tab „Secrets“ → New repository secret: Name `RIOT_API_KEY`, Wert = dein Schlüssel
   - Tab „Variables“ → New repository variable: `RIOT_ID` = z. B. `meloo8#EUW`
   - optional Variable `RIOT_SERVER` = `euw1` (Standard) oder `pbe1` zum Testen auf dem PBE
3. Actions → „Daten aktualisieren“ → Run workflow.

Der Schlüssel bleibt geheim, auf der Seite steht nur das Ergebnis (`docs/mystats.json`).
Für PBE-Spiele gibt es auf der Seite zusätzlich „Spiel eintragen“ (wird nur im eigenen Browser gespeichert).
