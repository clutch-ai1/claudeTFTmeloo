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

