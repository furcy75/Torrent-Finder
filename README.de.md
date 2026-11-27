<div align="center">

<img src="assets/icon/app_icon.png" alt="Torrent Seeder Logo" width="128" height="128" />

# Torrent Seeder

**Autarke Gesamtkatalog-Torrent-Suchmaschine mit eigenem Website-Extraktor, Anti-Malware-Sandbox & Multi-Account-Seedr.cc-Integration**

*100 % autark auf Android, Windows und Linux — Kein Server, keine Werbung, kein unsicherer Browser, 6 Sprachen.*

[🇬🇧 English](README.md) | [🇫🇷 Français](README.fr.md) | [🇪🇸 Español](README.es.md) | **🇩🇪 Deutsch** | [🇳🇱 Nederlands](README.nl.md) | [🇮🇹 Italiano](README.it.md)

[![Build & Release](https://github.com/furcy75/Torrent-Finder/actions/workflows/build-release.yml/badge.svg)](https://github.com/furcy75/Torrent-Finder/actions/workflows/build-release.yml)
[![Latest Release](https://img.shields.io/github/v/release/furcy75/Torrent-Finder?color=22c55e&label=Version)](https://github.com/furcy75/Torrent-Finder/releases/latest)
[![Platforms](https://img.shields.io/badge/Plattformen-Android%20%7C%20Windows%20%7C%20Linux-38bdf8)](#download)
[![GitHub Sponsors](https://img.shields.io/badge/Unterst%C3%BCtzen-GitHub%20Sponsors-db2777?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/furcy75)
[![License: MIT](https://img.shields.io/badge/Lizenz-MIT-94a3b8.svg)](LICENSE)

</div>

---

## 🎯 Warum Torrent Seeder?

**Torrent Seeder** schützt vor werbeverseuchten Webseiten und gefälschten `.torrent`-Dateien durch eine **100 % lokale, eigenständige Architektur**:

- **Kein Server nötig**: läuft vollständig eigenständig auf Android, Windows und Linux.
- **Keine WebView / kein Browser**: sucht ausschließlich über direkte HTTP-Anfragen (JSON-APIs / RSS-XML).
- **Integrierte Anti-Malware-Sandbox**: lädt jede `.torrent`-Datei im Speicher in einem **isolierten Dart-Isolate**, prüft alle enthaltenen Dateien (blockiert `.exe`, `.lnk`, `.bat`, RTLO, `../`, Passwort-Archive) und erstellt eine saubere `.torrent`-Datei.
- **Oberfläche in 6 Sprachen**: wechseln Sie jederzeit per Klick auf die kleine Flagge neben den Einstellungen zwischen **English, Français, Español, Deutsch, Nederlands und Italiano**.

---

## 📦 Download

Laden Sie die aktuelle Version direkt über [**GitHub Releases**](https://github.com/furcy75/Torrent-Finder/releases/latest) herunter:

| Plattform | Datei | Installation |
| :--- | :--- | :--- |
| **Android** *(autark)* | [`TorrentSeeder-Android.apk`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Android.apk) | APK direkt auf dem Gerät installieren |
| **Windows** *(Installer)* | [`TorrentSeeder-Windows-Setup.exe`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Windows-Setup.exe) | Doppelklick (Visual C++ DLLs enthalten) |
| **Windows** *(Portabel)* | [`TorrentSeeder-Windows-Portable.zip`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Windows-Portable.zip) | Entpacken und `safetorrent.exe` starten |
| **Linux** *(Ubuntu / Debian / Mint)* | [`TorrentSeeder-Linux-amd64.deb`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Linux-amd64.deb) | `sudo apt install ./TorrentSeeder-Linux-amd64.deb` |
| **Linux** *(Portabel)* | [`TorrentSeeder-Linux-x64.tar.gz`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Linux-x64.tar.gz) | Entpacken und `./safetorrent` ausführen |

---

## ✨ Hauptfunktionen

- **Getrennte Info-Suche & bearbeitbare Torrent-Suche**: suchen Sie zuerst Film-/Serien-Infos (optional — AlloCiné, Wikidata, TVMaze, IMDb), klicken Sie auf einen Titel in der gewünschten Sprache und passen Sie die Torrent-Suchanfrage frei an.
- **Schnellfilter, Sprachflaggen in Ergebnissen & NFO-Viewer**: aktive Seeder, Maximalgröße, Auflösung, Codec (`H.264 / x264`, `x265`, `HDR`), CAM/TS standardmäßig ausgeblendet, Vektor-Flaggen für erkannte Sprachen in den Ergebnissen und sicherer Klartext-NFO-Viewer.
- **Seedr.cc-Integration (ein oder mehrere Konten)**: Anmeldung mit **E-Mail & Passwort** (nur das OAuth-Token wird gespeichert, niemals das Passwort), manuelle Kontoauswahl mit **freiem Speicher & Anzeige laufender Downloads**, sowie ein **diskretes Pop-up „Datei heruntergeladen“** (ohne Dateidetails) nach Abschluss.
- **11 integrierte Quellen (Gesamtkatalog) + Eigene Websites + Torznab**: Knaben, APIBay, TorrentCSV, YTS (Multi-Mirror), EZTV, BitSearch, Nyaa, SubsPlease, SolidTorrents, LimeTorrents, Internet Archive (Filme, Serien, Anime, Musik, Bücher, Software...), plus **Eigene Websites** in ⚙️ Einstellungen (Such-URL mit `{query}`, HTML/CSS/RSS/JSON-Extraktion, 2-Schritt-Modus, Test-Button, JSON Import/Export) und Jackett/Prowlarr.

---

## 💖 Projekt unterstützen

**Torrent Seeder** ist kostenlos, Open-Source und werbefrei. Sie können die Entwicklung über [**GitHub Sponsors**](https://github.com/sponsors/furcy75) unterstützen.

[![Auf GitHub sponsern](https://img.shields.io/badge/Spenden-GitHub%20Sponsors-db2777?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/furcy75)

---

## ⚖️ Rechtlicher Hinweis & Lizenz

Torrent Seeder ist ein technisches Werkzeug zum Durchsuchen und Prüfen von BitTorrent-Metadaten (`.torrent`). Es werden keine urheberrechtlich geschützten Inhalte gehostet. Lizenziert unter der **MIT-Lizenz** — siehe [LICENSE](LICENSE).
