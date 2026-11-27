<div align="center">

<img src="assets/icon/app_icon.png" alt="Torrent Seeder Logo" width="128" height="128" />

# Torrent Seeder

**Moteur de recherche Torrent autonome (tout le catalogue) avec extracteur de sites personnalisés, bac à sable anti-virus et intégration Seedr.cc multi-comptes**

*100 % autonome sur Android, Windows et Linux — Zéro serveur, zéro publicité, zéro navigateur piégé, interface en 6 langues.*

[🇬🇧 English](README.md) | **🇫🇷 Français** | [🇪🇸 Español](README.es.md) | [🇩🇪 Deutsch](README.de.md) | [🇳🇱 Nederlands](README.nl.md) | [🇮🇹 Italiano](README.it.md)

[![Build & Release](https://github.com/furcy75/Torrent-Finder/actions/workflows/build-release.yml/badge.svg)](https://github.com/furcy75/Torrent-Finder/actions/workflows/build-release.yml)
[![Latest Release](https://img.shields.io/github/v/release/furcy75/Torrent-Finder?color=22c55e&label=Version)](https://github.com/furcy75/Torrent-Finder/releases/latest)
[![Platforms](https://img.shields.io/badge/Plateformes-Android%20%7C%20Windows%20%7C%20Linux-38bdf8)](#téléchargement)
[![GitHub Sponsors](https://img.shields.io/badge/Soutenir-GitHub%20Sponsors-db2777?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/furcy75)
[![License: MIT](https://img.shields.io/badge/Licence-MIT-94a3b8.svg)](LICENSE)

</div>

---

## 🎯 Pourquoi Torrent Seeder ?

Chercher un fichier `.torrent` sur le web expose habituellement à deux menaces majeures : les **pages web publicitaires piégées** (popups, faux boutons « Download », scripts malveillants) et les **faux torrents** contenant des exécutables déguisés (`Film.mkv.exe`, raccourcis `.lnk`, archives `.rar` piégées).

**Torrent Seeder** élimine ces deux risques grâce à une architecture **100 % locale et autonome** :

- **Aucun serveur requis** : l'APK Android tourne en totale autonomie sur votre téléphone, tout comme l'application Windows et Linux.
- **Aucune WebView / aucun navigateur** : les recherches s'effectuent exclusivement via des requêtes HTTP brutes (APIs JSON / RSS XML / métadonnées).
- **Bac à sable intégré** : chaque `.torrent` est téléchargé en mémoire dans un **Isolate Dart séparé**, inspecté fichier par fichier, puis **reconstruit à neuf** sans métadonnées externes avant d'être enregistré ou envoyé vers Seedr.
- **Interface multilingue (6 langues)** : changez instantanément entre **English, Français, Español, Deutsch, Nederlands et Italiano** via le drapeau situé à côté des paramètres.

---

## 📦 Téléchargement

Récupérez directement la dernière version prête à l'emploi depuis [**GitHub Releases**](https://github.com/furcy75/Torrent-Finder/releases/latest) :

| Plateforme | Fichier | Installation |
| :--- | :--- | :--- |
| **Android** *(autonome)* | [`TorrentSeeder-Android.apk`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Android.apk) | Installer l'APK directement sur le téléphone |
| **Windows** *(Installateur)* | [`TorrentSeeder-Windows-Setup.exe`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Windows-Setup.exe) | Double-clic (DLLs Visual C++ incluses, zéro prérequis) |
| **Windows** *(Portable)* | [`TorrentSeeder-Windows-Portable.zip`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Windows-Portable.zip) | Décompresser et lancer `safetorrent.exe` |
| **Linux** *(Ubuntu / Debian / Mint)* | [`TorrentSeeder-Linux-amd64.deb`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Linux-amd64.deb) | `sudo apt install ./TorrentSeeder-Linux-amd64.deb` |
| **Linux** *(Portable)* | [`TorrentSeeder-Linux-x64.tar.gz`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Linux-x64.tar.gz) | Décompresser et lancer `./safetorrent` |

---

## ✨ Fonctionnalités principales

- **Recherche d'informations & Recherche Torrent séparées** : recherchez d'abord la fiche Film/Série (optionnel — AlloCiné, Wikidata, TVMaze, IMDb), cliquez sur un titre dans la langue souhaitée pour remplir le champ **Recherche Torrent**, puis modifiez librement votre requête avant de lancer la recherche.
- **Filtres rapides, drapeaux dans les résultats & Visionneuse NFO** : seeders actifs, taille max, résolution, codec (`H.264 / x264`, `x265`, `HDR`), exclusion CAM/TS par défaut, affichage de drapeaux vectoriels lorsque les langues sont détectées dans les résultats, et NFO texte brut sécurisé.
- **Intégration Seedr.cc (un ou plusieurs comptes)** : connexion par **Email & Mot de passe** (seul le jeton OAuth est conservé localement, jamais le mot de passe), sélecteur manuel de compte avec **quota libre + indicateur de téléchargement en cours**, et **pop-up discret « Fichier téléchargé »** (sans détail de fichier) dès qu'un transfert se termine.
- **11 sources intégrées (tout le catalogue) + Sites web personnalisés + Torznab** : Knaben, APIBay (NFO), TorrentCSV, YTS (multi-miroirs), EZTV, BitSearch, Nyaa, SubsPlease, SolidTorrents, LimeTorrents, Internet Archive — recherche complète sans restriction (films, séries, animés, musique, livres, logiciels, jeux...), plus **Sites web personnalisés** dans ⚙️ Paramètres (URL de recherche avec `{query}`, extraction auto HTML/RSS/JSON, sélecteurs CSS optionnels, mode 2 étapes, bouton Tester, Import/Export JSON) et Jackett/Prowlarr.

---

## 💖 Soutenir le projet

**Torrent Seeder** est gratuit, open-source et sans publicité. Vous pouvez soutenir son développement via [**GitHub Sponsors**](https://github.com/sponsors/furcy75).

[![Sponsoriser sur GitHub](https://img.shields.io/badge/Faire%20un%20don-GitHub%20Sponsors-db2777?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/furcy75)

---

## ⚖️ Avertissement légal & Licence

Torrent Seeder est un outil technique de recherche et d'assainissement de métadonnées BitTorrent (`.torrent`). L'application n'héberge aucun contenu protégé. Chaque utilisateur est seul responsable de l'usage qu'il en fait. Distribué sous licence **MIT** — voir [LICENSE](LICENSE).
