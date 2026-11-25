import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safetorrent/l10n/app_l10n.dart';
import 'package:safetorrent/models/movie_suggestion.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/seedr_service.dart';
import 'package:safetorrent/ui/search_screen.dart';
import 'package:safetorrent/ui/seedr_screen.dart';
import 'package:safetorrent/ui/settings_dialog.dart';
import 'package:safetorrent/ui/watchlist_screen.dart';
import 'package:safetorrent/ui/widgets/country_flag.dart';
import 'package:url_launcher/url_launcher.dart';

class PendingSearchRequest {
  const PendingSearchRequest({
    required this.movie,
    this.watchlistId,
  });

  final MovieSuggestion movie;
  final String? watchlistId;
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.storage,
    this.onLanguageChanged,
  });

  static const String sponsorUrl = 'https://github.com/sponsors/furcy75';

  final LocalStorageService storage;
  final ValueChanged<String>? onLanguageChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tabIndex = 0;
  bool _ready = false;
  PendingSearchRequest? _pendingSearch;
  int _searchTriggerId = 0;
  int _seedrRefreshSignal = 0;

  // Discreet global Seedr download-completion monitor
  final Map<String, Set<String>> _activeTransfersByAccount = {};
  final Map<String, int> _pendingNewTransferTicks = {};
  final Map<String, int> _baselineItemCountByAccount = {};
  final Set<String> _manuallyCancelledTransferIds = {};
  Timer? _completionPollTimer;
  bool _pollingCompletion = false;
  bool _completionPopupOpen = false;

  @override
  void initState() {
    super.initState();
    _ready = widget.storage.isLoaded;
    if (!_ready) {
      _initStorage();
    }
  }

  @override
  void dispose() {
    _completionPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initStorage() async {
    await widget.storage.load();
    if (mounted) {
      widget.onLanguageChanged?.call(widget.storage.settings.appLanguage);
      setState(() => _ready = true);
    }
  }

  Future<void> _selectLanguage(String code) async {
    await widget.storage.updateSettings(
      widget.storage.settings.copyWith(appLanguage: code),
    );
    widget.onLanguageChanged?.call(code);
    if (mounted) setState(() {});
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

  // -------------------------------------------------------------------
  // Global Discreet Download Completion Monitor (zero file details shown)
  // -------------------------------------------------------------------
  void _onSeedrTransferStarted(String accountId) {
    _pendingNewTransferTicks[accountId] = 15;
    _ensureCompletionPolling();
  }

  void _onSeedrTransfersObserved(
    String accountId,
    Set<String> currentIds,
    int rootItemCount,
  ) {
    final prevIds = _activeTransfersByAccount[accountId] ?? const <String>{};
    final completed = prevIds.where(
      (id) => !currentIds.contains(id) && !_manuallyCancelledTransferIds.contains(id),
    );
    if (completed.isNotEmpty) {
      _pendingNewTransferTicks.remove(accountId);
      _showDiscreetDownloadFinishedPopup();
    } else if (_pendingNewTransferTicks.containsKey(accountId) && currentIds.isEmpty) {
      final baseline = _baselineItemCountByAccount[accountId];
      if (baseline != null && rootItemCount > baseline) {
        _pendingNewTransferTicks.remove(accountId);
        _showDiscreetDownloadFinishedPopup();
      }
    }

    _baselineItemCountByAccount[accountId] = rootItemCount;
    if (currentIds.isEmpty) {
      _activeTransfersByAccount.remove(accountId);
    } else {
      _activeTransfersByAccount[accountId] = Set<String>.from(currentIds);
      _pendingNewTransferTicks.remove(accountId);
    }
    _ensureCompletionPolling();
  }

  void _onSeedrTransferCancelled(String transferId) {
    _manuallyCancelledTransferIds.add(transferId);
  }

  void _ensureCompletionPolling() {
    final hasWork =
        _activeTransfersByAccount.isNotEmpty || _pendingNewTransferTicks.isNotEmpty;
    if (hasWork && _completionPollTimer == null) {
      _completionPollTimer = Timer.periodic(
        const Duration(seconds: 8),
        (_) => _pollMonitoredAccounts(),
      );
    } else if (!hasWork) {
      _completionPollTimer?.cancel();
      _completionPollTimer = null;
    }
  }

  Future<void> _pollMonitoredAccounts() async {
    if (!mounted || _pollingCompletion) return;
    final monitoredIds = <String>{
      ..._activeTransfersByAccount.keys,
      ..._pendingNewTransferTicks.keys,
    };
    if (monitoredIds.isEmpty) {
      _ensureCompletionPolling();
      return;
    }

    _pollingCompletion = true;
    try {
      final seedr = SeedrService(storage: widget.storage);
      for (final accountId in monitoredIds) {
        final acc = widget.storage.seedrAccountById(accountId);
        if (acc == null) {
          _activeTransfersByAccount.remove(accountId);
          _pendingNewTransferTicks.remove(accountId);
          continue;
        }
        try {
          final contents = await seedr.listContents(account: acc, folderId: '0');
          if (!mounted) return;
          final currentIds = contents.torrents.map((t) => t.id).toSet();
          final itemCount = contents.folders.length + contents.files.length;

          if (_pendingNewTransferTicks.containsKey(accountId)) {
            final remaining = (_pendingNewTransferTicks[accountId] ?? 1) - 1;
            if (remaining <= 0) {
              _pendingNewTransferTicks.remove(accountId);
            } else {
              _pendingNewTransferTicks[accountId] = remaining;
            }
          }

          _onSeedrTransfersObserved(accountId, currentIds, itemCount);
        } catch (_) {
          // Ignore transient network hiccups during background polling
        }
      }
    } finally {
      _pollingCompletion = false;
      _ensureCompletionPolling();
    }
  }

  Future<void> _showDiscreetDownloadFinishedPopup() async {
    if (!mounted || _completionPopupOpen) return;
    _completionPopupOpen = true;
    final l10n = AppL10n.of(context);
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF111C33),
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.t('dl_done_title'))),
            ],
          ),
          content: Text(l10n.t('dl_done_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.t('close')),
            ),
            if (_tabIndex != 2)
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _openSeedrTab(refresh: true);
                },
                icon: const Icon(Icons.cloud_done_outlined, size: 17),
                label: Text(l10n.t('open_seedr')),
              ),
          ],
        ),
      );
    } finally {
      _completionPopupOpen = false;
    }
  }

  // -------------------------------------------------------------------
  // Donate / GitHub Sponsors Dialog
  // -------------------------------------------------------------------
  Future<void> _openDonateDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppL10n.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111C33),
        title: Row(
          children: [
            const Icon(Icons.volunteer_activism_outlined, color: Color(0xFFF472B6), size: 26),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.t('donate_title'))),
          ],
        ),
        content: Text(l10n.t('donate_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.t('donate_later')),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDB2777)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final uri = Uri.parse(HomeShell.sponsorUrl);
              final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok) {
                await Clipboard.setData(const ClipboardData(text: HomeShell.sponsorUrl));
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.t('donate_copied'))),
                );
              }
            },
            icon: const Icon(Icons.favorite_outline, size: 17),
            label: Text(l10n.t('donate_cta')),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => SettingsDialog(
        storage: widget.storage,
        onOpenSeedrTab: () => _openSeedrTab(refresh: true),
      ),
    );
    if (mounted) {
      setState(() => _seedrRefreshSignal++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final watchlistCount = widget.storage.watchlist.length;
    final seedrCount = widget.storage.seedrAccounts.length;

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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Torrent Seeder',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  Text(
                    l10n.t('app_subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF22C55E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.t('tooltip_donate'),
            icon: const Icon(
              Icons.volunteer_activism_outlined,
              color: Color(0xFFF472B6),
            ),
            onPressed: _openDonateDialog,
          ),
          PopupMenuButton<String>(
            key: const Key('language_switcher_btn'),
            tooltip: l10n.t('tooltip_language'),
            color: const Color(0xFF111C33),
            initialValue: l10n.code,
            onSelected: _selectLanguage,
            itemBuilder: (_) => AppL10n.supported.map((opt) {
              final selected = opt.code == l10n.code;
              return PopupMenuItem<String>(
                value: opt.code,
                child: Row(
                  children: [
                    CountryFlag(code: opt.flagCode, width: 22, height: 15),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        opt.nativeName,
                        style: TextStyle(
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                          color: selected ? const Color(0xFF38BDF8) : null,
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check, size: 16, color: Color(0xFF22C55E)),
                  ],
                ),
              );
            }).toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CountryFlag(code: l10n.flagCode, width: 22, height: 15),
                  const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.t('tooltip_settings'),
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
                  onSeedrTransferStarted: _onSeedrTransferStarted,
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
                  onTransferStarted: _onSeedrTransferStarted,
                  onTransfersObserved: _onSeedrTransfersObserved,
                  onTransferCancelled: _onSeedrTransferCancelled,
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
          });
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.search),
            label: l10n.t('tab_search'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: watchlistCount > 0,
              label: Text('$watchlistCount'),
              child: const Icon(Icons.bookmark_outline),
            ),
            label: l10n.t('tab_watchlist'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: seedrCount > 0,
              backgroundColor: const Color(0xFF22C55E),
              label: seedrCount > 1 ? Text('$seedrCount') : null,
              smallSize: 8,
              child: const Icon(Icons.cloud_outlined),
            ),
            label: l10n.t('tab_seedr'),
          ),
        ],
      ),
    );
  }
}
