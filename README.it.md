<div align="center">

<img src="assets/icon/app_icon.png" alt="Torrent Seeder Logo" width="128" height="128" />

# Torrent Seeder

**Motore di ricerca Torrent autonomo per Film e Serie TV con Sandbox anti-malware integrata e supporto multi-account Seedr.cc**

*100% autonomo su Android, Windows e Linux — Nessun server, nessuna pubblicità, nessun browser insicuro, interfaccia in 6 lingue.*

[🇬🇧 English](README.md) | [🇫🇷 Français](README.fr.md) | [🇪🇸 Español](README.es.md) | [🇩🇪 Deutsch](README.de.md) | [🇳🇱 Nederlands](README.nl.md) | **🇮🇹 Italiano**

[![Build & Release](https://github.com/furcy75/Torrent-Finder/actions/workflows/build-release.yml/badge.svg)](https://github.com/furcy75/Torrent-Finder/actions/workflows/build-release.yml)
[![Latest Release](https://img.shields.io/github/v/release/furcy75/Torrent-Finder?color=22c55e&label=Versione)](https://github.com/furcy75/Torrent-Finder/releases/latest)
[![Platforms](https://img.shields.io/badge/Piattaforme-Android%20%7C%20Windows%20%7C%20Linux-38bdf8)](#download)
[![GitHub Sponsors](https://img.shields.io/badge/Sostieni-GitHub%20Sponsors-db2777?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/furcy75)
[![License: MIT](https://img.shields.io/badge/Licenza-MIT-94a3b8.svg)](LICENSE)

</div>

---

## 🎯 Perché Torrent Seeder?

**Torrent Seeder** elimina i rischi delle pagine web piene di pubblicità malevole e dei falsi file `.torrent` grazie a un'architettura **100% locale e autonoma**:

- **Nessun server necessario**: funziona completamente in autonomia su Android, Windows e Linux.
- **Nessuna WebView / nessun browser**: effettua solo richieste HTTP dirette (API JSON / RSS XML).
- **Sandbox anti-malware integrata**: analizza ogni `.torrent` in memoria dentro un **Dart Isolate isolato** (blocca `.exe`, `.lnk`, `.bat`, RTLO, `../`, archivi protetti da password) e ricostruisce un `.torrent` pulito.
- **Interfaccia in 6 lingue**: passa istantaneamente tra **English, Français, Español, Deutsch, Nederlands e Italiano** cliccando sulla bandiera accanto alle Impostazioni.

---

## 📦 Download

Scarica l'ultima versione da [**GitHub Releases**](https://github.com/furcy75/Torrent-Finder/releases/latest):

| Piattaforma | File | Installazione |
| :--- | :--- | :--- |
| **Android** *(autonomo)* | [`TorrentSeeder-Android.apk`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Android.apk) | Installa l'APK direttamente sul dispositivo |
| **Windows** *(Installer)* | [`TorrentSeeder-Windows-Setup.exe`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Windows-Setup.exe) | Doppio clic (DLL Visual C++ incluse) |
| **Windows** *(Portatile)* | [`TorrentSeeder-Windows-Portable.zip`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Windows-Portable.zip) | Estrai e avvia `safetorrent.exe` |
| **Linux** *(Ubuntu / Debian / Mint)* | [`TorrentSeeder-Linux-amd64.deb`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Linux-amd64.deb) | `sudo apt install ./TorrentSeeder-Linux-amd64.deb` |
| **Linux** *(Portatile)* | [`TorrentSeeder-Linux-x64.tar.gz`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Linux-x64.tar.gz) | Estrai e avvia `./safetorrent` |

---

## ✨ Funzionalità principali

- **Ricerca informazioni e Ricerca Torrent separate**: cerca prima la scheda Film/Serie (opzionale — AlloCiné, Wikidata, TVMaze, IMDb), clicca su un titolo nella lingua desiderata per compilare la **Ricerca Torrent** e modificala liberamente prima di avviare la ricerca.
- **Filtri rapidi, bandiere nei risultati e Visualizzatore NFO sicuro**: seeder attivi, dimensione massima, risoluzione, codec (`H.264 / x264`, `x265`, `HDR`), esclusione CAM/TS predefinita, bandiere vettoriali quando le lingue sono rilevate nei risultati e NFO in testo semplice.
- **Integrazione Seedr.cc (uno o più account)**: accesso con **Email e Password** (viene salvato solo il token OAuth, mai la password), selettore manuale con **spazio libero + indicatore di download in corso**, e **avviso discreto «File scaricato»** (senza dettagli del file) al termine di un trasferimento.
- **10 fonti integrate + Torznab**: YTS, APIBay, Knaben, TorrentCSV, SolidTorrents, EZTV, BitSearch, Nyaa, LimeTorrents, Internet Archive + Jackett/Prowlarr.

---

## 💖 Sostieni il progetto

**Torrent Seeder** è gratuito, open-source e senza pubblicità. Puoi sostenerne lo sviluppo tramite [**GitHub Sponsors**](https://github.com/sponsors/furcy75).

[![Sponsorizza su GitHub](https://img.shields.io/badge/Dona-GitHub%20Sponsors-db2777?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/furcy75)

---

## ⚖️ Avviso legale e Licenza

Torrent Seeder è uno strumento tecnico per la ricerca e la verifica dei metadati BitTorrent (`.torrent`). Non ospita alcun contenuto protetto da copyright. Distribuito con licenza **MIT** — vedi [LICENSE](LICENSE).
