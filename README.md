# 🛡️ SafeTorrent

**Application 100 % autonome (Android `.apk`, Windows `.exe`, Linux) avec bac à sable anti-virus intégré pour rechercher des fichiers `.torrent` de films.**

✅ **Zéro PC serveur requis** : l'APK Android tourne **100 % en solo** sur votre téléphone, tout comme l'application Windows et l'application Linux.  
✅ **Zéro infrastructure / Zéro cloud / Zéro compte** : tout s'exécute directement sur votre appareil.

---

## ✨ Fonctionnalités

- **🛡️ Bac à sable anti-virus embarqué** :
  - **Zéro navigateur / Zéro WebView / Zéro JavaScript** : l'application n'affiche jamais les pages web des sites torrent (élimine 100 % des pubs malveillantes, popups, faux boutons « Download » et *drive-by downloads*).
  - **Exécution dans un Isolate mémoire séparé** (`Isolate.run`) + bac à sable système d'Android (SELinux / UID dédié).
  - **Protection anti-SSRF** sur chaque requête et redirection (bloque `file://`, `127.0.0.1`, réseaux privés, métadonnées cloud) + limite stricte de **2 Mo en RAM** + rejet immédiat des pages HTML déguisées.
  - **Inspecteur & Reconstructeur `.torrent` (Bencode Sanitizer)** :
    - Décode strictement le fichier `.torrent` (protection anti-bombes Bencode).
    - Inspecte **chaque fichier contenu à l'intérieur** et **bloque automatiquement** les exécutables et pièges classiques (`.exe`, `.msi`, `.bat`, `.scr`, `.lnk`, `.vbs`, `.ps1`, `.apk`, `.dmg`, `.iso`, doubles extensions `Film.mkv.exe`, usurpation Unicode RTLO `\u202e`, traversée de répertoire `../`, archives `.zip`/`.rar`/`.7z` piégées par mot de passe).
    - Vérifie la présence d'au moins un vrai fichier vidéo (`.mkv`, `.mp4`, `.avi`...).
    - **Reconstruit un fichier `.torrent` propre** ne contenant que les champs BitTorrent légitimes (`announce`, `announce-list`, `info`) tout en préservant l'`info_hash` SHA-1 exact.
- **🎬 Recherche ultra-simple + AlloCiné** :
  - Tapez uniquement le **nom du film** en français (ex : *Les Évadés*).
  - Appuyez sur **« AlloCiné (Titre EN) »** pour récupérer automatiquement son **titre original / anglais** (*The Shawshank Redemption*), son affiche et son année (avec secours automatique Wikidata FR→EN et IMDb).
- **🇫🇷 🇬🇧 🇪🇸 Drapeaux de langue** :
  - Choisissez la langue voulue en un clic : **🇫🇷 Français**, **🇬🇧 English**, **🇪🇸 Español** ou **🌍 Toutes**.
- **📊 Informations claires sur chaque torrent** :
  - **Qualité** (`4K 2160p`, `1080p`, `720p`, `BluRay`, `WEB-DL`, `HDR`, `x265`), **Taille**, **Seeders**, **Leechers**, langue détectée, source et bouton **« Bac à sable (.torrent) »**.
- **📌 Historique optionnel & Liste « Plus tard »** :
  - Interrupteur en haut de l'écran pour activer ou désactiver l'historique local.
  - Si un film n'est pas trouvé, sauvegardez-le en 1 clic dans **« Plus tard »** pour relancer la recherche automatiquement plus tard.
- **🔌 Indexeurs intégrés + Jackett / Prowlarr optionnel** :
  - Prêt à l'emploi sans configuration : **YTS**, **APIBay**, **Internet Archive**.
  - Possibilité d'ajouter des indexeurs **Torznab** (Jackett / Prowlarr) depuis les réglages.

---

## 📦 Obtenir l'APK Android, l'EXE Windows et l'App Linux (sans rien compiler sur votre PC !)

Ce dépôt inclut un workflow **GitHub Actions** ([build-release.yml](.github/workflows/build-release.yml)) qui compile automatiquement les 3 applications autonomes dans le cloud GitHub :

1. Poussez ce dossier sur le dépôt GitHub :
   ```bash
   git init
   git add .
   git commit -m "Initial commit: SafeTorrent standalone Android/Windows/Linux app"
   git branch -M main
   git remote add origin https://github.com/furcy75/Torrent-Finder.git
   git push -u origin main
   ```
2. Ouvrez l'onglet **Releases** ou **Actions** sur GitHub → téléchargez directement :
   - **`SafeTorrent-Android.apk`** → transférez et installez sur votre téléphone Android (**100 % autonome**).
   - **`SafeTorrent-Windows-Setup.exe`** → un seul fichier `.exe` installable directement sur Windows (sans dézipper, avec raccourci Bureau) + **`SafeTorrent-Windows-Portable.zip`** (version portable sans installation).
   - **`SafeTorrent-Linux-amd64.deb`** → paquet Debian/Ubuntu/Mint installable en 1 clic (`sudo apt install ./SafeTorrent-Linux-amd64.deb`) + **`SafeTorrent-Linux-x64.tar.gz`** (archive portable).
3. *(Bonus)* En créant un tag (`git tag v1.0.0 && git push origin v1.0.0`), GitHub publie automatiquement une **Release** avec tous les fichiers prêts au téléchargement.

---

## 🛠️ Compiler localement (optionnel, si vous avez Flutter installé)

```bash
# Générer les dossiers plateformes compatibles avec votre version de Flutter
flutter create --platforms=android,windows,linux --org com.safetorrent --project-name safetorrent .
flutter pub get

# Lancer les tests unitaires, sécurité et UI
flutter analyze
flutter test

# Compiler au choix :
flutter build apk --release        # -> build/app/outputs/flutter-apk/app-release.apk
flutter build windows --release    # -> build/windows/x64/runner/Release/
flutter build linux --release      # -> build/linux/x64/release/bundle/
```

> **Note Android :** si vous compilez localement, vérifiez que `<uses-permission android:name="android.permission.INTERNET" />` est présent dans `android/app/src/main/AndroidManifest.xml` (ajouté automatiquement par le workflow GitHub Actions).

---

## ⚖️ Avertissement légal

SafeTorrent est un moteur de recherche technique et un outil d'inspection/assainissement de métadonnées BitTorrent (`.torrent`). Il n'héberge aucun contenu. Vous êtes seul responsable de l'usage que vous en faites et du respect des lois applicables dans votre pays.

## 📄 Licence

MIT — voir [LICENSE](LICENSE).
