<div align="center">

<img src="assets/icon/app_icon.png" alt="Torrent Seeder Logo" width="128" height="128" />

# Torrent Seeder

**Buscador Torrent autónomo (catálogo completo) con extractor de sitios personalizados, Sandbox antivirus integrado y soporte multi-cuenta Seedr.cc**

*100 % autónomo en Android, Windows y Linux — Sin servidor, sin publicidad, sin navegadores peligrosos, interfaz en 6 idiomas.*

[🇬🇧 English](README.md) | [🇫🇷 Français](README.fr.md) | **🇪🇸 Español** | [🇩🇪 Deutsch](README.de.md) | [🇳🇱 Nederlands](README.nl.md) | [🇮🇹 Italiano](README.it.md)

[![Build & Release](https://github.com/furcy75/Torrent-Finder/actions/workflows/build-release.yml/badge.svg)](https://github.com/furcy75/Torrent-Finder/actions/workflows/build-release.yml)
[![Latest Release](https://img.shields.io/github/v/release/furcy75/Torrent-Finder?color=22c55e&label=Versi%C3%B3n)](https://github.com/furcy75/Torrent-Finder/releases/latest)
[![Platforms](https://img.shields.io/badge/Plataformas-Android%20%7C%20Windows%20%7C%20Linux-38bdf8)](#descarga)
[![GitHub Sponsors](https://img.shields.io/badge/Apoyar-GitHub%20Sponsors-db2777?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/furcy75)
[![License: MIT](https://img.shields.io/badge/Licencia-MIT-94a3b8.svg)](LICENSE)

</div>

---

## 🎯 ¿Por qué Torrent Seeder?

**Torrent Seeder** elimina el riesgo de páginas web con anuncios maliciosos y archivos `.torrent` falsos mediante una arquitectura **100 % local y autónoma**:

- **Sin servidor externo**: funciona totalmente solo en Android, Windows y Linux.
- **Sin WebView / sin navegador**: solo peticiones HTTP directas (APIs JSON / RSS XML).
- **Sandbox antivirus integrado**: inspecciona cada `.torrent` en un **Isolate aislado** y lo reconstruye limpio antes de guardarlo o enviarlo a Seedr.
- **Interfaz en 6 idiomas**: cambia al instante entre **English, Français, Español, Deutsch, Nederlands e Italiano** desde la bandera junto a Ajustes.

---

## 📦 Descarga

Descarga la última versión desde [**GitHub Releases**](https://github.com/furcy75/Torrent-Finder/releases/latest) :

| Plataforma | Archivo | Instalación |
| :--- | :--- | :--- |
| **Android** *(autónomo)* | [`TorrentSeeder-Android.apk`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Android.apk) | Instalar el APK directamente en el teléfono |
| **Windows** *(Instalador)* | [`TorrentSeeder-Windows-Setup.exe`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Windows-Setup.exe) | Doble clic (DLLs de Visual C++ incluidas) |
| **Windows** *(Portable)* | [`TorrentSeeder-Windows-Portable.zip`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Windows-Portable.zip) | Descomprimir y ejecutar `safetorrent.exe` |
| **Linux** *(Ubuntu / Debian / Mint)* | [`TorrentSeeder-Linux-amd64.deb`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Linux-amd64.deb) | `sudo apt install ./TorrentSeeder-Linux-amd64.deb` |
| **Linux** *(Portable)* | [`TorrentSeeder-Linux-x64.tar.gz`](https://github.com/furcy75/Torrent-Finder/releases/latest/download/TorrentSeeder-Linux-x64.tar.gz) | Descomprimir y ejecutar `./safetorrent` |

---

## ✨ Funciones principales

- **Búsqueda de información y Búsqueda Torrent separadas**: busca primero la ficha de Película/Serie (opcional — AlloCiné, Wikidata, TVMaze, IMDb), selecciona un título en el idioma deseado para rellenar el campo **Búsqueda Torrent** y edítalo libremente antes de buscar.
- **Filtros rápidos, banderas en resultados y Visor NFO seguro**: seeders activos, tamaño máximo, resolución, códec (`H.264 / x264`, `x265`, `HDR`), exclusión CAM/TS por defecto, banderas vectoriales cuando se detectan idiomas en los resultados y visor NFO en texto plano.
- **Integración Seedr.cc (una o más cuentas)**: acceso con **Email y Contraseña** (solo se guarda el token OAuth, nunca la contraseña), selector manual con **cuota libre e indicador de descarga en curso**, y **aviso discreto «Archivo descargado»** (sin detalles del archivo) al finalizar una descarga.
- **11 fuentes integradas (catálogo completo) + Sitios personalizados + Torznab**: Knaben, APIBay, TorrentCSV, YTS (multi-mirror), EZTV, BitSearch, Nyaa, SubsPlease, SolidTorrents, LimeTorrents, Internet Archive (películas, series, anime, música, libros, software...), más **Sitios web personalizados** en ⚙️ Ajustes (URL con `{query}`, extracción HTML/CSS/RSS/JSON, modo 2 pasos, botón Probar, Importar/Exportar JSON) y Jackett/Prowlarr.

---

## 💖 Apoyar el proyecto

**Torrent Seeder** es gratuito, de código abierto y sin publicidad. Puedes apoyar su desarrollo en [**GitHub Sponsors**](https://github.com/sponsors/furcy75).

[![Patrocinar en GitHub](https://img.shields.io/badge/Donar-GitHub%20Sponsors-db2777?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/furcy75)

---

## ⚖️ Aviso legal y Licencia

Torrent Seeder es una herramienta técnica para buscar y verificar metadatos BitTorrent (`.torrent`). No aloja ningún contenido protegido. Licencia **MIT** — consulta [LICENSE](LICENSE).
