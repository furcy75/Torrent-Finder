import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safetorrent/l10n/app_l10n.dart';
import 'package:safetorrent/models/movie_suggestion.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/models/watchlist_item.dart';
import 'package:safetorrent/services/allocine_service.dart';
import 'package:safetorrent/services/indexers_service.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/release_parser.dart';
import 'package:safetorrent/services/seedr_service.dart';
import 'package:safetorrent/ui/home_shell.dart';
import 'package:safetorrent/ui/nfo_dialog.dart';
import 'package:safetorrent/ui/sandbox_dialog.dart';
import 'package:safetorrent/ui/seedr_picker_dialog.dart';
import 'package:safetorrent/ui/widgets/country_flag.dart';

enum _SortMode { seeders, dateDesc, dateAsc, quality, sizeDesc, sizeAsc }

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.storage,
    required this.pendingRequest,
    required this.triggerId,
    required this.onDataChanged,
    this.onOpenSeedr,
    this.onSeedrTransferStarted,
  });

  final LocalStorageService storage;
  final PendingSearchRequest? pendingRequest;
  final int triggerId;
  final VoidCallback onDataChanged;
  final VoidCallback? onOpenSeedr;
  final ValueChanged<String>? onSeedrTransferStarted;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // Area 1: Movie / TV Series Information Lookup (optional)
  final _infoCtrl = TextEditingController();
  final _infoFocus = FocusNode();

  // Area 2: Editable Torrent Search Query (always editable!)
  final _torrentQueryCtrl = TextEditingController();
  final _torrentQueryFocus = FocusNode();

  final _allocineService = AllocineService();
  final _indexersService = IndexersService();

  MediaType _mediaType = MediaType.movie;
  bool _skippedInfoStep = false;
  bool _loadingInfo = false;
  bool _hasLookedUpInfo = false;
  List<MovieSuggestion> _suggestions = [];
  MovieSuggestion? _selectedMedia;

  // Quick filter tags (NO language filter; CAM/TS excluded by default)
  bool _onlyActiveSeeders = false;
  bool _minTenSeeders = false;
  bool _excludeCam = true;
  int? _maxSizeGb;
  final Set<String> _resolutionFilters = {};
  final Set<String> _formatFilters = {};

  _SortMode _sortMode = _SortMode.seeders;
  bool _searchingTorrents = false;
  bool _hasSearchedTorrents = false;
  List<TorrentResult> _results = [];
  List<String> _queriedIndexers = [];
  String? _activeWatchlistId;
  int _lastHandledTrigger = 0;

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.triggerId != _lastHandledTrigger && widget.pendingRequest != null) {
      _lastHandledTrigger = widget.triggerId;
      final req = widget.pendingRequest!;
      final media = req.movie;
      _mediaType = media.mediaType;
      _infoCtrl.text = media.titleFr;
      _selectedMedia = media;
      _skippedInfoStep = false;
      _suggestions = [];
      _hasLookedUpInfo = true;
      _activeWatchlistId = req.watchlistId;
      _setTorrentQueryFromTitle(media.titleFr, year: media.year);
      _performTorrentSearch();

      if (media.posterUrl == null || media.posterUrl!.isEmpty) {
        _silentlyEnrichPoster(media, req.watchlistId);
      }
    }
  }

  Future<void> _silentlyEnrichPoster(MovieSuggestion media, String? watchlistId) async {
    final hits = await _allocineService.resolveTitles(
      media.titleFr,
      mediaType: media.mediaType,
      limit: 2,
    );
    if (!mounted || hits.isEmpty) return;
    final match = hits.firstWhere(
      (h) => h.posterUrl != null && h.posterUrl!.isNotEmpty,
      orElse: () => hits.first,
    );
    if (match.posterUrl == null || match.posterUrl!.isEmpty) return;

    setState(() {
      if (_selectedMedia?.titleFr == media.titleFr) {
        _selectedMedia = _selectedMedia?.copyWith(
          posterUrl: match.posterUrl,
          titleEn: _selectedMedia?.titleEn ?? match.titleEn,
          titleEs: _selectedMedia?.titleEs ?? match.titleEs,
          tvMazeId: _selectedMedia?.tvMazeId ?? match.tvMazeId,
          seriesStatus: _selectedMedia?.seriesStatus ?? match.seriesStatus,
          seasonCount: _selectedMedia?.seasonCount ?? match.seasonCount,
          nextSeasonInfo: _selectedMedia?.nextSeasonInfo ?? match.nextSeasonInfo,
          nextReleaseDate: _selectedMedia?.nextReleaseDate ?? match.nextReleaseDate,
        );
      }
    });

    if (watchlistId != null) {
      final idx = widget.storage.watchlist.indexWhere((e) => e.id == watchlistId);
      if (idx != -1) {
        await widget.storage.updateWatchlistItem(
          widget.storage.watchlist[idx].copyWith(
            posterUrl: match.posterUrl,
            tvMazeId: match.tvMazeId,
            seriesStatus: match.seriesStatus,
            seasonCount: match.seasonCount,
            nextSeasonInfo: match.nextSeasonInfo,
            nextReleaseDate: match.nextReleaseDate,
          ),
        );
        widget.onDataChanged();
      }
    }
  }

  @override
  void dispose() {
    _infoCtrl.dispose();
    _infoFocus.dispose();
    _torrentQueryCtrl.dispose();
    _torrentQueryFocus.dispose();
    super.dispose();
  }

  void _resetAllToZero() {
    setState(() {
      _infoCtrl.clear();
      _torrentQueryCtrl.clear();
      _skippedInfoStep = false;
      _loadingInfo = false;
      _hasLookedUpInfo = false;
      _suggestions = [];
      _selectedMedia = null;
      _results = [];
      _queriedIndexers = [];
      _countsByIndexer = {};
      _indexerErrors = {};
      _activeWatchlistId = null;
      _searchingTorrents = false;
      _hasSearchedTorrents = false;
      _onlyActiveSeeders = false;
      _minTenSeeders = false;
      _excludeCam = true;
      _maxSizeGb = null;
      _resolutionFilters.clear();
      _formatFilters.clear();
      _sortMode = _SortMode.seeders;
    });
    _infoFocus.requestFocus();
  }

  bool get _hasAnyTagFilters =>
      _onlyActiveSeeders ||
      _minTenSeeders ||
      _excludeCam ||
      _maxSizeGb != null ||
      _resolutionFilters.isNotEmpty ||
      _formatFilters.isNotEmpty;

  void _clearAllTagFilters() {
    setState(() {
      _onlyActiveSeeders = false;
      _minTenSeeders = false;
      _excludeCam = false;
      _maxSizeGb = null;
      _resolutionFilters.clear();
      _formatFilters.clear();
    });
  }

  // -------------------------------------------------------------------
  // Area 1: Movie / TV Series Info Lookup (AlloCiné / TVMaze / Wikidata / IMDb)
  // -------------------------------------------------------------------
  Future<void> _lookupMediaInfo() async {
    final l10n = AppL10n.of(context);
    final query = _infoCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack(
        _mediaType == MediaType.series
            ? l10n.t('enter_series_first')
            : l10n.t('enter_movie_first'),
      );
      _infoFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();

    setState(() {
      _loadingInfo = true;
      _hasLookedUpInfo = true;
      _skippedInfoStep = false;
      _suggestions = [];
      _selectedMedia = null;
    });

    final hits = await _allocineService.resolveTitles(query, mediaType: _mediaType);
    if (!mounted) return;
    setState(() {
      _loadingInfo = false;
      _suggestions = hits;
    });
  }

  void _skipInfoStep() {
    final typed = _infoCtrl.text.trim();
    setState(() {
      _skippedInfoStep = true;
      if (_torrentQueryCtrl.text.trim().isEmpty && typed.isNotEmpty) {
        _torrentQueryCtrl.text = typed;
      }
    });
    _torrentQueryFocus.requestFocus();
  }

  void _selectMediaMatch(MovieSuggestion media) {
    setState(() {
      _selectedMedia = media;
      _mediaType = media.mediaType;
      _infoCtrl.text = media.titleFr;
      _skippedInfoStep = false;
      _setTorrentQueryFromTitle(media.titleFr, year: media.year);
    });
    _torrentQueryFocus.requestFocus();
  }

  /// Replaces the editable Torrent Search field with [title] (optionally with [year])
  /// so the user can still modify it or append extra keywords before searching.
  void _setTorrentQueryFromTitle(String title, {int? year}) {
    final clean = title.trim();
    final next = (year != null && _mediaType == MediaType.movie) ? '$clean $year' : clean;
    _torrentQueryCtrl.text = next;
    _torrentQueryCtrl.selection = TextSelection.collapsed(offset: next.length);
  }

  /// Appends a helper token (e.g. `S01`, `Complete`, year, etc.) into the editable query
  /// if not already present.
  void _appendTokenToTorrentQuery(String token) {
    final current = _torrentQueryCtrl.text.trim();
    final lowerTokens = current.toLowerCase().split(RegExp(r'\s+'));
    if (lowerTokens.contains(token.toLowerCase())) return;
    final next = current.isEmpty ? token : '$current $token';
    setState(() {
      _torrentQueryCtrl.text = next;
      _torrentQueryCtrl.selection = TextSelection.collapsed(offset: next.length);
    });
    _torrentQueryFocus.requestFocus();
  }

  // -------------------------------------------------------------------
  // Area 2: Editable Torrent Search (Full Catalog)
  // -------------------------------------------------------------------
  Map<String, int> _countsByIndexer = {};
  Map<String, String> _indexerErrors = {};

  Future<void> _performTorrentSearch() async {
    final l10n = AppL10n.of(context);
    final rawQuery = _torrentQueryCtrl.text.trim();
    if (rawQuery.isEmpty) {
      _showSnack(l10n.t('enter_torrent_query'));
      _torrentQueryFocus.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _searchingTorrents = true;
      _hasSearchedTorrents = true;
      _results = [];
      _countsByIndexer = {};
      _indexerErrors = {};
    });

    final summary = await _indexersService.search(
      query: rawQuery,
      mediaType: _selectedMedia?.mediaType ?? _mediaType,
      includeAllLanguages: true,
      settings: widget.storage.settings,
    );

    if (_activeWatchlistId != null) {
      final idx = widget.storage.watchlist.indexWhere((e) => e.id == _activeWatchlistId);
      if (idx != -1) {
        final item = widget.storage.watchlist[idx];
        await widget.storage.updateWatchlistItem(
          item.copyWith(
            posterUrl: _selectedMedia?.posterUrl ?? item.posterUrl,
            found: summary.results.isNotEmpty,
            lastResultCount: summary.results.length,
            lastCheckedAt: DateTime.now().toUtc(),
          ),
        );
      }
      _activeWatchlistId = null;
    }

    if (!mounted) return;
    setState(() {
      _searchingTorrents = false;
      _results = summary.results;
      _queriedIndexers = summary.indexersQueried;
      _countsByIndexer = summary.countsByIndexer;
      _indexerErrors = summary.errors;
    });
    widget.onDataChanged();
  }

  Future<void> _saveForLater({MovieSuggestion? overrideMedia}) async {
    final l10n = AppL10n.of(context);
    final m = overrideMedia ?? _selectedMedia;
    final titleFr = m?.titleFr ??
        (_infoCtrl.text.trim().isNotEmpty
            ? _infoCtrl.text.trim()
            : _torrentQueryCtrl.text.trim());
    if (titleFr.isEmpty) {
      _showSnack(l10n.t('enter_title_first'));
      return;
    }
    final titleOrig = m?.titleEn ??
        (m != null && m.titleOriginal.toLowerCase() != titleFr.toLowerCase()
            ? m.titleOriginal
            : null);

    final added = await widget.storage.addToWatchlist(
      WatchlistItem(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        titleFr: titleFr,
        titleOriginal: titleOrig,
        titleEn: m?.titleEn,
        titleEs: m?.titleEs,
        posterUrl: m?.posterUrl,
        mediaType: m?.mediaType ?? _mediaType,
        tvMazeId: m?.tvMazeId,
        seriesStatus: m?.seriesStatus,
        seasonCount: m?.seasonCount,
        nextSeasonInfo: m?.nextSeasonInfo,
        nextReleaseDate: m?.nextReleaseDate,
        languages: const [LanguageFilter.all],
        year: m?.year,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    widget.onDataChanged();
    _showSnack(
      added
          ? l10n.t('saved_watchlist', {'title': titleFr})
          : l10n.t('already_watchlist', {'title': titleFr}),
    );
  }

  bool _matchesTagFilters(TorrentResult item) {
    if (_onlyActiveSeeders && item.seeders <= 0) return false;
    if (_minTenSeeders && item.seeders < 10) return false;

    final hay = '${item.title} ${item.quality} ${item.qualityTags.join(' ')}'.toLowerCase();

    if (_excludeCam &&
        (hay.contains('cam/ts') ||
            RegExp(r'\b(hdcam|camrip|cam|telesync|hdts|ts)\b').hasMatch(hay))) {
      return false;
    }

    if (_maxSizeGb != null) {
      final maxBytes = _maxSizeGb! * 1024 * 1024 * 1024;
      if (item.sizeBytes <= 0 || item.sizeBytes > maxBytes) return false;
    }

    if (_resolutionFilters.isNotEmpty) {
      final matchedRes = _resolutionFilters.any((res) {
        if (res == '4K') return hay.contains('2160p') || hay.contains('4k') || hay.contains('uhd');
        return hay.contains(res.toLowerCase());
      });
      if (!matchedRes) return false;
    }

    if (_formatFilters.isNotEmpty) {
      final matchedFmt = _formatFilters.any((fmt) {
        final f = fmt.toLowerCase();
        if (f == 'h.264 / x264') {
          return hay.contains('x264') ||
              hay.contains('h.264') ||
              hay.contains('h264') ||
              RegExp(r'\bavc\b').hasMatch(hay);
        }
        if (f == 'x265') return hay.contains('x265') || hay.contains('hevc') || hay.contains('265');
        if (f == 'bluray') {
          return hay.contains('bluray') || hay.contains('blu-ray') || hay.contains('bdrip');
        }
        if (f == 'webrip') return hay.contains('webrip') || hay.contains('web-rip');
        if (f == 'web-dl') return hay.contains('web-dl') || hay.contains('webdl');
        return hay.contains(f);
      });
      if (!matchedFmt) return false;
    }

    return true;
  }

  List<TorrentResult> get _filteredAndSortedResults {
    final list = _results.where(_matchesTagFilters).toList();
    int compareDates(TorrentResult a, TorrentResult b, {required bool descending}) {
      final da = ReleaseParser.parsePublishedDate(a.publishedAt);
      final db = ReleaseParser.parsePublishedDate(b.publishedAt);
      if (da == null && db == null) return b.seeders.compareTo(a.seeders);
      if (da == null) return 1;
      if (db == null) return -1;
      final cmp = descending ? db.compareTo(da) : da.compareTo(db);
      return cmp != 0 ? cmp : b.seeders.compareTo(a.seeders);
    }

    list.sort((a, b) {
      return switch (_sortMode) {
        _SortMode.seeders => b.seeders.compareTo(a.seeders),
        _SortMode.dateDesc => compareDates(a, b, descending: true),
        _SortMode.dateAsc => compareDates(a, b, descending: false),
        _SortMode.quality =>
          ReleaseParser.qualityRank(b.quality).compareTo(ReleaseParser.qualityRank(a.quality)),
        _SortMode.sizeDesc => b.sizeBytes.compareTo(a.sizeBytes),
        _SortMode.sizeAsc =>
          (a.sizeBytes == 0 ? 1 << 60 : a.sizeBytes).compareTo(b.sizeBytes == 0 ? 1 << 60 : b.sizeBytes),
      };
    });
    return list;
  }

  static String _labelForLangCode(String code) {
    return switch (code.toUpperCase()) {
      'FR' => 'Français',
      'EN' => 'English',
      'ES' => 'Español',
      'MULTI' => 'MULTI',
      'DE' => 'Deutsch',
      'NL' => 'Nederlands',
      'IT' => 'Italiano',
      'PT' => 'Português',
      'JA' || 'JP' => '日本語',
      _ => code.toUpperCase(),
    };
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openSandbox(TorrentResult item) async {
    await showDialog<void>(
      context: context,
      builder: (_) => SandboxDialog(
        torrent: item,
        settings: widget.storage.settings,
        storage: widget.storage,
        onSentToSeedr: widget.onOpenSeedr,
        onSeedrTransferStarted: widget.onSeedrTransferStarted,
      ),
    );
  }

  Future<void> _sendToSeedr(TorrentResult item) async {
    final l10n = AppL10n.of(context);
    final seedr = SeedrService(storage: widget.storage);
    if (!seedr.isConnected) {
      _showSnack(l10n.t('connect_seedr_first'));
      widget.onOpenSeedr?.call();
      return;
    }
    final magnet = item.magnetUrl;
    if (magnet == null || magnet.isEmpty) {
      _showSnack(l10n.t('use_sandbox_for_seedr'));
      return;
    }

    final chosen = await SeedrPickerDialog.show(
      context,
      storage: widget.storage,
      torrentTitle: item.title,
      torrentSizeBytes: item.sizeBytes,
    );
    if (chosen == null || !mounted) return;

    try {
      _showSnack(l10n.t('sending_to_seedr', {'account': chosen.displayName}));
      final msg = await seedr.addMagnet(magnet, account: chosen);
      await widget.storage.setActiveSeedrAccount(chosen.id);
      widget.onSeedrTransferStarted?.call(chosen.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('sent_to_seedr', {'account': chosen.displayName, 'msg': msg})),
          action: widget.onOpenSeedr != null
              ? SnackBarAction(label: l10n.t('open_seedr'), onPressed: widget.onOpenSeedr!)
              : null,
        ),
      );
    } catch (e) {
      _showSnack('$e');
    }
  }

  Future<void> _openNfo(TorrentResult item) async {
    await showDialog<void>(
      context: context,
      builder: (_) => NfoDialog(torrent: item),
    );
  }

  Future<void> _copyMagnet(String magnet) async {
    final l10n = AppL10n.of(context);
    await Clipboard.setData(ClipboardData(text: magnet));
    _showSnack(l10n.t('magnet_copied'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final visibleResults = _filteredAndSortedResults;
    final canReset = _infoCtrl.text.isNotEmpty ||
        _torrentQueryCtrl.text.isNotEmpty ||
        _selectedMedia != null ||
        _suggestions.isNotEmpty ||
        _skippedInfoStep ||
        _results.isNotEmpty;
    final isSeries = _mediaType == MediaType.series;
    final showTorrentSearchArea =
        _skippedInfoStep || _selectedMedia != null || _hasSearchedTorrents || _torrentQueryCtrl.text.isNotEmpty;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Top bar: clear 2-part indicator + reset button
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _stepPill(
                        l10n.t('phase_info'),
                        active: !showTorrentSearchArea,
                        done: _selectedMedia != null || _skippedInfoStep,
                      ),
                      _stepPill(
                        l10n.t('phase_torrent'),
                        active: showTorrentSearchArea,
                        done: false,
                      ),
                    ],
                  ),
                ),
                if (canReset)
                  OutlinedButton.icon(
                    onPressed: _resetAllToZero,
                    icon: const Icon(Icons.refresh, size: 17),
                    label: Text(l10n.t('new_search')),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ===========================================================
            // SECTION 1 — Movie / TV Series Information Lookup (Optional)
            // ===========================================================
            if (_selectedMedia != null)
              _buildSelectedMediaInfoCard(l10n, _selectedMedia!)
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFF38BDF8), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.t('info_section_title'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.t('info_section_subtitle'),
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            selected: _mediaType == MediaType.movie,
                            onSelected: (_) => setState(() => _mediaType = MediaType.movie),
                            avatar: const Icon(Icons.movie_outlined, size: 17),
                            label: Text(l10n.t('movies')),
                          ),
                          ChoiceChip(
                            selected: _mediaType == MediaType.series,
                            onSelected: (_) => setState(() => _mediaType = MediaType.series),
                            avatar: const Icon(Icons.tv_outlined, size: 17),
                            label: Text(l10n.t('tv_series')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('info_lookup_field'),
                        controller: _infoCtrl,
                        focusNode: _infoFocus,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _lookupMediaInfo(),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: isSeries ? l10n.t('series_name') : l10n.t('movie_name'),
                          hintText: isSeries ? l10n.t('series_hint') : l10n.t('movie_hint'),
                          prefixIcon: Icon(isSeries ? Icons.tv_outlined : Icons.movie_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _loadingInfo ? null : _lookupMediaInfo,
                            icon: _loadingInfo
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.manage_search),
                            label: Text(
                              isSeries ? l10n.t('identify_series') : l10n.t('identify_movie'),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _skipInfoStep,
                            icon: const Icon(Icons.fast_forward_outlined, size: 18),
                            label: Text(l10n.t('skip_direct')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // Info lookup results (pick a movie / series to populate titles)
            if (_selectedMedia == null && (_loadingInfo || _hasLookedUpInfo)) ...[
              const SizedBox(height: 12),
              _buildInfoLookupResults(l10n),
            ],

            const SizedBox(height: 14),

            // ===========================================================
            // SECTION 2 — Editable Torrent Search (Distinct Card!)
            // ===========================================================
            Card(
              color: const Color(0xFF13203B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: showTorrentSearchArea
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF243559),
                  width: showTorrentSearchArea ? 1.3 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.travel_explore, color: Color(0xFF22C55E), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.t('torrent_section_title'),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.t('torrent_section_subtitle'),
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('torrent_query_field'),
                      controller: _torrentQueryCtrl,
                      focusNode: _torrentQueryFocus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _performTorrentSearch(),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: l10n.t('torrent_query_label'),
                        hintText: l10n.t('torrent_query_hint'),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _torrentQueryCtrl.text.isNotEmpty
                            ? IconButton(
                                tooltip: l10n.t('clear_query'),
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setState(() => _torrentQueryCtrl.clear()),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _searchingTorrents ? null : _performTorrentSearch,
                          icon: _searchingTorrents
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search, size: 18),
                          label: Text(
                            _hasSearchedTorrents
                                ? l10n.t('rerun_torrent_search')
                                : l10n.t('launch_torrent_search'),
                          ),
                        ),
                        if (_selectedMedia != null || _torrentQueryCtrl.text.trim().isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: _saveForLater,
                            icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                            label: Text(l10n.t('save_for_later')),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Quick filters card (NO language filter!)
            if (_results.isNotEmpty) ...[
              _buildCategorizedFiltersCard(l10n, visibleResults.length),
              const SizedBox(height: 12),
            ],

            if (_searchingTorrents)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(l10n.t('searching_torrents')),
                    ],
                  ),
                ),
              )
            else if (_hasSearchedTorrents && _results.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.movie_filter_outlined, size: 44, color: Color(0xFF94A3B8)),
                      const SizedBox(height: 10),
                      Text(
                        _selectedMedia == null
                            ? l10n.t('no_torrents_any')
                            : (isSeries
                                ? l10n.t('no_torrents_series')
                                : l10n.t('no_torrents_movie')),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.t('no_torrents_hint'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF94A3B8)),
                      ),
                      if (_indexerErrors.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _buildIndexerErrorsChip(l10n),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _saveForLater,
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: Text(l10n.t('save_for_later')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _resetAllToZero,
                            icon: const Icon(Icons.refresh),
                            label: Text(l10n.t('new_search')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else if (_results.isNotEmpty && visibleResults.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.filter_alt_off_outlined, size: 40, color: Color(0xFF94A3B8)),
                      const SizedBox(height: 8),
                      Text(
                        '${l10n.t('no_filtered_results', {'count': '${_results.length}'})}'
                        '${_excludeCam ? l10n.t('cam_excluded_note') : ''}.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _clearAllTagFilters,
                            icon: const Icon(Icons.restart_alt),
                            label: Text(l10n.t('show_all')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saveForLater,
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: Text(l10n.t('save_for_later')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else if (visibleResults.isNotEmpty) ...[
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        l10n.t('results_summary', {
                          'visible': '${visibleResults.length}',
                          'total': '${_results.length}',
                          'indexers': _formatSourcesBreakdown(),
                        }),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                      if (_indexerErrors.isNotEmpty) _buildIndexerErrorsChip(l10n),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<_SortMode>(
                        value: _sortMode,
                        underline: const SizedBox.shrink(),
                        items: [
                          DropdownMenuItem(
                            value: _SortMode.seeders,
                            child: Text(l10n.t('sort_seeders')),
                          ),
                          DropdownMenuItem(
                            value: _SortMode.dateDesc,
                            child: Text(l10n.t('sort_date_desc')),
                          ),
                          DropdownMenuItem(
                            value: _SortMode.dateAsc,
                            child: Text(l10n.t('sort_date_asc')),
                          ),
                          DropdownMenuItem(
                            value: _SortMode.quality,
                            child: Text(l10n.t('sort_quality')),
                          ),
                          DropdownMenuItem(
                            value: _SortMode.sizeDesc,
                            child: Text(l10n.t('sort_size_desc')),
                          ),
                          DropdownMenuItem(
                            value: _SortMode.sizeAsc,
                            child: Text(l10n.t('sort_size_asc')),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _sortMode = v);
                        },
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _saveForLater,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: Text(l10n.t('later_short')),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...visibleResults.map((item) => _buildResultCard(l10n, item)),
            ],
          ],
        ),
      ),
    );
  }

  String _formatSourcesBreakdown() {
    final active = _countsByIndexer.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (active.isNotEmpty) {
      return active.map((e) => '${e.key} (${e.value})').join(', ');
    }
    return _queriedIndexers.join(', ');
  }

  Widget _buildIndexerErrorsChip(AppL10n l10n) {
    final tooltipText = _indexerErrors.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    return Tooltip(
      message: tooltipText,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _showSourceErrorsDialog(l10n),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF451A03),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFF59E0B)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 13, color: Color(0xFFFDE68A)),
              const SizedBox(width: 4),
              Text(
                l10n.t('sources_errors_chip', {'count': '${_indexerErrors.length}'}),
                style: const TextStyle(
                  color: Color(0xFFFDE68A),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSourceErrorsDialog(AppL10n l10n) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111C33),
        title: Text(l10n.t('sources_errors_title')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: _indexerErrors.entries
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.key,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          Text(
                            e.value,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.t('close')),
          ),
        ],
      ),
    );
  }

  Widget _stepPill(String label, {required bool active, required bool done}) {
    final bg = active
        ? const Color(0xFF0C4A6E)
        : done
            ? const Color(0xFF14532D)
            : const Color(0xFF1E293B);
    final fg = active
        ? const Color(0xFF7DD3FC)
        : done
            ? const Color(0xFF86EFAC)
            : const Color(0xFF94A3B8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildInfoLookupResults(AppL10n l10n) {
    if (_loadingInfo) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                _mediaType == MediaType.series
                    ? l10n.t('loading_series_db')
                    : l10n.t('loading_movie_db'),
              ),
            ],
          ),
        ),
      );
    }

    if (_suggestions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Icon(Icons.search_off_outlined, size: 36, color: Color(0xFF94A3B8)),
              const SizedBox(height: 8),
              Text(
                l10n.t('no_match_found'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.t('no_match_hint'),
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _skipInfoStep,
                icon: const Icon(Icons.fast_forward_outlined, size: 17),
                label: Text(l10n.t('skip_search_text')),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _mediaType == MediaType.series
                  ? l10n.t('step2_series_prompt')
                  : l10n.t('step2_movie_prompt'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
            const SizedBox(height: 10),
            ..._suggestions.map((s) => _buildSuggestionCard(l10n, s)),
          ],
        ),
      ),
    );
  }

  Widget _buildPoster(String? posterUrl, {double width = 62, double height = 92}) {
    if (posterUrl == null || posterUrl.isEmpty) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF172542),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF243559)),
        ),
        child: Icon(
          _mediaType == MediaType.series ? Icons.tv_outlined : Icons.movie_outlined,
          color: const Color(0xFF94A3B8),
          size: 30,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        posterUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: const Color(0xFF172542),
          child: const Icon(Icons.movie_outlined, color: Color(0xFF94A3B8), size: 30),
        ),
      ),
    );
  }

  Widget _flagPill(String langCode, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CountryFlag(code: langCode, width: 17, height: 12),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildSeriesBadges(AppL10n l10n, MovieSuggestion s) {
    if (s.mediaType != MediaType.series) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 5,
        children: [
          if (s.seasonCount != null)
            _pill(
              '📺 ${s.seasonCount} ${s.seasonCount! > 1 ? l10n.t('season_plural') : l10n.t('season_singular')}',
              const Color(0xFF1E3A8A),
              const Color(0xFFBFDBFE),
            ),
          if (s.seriesStatus != null && s.seriesStatus!.isNotEmpty)
            _pill(
              s.seriesStatus!,
              s.seriesStatus == 'En cours'
                  ? const Color(0xFF14532D)
                  : const Color(0xFF334155),
              s.seriesStatus == 'En cours'
                  ? const Color(0xFF86EFAC)
                  : const Color(0xFFCBD5E1),
            ),
          if (s.nextSeasonInfo != null && s.nextSeasonInfo!.isNotEmpty)
            _pill(
              '📅 ${s.nextSeasonInfo}',
              const Color(0xFF78350F),
              const Color(0xFFFDE68A),
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(AppL10n l10n, MovieSuggestion s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF243559)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPoster(s.posterUrl, width: 64, height: 94),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${s.titleFr}${s.year != null ? ' (${s.year})' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                    Text(
                      s.source,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    _flagPill(
                      'FR',
                      'FR : ${s.titleFr}',
                      const Color(0xFF172542),
                      const Color(0xFFE2E8F0),
                    ),
                    if (s.titleEn != null && s.titleEn!.isNotEmpty)
                      _flagPill(
                        'EN',
                        'EN : ${s.titleEn}',
                        const Color(0xFF172542),
                        const Color(0xFF7DD3FC),
                      ),
                    if (s.titleEs != null && s.titleEs!.isNotEmpty)
                      _flagPill(
                        'ES',
                        'ES : ${s.titleEs}',
                        const Color(0xFF172542),
                        const Color(0xFFFCD34D),
                      ),
                    if (s.titleOriginal.toLowerCase() != s.titleFr.toLowerCase() &&
                        s.titleOriginal.toLowerCase() != (s.titleEn ?? '').toLowerCase() &&
                        s.titleOriginal.toLowerCase() != (s.titleEs ?? '').toLowerCase())
                      _pill(
                        'VO : ${s.titleOriginal}',
                        const Color(0xFF172542),
                        const Color(0xFFD8B4FE),
                      ),
                  ],
                ),
                _buildSeriesBadges(l10n, s),
                if (s.synopsis != null && s.synopsis!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    s.synopsis!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _selectMediaMatch(s),
                      icon: const Icon(Icons.check_circle_outline, size: 17),
                      label: Text(l10n.t('pick_this_title')),
                    ),
                    TextButton.icon(
                      onPressed: () => _saveForLater(overrideMedia: s),
                      icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                      label: Text(l10n.t('later_short')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Displays the selected Movie/Series info card with clickable localized title
  /// buttons that populate the editable Torrent Search box below.
  Widget _buildSelectedMediaInfoCard(AppL10n l10n, MovieSuggestion media) {
    final localizedChoices = <(String? flagCode, String title)>[
      ('FR', media.titleFr),
      if (media.titleEn != null &&
          media.titleEn!.trim().isNotEmpty &&
          media.titleEn!.toLowerCase() != media.titleFr.toLowerCase())
        ('EN', media.titleEn!.trim()),
      if (media.titleEs != null &&
          media.titleEs!.trim().isNotEmpty &&
          media.titleEs!.toLowerCase() != media.titleFr.toLowerCase() &&
          media.titleEs!.toLowerCase() != (media.titleEn ?? '').toLowerCase())
        ('ES', media.titleEs!.trim()),
      if (media.titleOriginal.trim().isNotEmpty &&
          media.titleOriginal.toLowerCase() != media.titleFr.toLowerCase() &&
          media.titleOriginal.toLowerCase() != (media.titleEn ?? '').toLowerCase() &&
          media.titleOriginal.toLowerCase() != (media.titleEs ?? '').toLowerCase())
        (null, media.titleOriginal.trim()),
    ];

    final maxSeasons = (media.seasonCount ?? 0).clamp(0, 10);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPoster(media.posterUrl, width: 74, height: 110),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${media.titleFr}${media.year != null ? ' (${media.year})' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _selectedMedia = null),
                        child: Text(
                          media.mediaType == MediaType.series
                              ? l10n.t('change_series')
                              : l10n.t('change_movie'),
                        ),
                      ),
                    ],
                  ),
                  _buildSeriesBadges(l10n, media),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('click_title_to_fill'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (code, title) in localizedChoices)
                        ActionChip(
                          onPressed: () {
                            setState(() => _setTorrentQueryFromTitle(title, year: media.year));
                            _torrentQueryFocus.requestFocus();
                          },
                          avatar: code != null
                              ? CountryFlag(code: code, width: 17, height: 12)
                              : const Icon(Icons.title, size: 15),
                          label: Text(title, style: const TextStyle(fontSize: 12)),
                        ),
                      if (media.year != null)
                        ActionChip(
                          onPressed: () => _appendTokenToTorrentQuery('${media.year}'),
                          label: Text('+ ${media.year}', style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  if (media.mediaType == MediaType.series) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.t('append_season_hint'),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var s = 1; s <= (maxSeasons > 0 ? maxSeasons : 5); s++)
                          ActionChip(
                            onPressed: () =>
                                _appendTokenToTorrentQuery('S${s.toString().padLeft(2, '0')}'),
                            label: Text(
                              '+ S${s.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ActionChip(
                          onPressed: () => _appendTokenToTorrentQuery('Complete'),
                          label: Text(
                            '+ ${l10n.t('complete_series')}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Quick filters organized cleanly by category (NO language filter).
  Widget _buildCategorizedFiltersCard(AppL10n l10n, int visibleCount) {
    Widget categoryRow(String title, List<Widget> chips) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: chips,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.t('quick_filters', {'count': '$visibleCount'}),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                if (_hasAnyTagFilters)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _clearAllTagFilters,
                    icon: const Icon(Icons.close, size: 15),
                    label: Text(l10n.t('show_all'), style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            categoryRow(l10n.t('cat_availability'), [
              FilterChip(
                selected: _onlyActiveSeeders,
                onSelected: (v) => setState(() => _onlyActiveSeeders = v),
                label: Text(l10n.t('active_seeders'), style: const TextStyle(fontSize: 12)),
              ),
              FilterChip(
                selected: _minTenSeeders,
                onSelected: (v) => setState(() => _minTenSeeders = v),
                label: Text(l10n.t('min_10_seeders'), style: const TextStyle(fontSize: 12)),
              ),
            ]),
            categoryRow(l10n.t('cat_max_size'), [
              for (final gb in [2, 5, 10])
                FilterChip(
                  selected: _maxSizeGb == gb,
                  onSelected: (v) => setState(() => _maxSizeGb = v ? gb : null),
                  label: Text('< $gb GB', style: const TextStyle(fontSize: 12)),
                ),
            ]),
            categoryRow(l10n.t('cat_resolution'), [
              for (final res in ['4K', '1080p', '720p'])
                FilterChip(
                  selected: _resolutionFilters.contains(res),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _resolutionFilters.add(res);
                    } else {
                      _resolutionFilters.remove(res);
                    }
                  }),
                  label: Text(res, style: const TextStyle(fontSize: 12)),
                ),
            ]),
            categoryRow(l10n.t('cat_source_codec'), [
              for (final fmt in [
                'BluRay',
                'WEB-DL',
                'WEBRip',
                'HDRip',
                'H.264 / x264',
                'x265',
                'HDR',
              ])
                FilterChip(
                  selected: _formatFilters.contains(fmt),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _formatFilters.add(fmt);
                    } else {
                      _formatFilters.remove(fmt);
                    }
                  }),
                  label: Text(fmt, style: const TextStyle(fontSize: 12)),
                ),
            ]),
            categoryRow(l10n.t('cat_quality'), [
              FilterChip(
                selected: _excludeCam,
                onSelected: (v) => setState(() => _excludeCam = v),
                label: Text(l10n.t('exclude_cam'), style: const TextStyle(fontSize: 12)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(AppL10n l10n, TorrentResult item) {
    final isBlocked = item.preScanStatus == SafetyStatus.blocked;
    final is4k = item.quality.toLowerCase().contains('4k') || item.quality.contains('2160p');
    final formattedDate = ReleaseParser.formatPublishedDate(item.publishedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isBlocked ? const Color(0xFFEF4444) : const Color(0xFF243559),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _pill(
                  item.quality,
                  is4k ? const Color(0xFF4C1D95) : const Color(0xFF0C4A6E),
                  is4k ? const Color(0xFFD8B4FE) : const Color(0xFF7DD3FC),
                ),
                // Display crisp vector country flags whenever languages are detected
                ...item.detectedLanguages.map(
                  (l) => _flagPill(
                    l,
                    _labelForLangCode(l),
                    const Color(0xFF14532D),
                    const Color(0xFF86EFAC),
                  ),
                ),
                _pill(item.indexer, const Color(0xFF1E293B), const Color(0xFF94A3B8)),
                if (isBlocked)
                  _pill(
                    l10n.t('suspicious_badge'),
                    const Color(0xFF7F1D1D),
                    const Color(0xFFFCA5A5),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(
                  l10n.t('size_label', {'size': item.sizeHuman}),
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  l10n.t('seeders_label', {'n': '${item.seeders}'}),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF22C55E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  l10n.t('leechers_label', {'n': '${item.leechers}'}),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFF59E0B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (formattedDate != null)
                  Text(
                    '📅 $formattedDate',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
              ],
            ),
            if (item.preScanWarnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.preScanWarnings.join(' • '),
                style: TextStyle(
                  fontSize: 12,
                  color: isBlocked ? const Color(0xFFFCA5A5) : const Color(0xFFFCD34D),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (item.torrentUrl != null || item.infoHash != null)
                  FilledButton.icon(
                    onPressed: isBlocked ? null : () => _openSandbox(item),
                    icon: const Icon(Icons.verified_user_outlined, size: 18),
                    label: Text(l10n.t('sandbox_btn')),
                  ),
                if (item.magnetUrl != null)
                  OutlinedButton.icon(
                    onPressed: isBlocked ? null : () => _sendToSeedr(item),
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text(l10n.t('send_to_seedr')),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _openNfo(item),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: Text(l10n.t('nfo_btn')),
                ),
                if (item.magnetUrl != null)
                  OutlinedButton.icon(
                    onPressed: () => _copyMagnet(item.magnetUrl!),
                    icon: const Icon(Icons.link, size: 18),
                    label: Text(l10n.t('copy_magnet')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
