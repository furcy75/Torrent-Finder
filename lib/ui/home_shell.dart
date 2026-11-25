import 'package:flutter/material.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/ui/history_screen.dart';
import 'package:safetorrent/ui/search_screen.dart';
import 'package:safetorrent/ui/settings_dialog.dart';
import 'package:safetorrent/ui/watchlist_screen.dart';

class PendingSearchRequest {
  const PendingSearchRequest({
    required this.query,
    this.originalTitle,
    this.year,
    required this.languages,
    this.watchlistId,
  });

  final String query;
  final String? originalTitle;
  final int? year;
  final List<LanguageFilter> languages;
  final String? watchlistId;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.storage});

  final LocalStorageService storage;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tabIndex = 0;
  bool _ready = false;
  PendingSearchRequest? _pendingSearch;
  int _searchTriggerId = 0;

  @override
  void initState() {
    super.initState();
    _ready = widget.storage.isLoaded;
    if (!_ready) {
      _initStorage();
    }
  }

  Future<void> _initStorage() async {
    await widget.storage.load();
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  void _triggerSearch(PendingSearchRequest req) {
    setState(() {
      _pendingSearch = req;
      _searchTriggerId++;
      _tabIndex = 0;
    });
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(storage: widget.storage),
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleHistory(bool value) async {
    await widget.storage.updateSettings(
      widget.storage.settings.copyWith(saveHistory: value),
    );
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Historique local activé sur cet appareil.'
              : 'Historique local désactivé.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watchlistCount = widget.storage.watchlist.length;
    final historyCount = widget.storage.history.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        titleSpacing: 16,
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF22C55E), size: 26),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SafeTorrent',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                Text(
                  'Autonome • Bac à sable actif',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF22C55E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Tooltip(
            message: 'Activer / désactiver l\'historique local',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Historique', style: TextStyle(fontSize: 12)),
                Switch(
                  value: widget.storage.settings.saveHistory,
                  onChanged: _ready ? _toggleHistory : null,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Réglages sécurité & sources',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _ready ? _openSettings : null,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _tabIndex,
              children: [
                SearchScreen(
                  storage: widget.storage,
                  pendingRequest: _pendingSearch,
                  triggerId: _searchTriggerId,
                  onDataChanged: () => setState(() {}),
                ),
                WatchlistScreen(
                  storage: widget.storage,
                  onRerunSearch: _triggerSearch,
                  onDataChanged: () => setState(() {}),
                ),
                HistoryScreen(
                  storage: widget.storage,
                  onRerunSearch: _triggerSearch,
                  onDataChanged: () => setState(() {}),
                ),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0F172A),
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Rechercher',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: watchlistCount > 0,
              label: Text('$watchlistCount'),
              child: const Icon(Icons.bookmark_outline),
            ),
            label: 'Plus tard',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: historyCount > 0,
              label: Text('$historyCount'),
              child: const Icon(Icons.history),
            ),
            label: 'Historique',
          ),
        ],
      ),
    );
  }
}
