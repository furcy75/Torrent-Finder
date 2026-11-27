<div align="center">

<img src="assets/icon/app_icon.png" alt="Torrent Seeder Logo" width="128" height="128" />

# Torrent Seeder

**Zelfstandige Torrentzoekmachine (volledige catalogus) met eigen website-extractor, Anti-Malware Sandbox & Multi-Account Seedr.cc-integratie**

*100% zelfstandig op Android, Windows en Linux — Geen server, geen advertenties, geen onveilige browser, 6 talen.*

[🇬🇧 English](README.md) | [🇫🇷 Français](README.fr.md) | [🇪🇸 Español](README.es.md) | [🇩🇪 Deutsch](README.de.md) | **🇳🇱 Nederlands** | [🇮🇹 Italiano](README.it.md)

[![Build & Release](https://github.com/furcy75/Torrent-Finder/actions/workflows/build-release.yml/badge.svg)](https://github.com/furcy75/Torrent-Finder/actions/workflows/build-release.yml)
[![Latest Release](https://img.shields.io/github/v/release/furcy75/Torrent-Finder?color=22c55e&label=Versie)](https://github.com/furcy75/Torrent-Finder/releases/latest)
[![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20Windows%20%7C%20Linux-38bdf8)](#download)
[![GitHub Sponsors](https://img.shields.io/badge/Steunen-GitHub%20Sponsors-db2777?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/furcy75)
[![License: MIT](https://img.shields.io/badge/Licentie-MIT-94a3b8.svg)](LICENSE)

</div>

---

## 🎯 Waarom Torrent Seeder?

**Torrent Seeder** beschermt tegen kwaadaardige advertentiepagina's en valse `.torrent`-bestanden met een **100% lokale, zelfstandige architectuur**:

- **Geen server nodig**: draait volledig zelfstandig op Android, Windows en Linux.
- **Geen WebView / geen browser**: zoekt uitsluitend via directe HTTP-verzoeken (JSON-API's / RSS-XML).
- **Ingebouwde Anti-Malware Sandbox**: controleert elk `.torrent`-bestand in het geheugen binnen een **geïsoleerde Dart Isolate** (blokkeert `.exe`, `.lnk`, `.bat`, RTLO, `../`, wachtwoordarchieven) en herbouwt een schoon `.torrent`-bestand.
- **Interface in 6 talen**: schakel direct tussen **English, Français, Español, Deutsch, Nederlands en Italiano** via het vlaggetje naast Instellingen.

---

## 📦 Download

Download de nieuwste versie via [**GitHub Releases**](https://github.com/furcy75/Torrent-Finder/releases/latest):

| Platform | Bestand | Installatie |
| :--- | :--- | :--- |
| **Android** *(zelfstandig)* | [`TorrentSeeder-Android.apk`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Android.apk) | Installeer de APK direct op je apparaat |
| **Windows** *(Installatie)* | [`TorrentSeeder-Windows-Setup.exe`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Windows-Setup.exe) | Dubbelklik (Visual C++ DLL's inbegrepen) |
| **Windows** *(Portable)* | [`TorrentSeeder-Windows-Portable.zip`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Windows-Portable.zip) | Uitpakken en `safetorrent.exe` starten |
| **Linux** *(Ubuntu / Debian / Mint)* | [`TorrentSeeder-Linux-amd64.deb`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Linux-amd64.deb) | `sudo apt install ./TorrentSeeder-Linux-amd64.deb` |
| **Linux** *(Portable)* | [`TorrentSeeder-Linux-x64.tar.gz`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Linux-x64.tar.gz) | Uitpakken en `./safetorrent` uitvoeren |

---

## ✨ Belangrijkste functies

- **Gescheiden Info-zoekopdracht & bewerkbare Torrent-zoekopdracht**: zoek eerst Film-/Serie-info (optioneel — AlloCiné, Wikidata, TVMaze, IMDb), klik op een titel in de gewenste taal en pas de zoekopdracht vrij aan.
- **Snelfilters, taalvlaggen bij resultaten & veilige NFO-viewer**: actieve seeders, max. grootte, resolutie, codec (`H.264 / x264`, `x265`, `HDR`), CAM/TS standaard uitgesloten, vectorvlaggen wanneer talen in resultaten worden herkend en platte-tekst NFO-viewer.
- **Seedr.cc-integratie (een of meer accounts)**: inloggen met **E-mail & Wachtwoord** (alleen het OAuth-token wordt lokaal opgeslagen, nooit het wachtwoord), handmatige accountkeuze met **vrije ruimte + melding van actieve downloads**, en een **discrete melding «Bestand gedownload»** (zonder bestandsdetails) zodra een transfer klaar is.
- **11 ingebouwde bronnen (volledige catalogus) + Aangepaste websites + Torznab**: Knaben, APIBay, TorrentCSV, YTS (multi-mirror), EZTV, BitSearch, Nyaa, SubsPlease, SolidTorrents, LimeTorrents, Internet Archive (films, series, anime, muziek, boeken, software...), plus **Aangepaste websites** in ⚙️ Instellingen (zoek-URL met `{query}`, HTML/CSS/RSS/JSON-extractie, 2-stapsmodus, Test-knop, JSON Import/Export) en Jackett/Prowlarr.

---

## 💖 Steun het project

**Torrent Seeder** is gratis, open-source en reclamevrij. Je kunt de ontwikkeling steunen via [**GitHub Sponsors**](https://github.com/sponsors/furcy75).

[![Sponsor op GitHub](https://img.shields.io/badge/Doneren-GitHub%20Sponsors-db2777?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/furcy75)

---

## ⚖️ Juridische kennisgeving & Licentie

Torrent Seeder is een technisch hulpmiddel voor het zoeken en controleren van BitTorrent-metadata (`.torrent`). De app host geen auteursrechtelijk beschermde inhoud. Uitgebracht onder de **MIT-licentie** — zie [LICENSE](LICENSE).
