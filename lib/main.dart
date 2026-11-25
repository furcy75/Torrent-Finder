import 'package:flutter/material.dart';
import 'package:safetorrent/l10n/app_l10n.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/ui/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TorrentSeederApp());
}

class TorrentSeederApp extends StatefulWidget {
  const TorrentSeederApp({super.key, this.storage});

  final LocalStorageService? storage;

  @override
  State<TorrentSeederApp> createState() => _TorrentSeederAppState();
}

class _TorrentSeederAppState extends State<TorrentSeederApp> {
  late final LocalStorageService _storage = widget.storage ?? LocalStorageService();
  late String _langCode = AppL10n.resolveCode(_storage.settings.appLanguage);

  void _handleLanguageChanged(String code) {
    final resolved = AppL10n.resolveCode(code);
    if (resolved != _langCode) {
      setState(() => _langCode = resolved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF38BDF8),
      brightness: Brightness.dark,
      surface: const Color(0xFF0F172A),
    );

    return AppL10nScope(
      l10n: AppL10n(_langCode),
      child: MaterialApp(
        title: 'Torrent Seeder',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: const Color(0xFF0B1120),
          cardTheme: CardThemeData(
            color: const Color(0xFF111C33),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF243559)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF0B1120),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF243559)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF243559)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
            ),
          ),
        ),
        home: HomeShell(
          storage: _storage,
          onLanguageChanged: _handleLanguageChanged,
        ),
      ),
    );
  }
}
