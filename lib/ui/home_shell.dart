import 'package:flutter/material.dart';
import 'package:safetorrent/models/movie_suggestion.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/ui/search_screen.dart';
import 'package:safetorrent/ui/seedr_screen.dart';
import 'package:safetorrent/ui/settings_dialog.dart';
import 'package:safetorrent/ui/torbox_screen.dart';
import 'package:safetorrent/ui/watchlist_screen.dart';

class PendingSearchRequest {
  const PendingSearchRequest({
    required this.movie,
    this.watchlistId,
  });

  final MovieSuggestion movie;
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
  int _seedrRefreshSignal = 0;
  int _torboxRefreshSignal = 0;

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

  void _openSeedrTab({bool refresh = true}) {
    setState(() {
      if (refresh) _seedrRefreshSignal++;
      _tabIndex = 2;
    });
  }

  void _openTorboxTab({bool refresh = true}) {
    setState(() {
      if (refresh) _torboxRefreshSignal++;
      _tabIndex = 3;
    });
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(storage: widget.storage),
    );
    if (mounted) {
      setState(() => _torboxRefreshSignal++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final watchlistCount = widget.storage.watchlist.length;
    final seedrConnected = widget.storage.seedrSession?.isValid == true;
    final torboxConnected = widget.storage.torboxProfiles.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        titleSpacing: 16,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 30,
                height: 30,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFF22C55E),
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SafeTorrent',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                Text(
                  'Autonome • Films & Séries • Bac à sable actif',
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
          IconButton(
            tooltip: 'Réglages sécurité, Cloud & sources',
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
                  onOpenSeedr: () => _openSeedrTab(refresh: true),
                  onOpenTorbox: () => _openTorboxTab(refresh: true),
                ),
                WatchlistScreen(
                  storage: widget.storage,
                  onRerunSearch: _triggerSearch,
                  onDataChanged: () => setState(() {}),
                ),
                SeedrScreen(
                  storage: widget.storage,
                  refreshSignal: _seedrRefreshSignal,
                  onSessionChanged: () => setState(() {}),
                ),
                TorboxScreen(
                  storage: widget.storage,
                  refreshSignal: _torboxRefreshSignal,
                  onProfilesChanged: () => setState(() {}),
                ),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0F172A),
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) {
          setState(() {
            _tabIndex = idx;
            if (idx == 2) _seedrRefreshSignal++;
            if (idx == 3) _torboxRefreshSignal++;
          });
        },
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
              isLabelVisible: seedrConnected,
              backgroundColor: const Color(0xFF22C55E),
              smallSize: 8,
              child: const Icon(Icons.cloud_outlined),
            ),
            label: 'Seedr',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: torboxConnected,
              backgroundColor: const Color(0xFF22C55E),
              smallSize: 8,
              child: const Icon(Icons.bolt_outlined),
            ),
            label: 'TorBox',
          ),
        ],
      ),
    );
  }
}
