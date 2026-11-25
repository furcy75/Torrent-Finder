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

enum _SortMode { seeders, quality, sizeDesc, sizeAsc }

enum _SearchStage { input, pickMedia, results }

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
  final _movieCtrl = TextEditingController();
  final _movieFocus = FocusNode();

  final _allocineService = AllocineService();
  final _indexersService = IndexersService();

  MediaType _mediaType = MediaType.movie;
  _SearchStage _stage = _SearchStage.input;

  MovieSuggestion? _selectedMedia;
  final Set<String> _activeSearchTitles = {};
  String? _selectedSeasonTag;

  // Quick filter tags organized by category rows (CAM/TS excluded by default)
  final Set<String> _langResultFilters = {};
  bool _onlyActiveSeeders = false;
  bool _minTenSeeders = false;
  bool _excludeCam = true;
  int? _maxSizeGb;
  final Set<String> _resolutionFilters = {};
  final Set<String> _formatFilters = {};

  _SortMode _sortMode = _SortMode.seeders;
  bool _loadingTitles = false;
  bool _searchingTorrents = false;
  bool _hasSearchedTorrents = false;

  List<MovieSuggestion> _suggestions = [];
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
      _movieCtrl.text = media.titleFr;
      _selectedMedia = media;
      _selectedSeasonTag = null;
      _activeSearchTitles
        ..clear()
        ..addAll(media.allDistinctTitles);
      _activeWatchlistId = req.watchlistId;
      _suggestions = [];
      _stage = _SearchStage.results;
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
    _movieCtrl.dispose();
    _movieFocus.dispose();
    super.dispose();
  }

  void _resetAllToZero() {
    setState(() {
      _movieCtrl.clear();
      _stage = _SearchStage.input;
      _selectedMedia = null;
      _selectedSeasonTag = null;
      _activeSearchTitles.clear();
      _suggestions = [];
      _results = [];
      _queriedIndexers = [];
      _activeWatchlistId = null;
      _loadingTitles = false;
      _searchingTorrents = false;
      _hasSearchedTorrents = false;
      _langResultFilters.clear();
      _onlyActiveSeeders = false;
      _minTenSeeders = false;
      _excludeCam = true;
      _maxSizeGb = null;
      _resolutionFilters.clear();
      _formatFilters.clear();
      _sortMode = _SortMode.seeders;
    });
    _movieFocus.requestFocus();
  }

  bool get _hasAnyTagFilters =>
      _langResultFilters.isNotEmpty ||
      _onlyActiveSeeders ||
      _minTenSeeders ||
      _excludeCam ||
      _maxSizeGb != null ||
      _resolutionFilters.isNotEmpty ||
      _formatFilters.isNotEmpty;

  void _clearAllTagFilters() {
    setState(() {
      _langResultFilters.clear();
      _onlyActiveSeeders = false;
      _minTenSeeders = false;
      _excludeCam = false;
      _maxSizeGb = null;
      _resolutionFilters.clear();
      _formatFilters.clear();
    });
  }

  Future<void> _identifyMedia() async {
    final l10n = AppL10n.of(context);
    final query = _movieCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack(
        _mediaType == MediaType.series
            ? l10n.t('enter_series_first')
            : l10n.t('enter_movie_first'),
      );
      _movieFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();

    setState(() {
      _loadingTitles = true;
      _stage = _SearchStage.pickMedia;
      _suggestions = [];
      _selectedMedia = null;
      _selectedSeasonTag = null;
      _results = [];
      _hasSearchedTorrents = false;
    });

    final hits = await _allocineService.resolveTitles(query, mediaType: _mediaType);
    if (!mounted) return;
    setState(() {
      _loadingTitles = false;
      _suggestions = hits;
    });
  }

  void _selectMediaAndSearch(MovieSuggestion media, {bool autoLaunchTorrents = true}) {
    final titles = media.allDistinctTitles;
    setState(() {
      _selectedMedia = media;
      _mediaType = media.mediaType;
      _movieCtrl.text = media.titleFr;
      _selectedSeasonTag = null;
      _activeSearchTitles
        ..clear()
        ..addAll(titles);
      _stage = _SearchStage.results;
      _results = [];
      _hasSearchedTorrents = false;
    });
    if (autoLaunchTorrents) {
      _performTorrentSearch();
    }
  }

  void _skipMatchingAndSearchDirect() {
    final l10n = AppL10n.of(context);
    final query = _movieCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack(l10n.t('enter_title_first'));
      return;
    }
    final manual = MovieSuggestion(
      titleFr: query,
      titleOriginal: query,
      mediaType: _mediaType,
      source: l10n.t('direct_search'),
    );
    _selectMediaAndSearch(manual, autoLaunchTorrents: true);
  }

  Future<void> _performTorrentSearch() async {
    final l10n = AppL10n.of(context);
    final activeList = _activeSearchTitles.toList();
    final primaryQuery = activeList.isNotEmpty ? activeList.first : _movieCtrl.text.trim();
    if (primaryQuery.isEmpty) {
      _showSnack(l10n.t('select_one_title'));
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _searchingTorrents = true;
      _hasSearchedTorrents = true;
      _stage = _SearchStage.results;
      _results = [];
    });

    final summary = await _indexersService.search(
      query: primaryQuery,
      extraTitles: activeList.skip(1).toList(),
      mediaType: _selectedMedia?.mediaType ?? _mediaType,
      seasonQueryTag: _selectedSeasonTag,
      year: _selectedMedia?.year,
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
    });
    widget.onDataChanged();
  }

  Future<void> _saveForLater({MovieSuggestion? overrideMedia}) async {
    final l10n = AppL10n.of(context);
    final m = overrideMedia ?? _selectedMedia;
    final titleFr = m?.titleFr ?? _movieCtrl.text.trim();
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
    if (_langResultFilters.isNotEmpty) {
      final detected = item.detectedLanguages.map((e) => e.toUpperCase()).toSet();
      final matchedLang = _langResultFilters.any((req) {
        if (req == 'MULTI') return detected.contains('MULTI');
        if (detected.contains('MULTI')) return true;
        if (detected.contains(req)) return true;
        if (req == 'EN' && !detected.contains('FR') && !detected.contains('ES')) {
          return true;
        }
        return false;
      });
      if (!matchedLang) return false;
    }

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
    list.sort((a, b) {
      return switch (_sortMode) {
        _SortMode.seeders => b.seeders.compareTo(a.seeders),
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
    final canReset = _stage != _SearchStage.input ||
        _movieCtrl.text.isNotEmpty ||
        _selectedMedia != null ||
        _results.isNotEmpty;
    final isSeries = _mediaType == MediaType.series;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _stepPill(
                        isSeries ? l10n.t('step_series') : l10n.t('step_movie'),
                        active: _stage == _SearchStage.input,
                        done: _stage != _SearchStage.input,
                      ),
                      _stepPill(
                        l10n.t('step_match'),
                        active: _stage == _SearchStage.pickMedia,
                        done: _stage == _SearchStage.results,
                      ),
                      _stepPill(
                        l10n.t('step_torrents'),
                        active: _stage == _SearchStage.results,
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

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                      controller: _movieCtrl,
                      focusNode: _movieFocus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _identifyMedia(),
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
                          onPressed: _loadingTitles ? null : _identifyMedia,
                          icon: _loadingTitles
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search),
                          label: Text(
                            isSeries ? l10n.t('identify_series') : l10n.t('identify_movie'),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _searchingTorrents ? null : _skipMatchingAndSearchDirect,
                          icon: const Icon(Icons.fast_forward_outlined, size: 18),
                          label: Text(l10n.t('skip_direct')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            if (_stage == _SearchStage.pickMedia) _buildStep2Suggestions(l10n),

            if (_stage == _SearchStage.results && _selectedMedia != null) ...[
              _buildSelectedMediaBanner(l10n, _selectedMedia!),
              const SizedBox(height: 12),
            ],

            if (_stage == _SearchStage.results && _results.isNotEmpty) ...[
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
            else if (_stage == _SearchStage.results && _hasSearchedTorrents && _results.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.movie_filter_outlined, size: 44, color: Color(0xFF94A3B8)),
                      const SizedBox(height: 10),
                      Text(
                        isSeries ? l10n.t('no_torrents_series') : l10n.t('no_torrents_movie'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.t('no_torrents_hint'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF94A3B8)),
                      ),
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
            else if (_stage == _SearchStage.results &&
                _results.isNotEmpty &&
                visibleResults.isEmpty)
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
            else if (_stage == _SearchStage.results && visibleResults.isNotEmpty) ...[
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Text(
                    l10n.t('results_summary', {
                      'visible': '${visibleResults.length}',
                      'total': '${_results.length}',
                      'indexers': _queriedIndexers.join(', '),
                    }),
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
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

  Widget _buildStep2Suggestions(AppL10n l10n) {
    if (_loadingTitles) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
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
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              const Icon(Icons.search_off_outlined, size: 42, color: Color(0xFF94A3B8)),
              const SizedBox(height: 8),
              Text(
                l10n.t('no_match_found'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.t('no_match_hint'),
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _skipMatchingAndSearchDirect,
                    icon: const Icon(Icons.search),
                    label: Text(l10n.t('search_anyway')),
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
            const Divider(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.t('cant_find_match'),
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                ),
                OutlinedButton.icon(
                  onPressed: _skipMatchingAndSearchDirect,
                  icon: const Icon(Icons.fast_forward_outlined, size: 16),
                  label: Text(l10n.t('skip_search_text')),
                ),
                TextButton.icon(
                  onPressed: _saveForLater,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: Text(l10n.t('save_for_later')),
                ),
              ],
            ),
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
                      onPressed: () => _selectMediaAndSearch(s, autoLaunchTorrents: true),
                      icon: const Icon(Icons.search, size: 17),
                      label: Text(l10n.t('select_and_search')),
                    ),
                    OutlinedButton(
                      onPressed: () => _selectMediaAndSearch(s, autoLaunchTorrents: false),
                      child: Text(l10n.t('choose_titles_season')),
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

  Widget _buildSelectedMediaBanner(AppL10n l10n, MovieSuggestion media) {
    final allTitles = media.allDistinctTitles;
    String? flagCodeForTitle(String t) {
      final low = t.toLowerCase();
      if (low == media.titleFr.toLowerCase()) return 'FR';
      if (media.titleEn != null && low == media.titleEn!.toLowerCase()) return 'EN';
      if (media.titleEs != null && low == media.titleEs!.toLowerCase()) return 'ES';
      return null;
    }

    final maxSeasons = (media.seasonCount ?? 0).clamp(0, 12);

    return Card(
      color: const Color(0xFF13203B),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPoster(media.posterUrl, width: 76, height: 112),
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
                      if (_suggestions.length > 1)
                        TextButton(
                          onPressed: () => setState(() => _stage = _SearchStage.pickMedia),
                          child: Text(
                            media.mediaType == MediaType.series
                                ? l10n.t('change_series')
                                : l10n.t('change_movie'),
                          ),
                        ),
                    ],
                  ),
                  _buildSeriesBadges(l10n, media),
                  const SizedBox(height: 6),
                  Text(
                    l10n.t('titles_used'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: allTitles.map((t) {
                      final selected = _activeSearchTitles.contains(t);
                      final code = flagCodeForTitle(t);
                      return FilterChip(
                        selected: selected,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _activeSearchTitles.add(t);
                            } else if (_activeSearchTitles.length > 1) {
                              _activeSearchTitles.remove(t);
                            }
                          });
                        },
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (code != null) ...[
                              CountryFlag(code: code, width: 17, height: 12),
                              const SizedBox(width: 6),
                            ],
                            Text(t, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                  if (media.mediaType == MediaType.series) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.t('target_season'),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          selected: _selectedSeasonTag == null,
                          onSelected: (_) => setState(() => _selectedSeasonTag = null),
                          label: Text(l10n.t('all_seasons'), style: const TextStyle(fontSize: 12)),
                        ),
                        for (var s = 1; s <= (maxSeasons > 0 ? maxSeasons : 5); s++)
                          ChoiceChip(
                            selected: _selectedSeasonTag == 'S${s.toString().padLeft(2, '0')}',
                            onSelected: (_) => setState(
                              () => _selectedSeasonTag = 'S${s.toString().padLeft(2, '0')}',
                            ),
                            label: Text(
                              'S${s.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ChoiceChip(
                          selected: _selectedSeasonTag == 'Complete',
                          onSelected: (_) => setState(() => _selectedSeasonTag = 'Complete'),
                          label: Text(
                            l10n.t('complete_series'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _searchingTorrents ? null : _performTorrentSearch,
                        icon: const Icon(Icons.search, size: 17),
                        label: Text(
                          _hasSearchedTorrents
                              ? l10n.t('rerun_torrent_search')
                              : l10n.t('launch_torrent_search'),
                        ),
                      ),
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
          ],
        ),
      ),
    );
  }

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
            categoryRow(l10n.t('cat_languages'), [
              for (final entry in const [
                ('FR', 'Français'),
                ('EN', 'English'),
                ('ES', 'Español'),
                ('DE', 'Deutsch'),
                ('NL', 'Nederlands'),
                ('IT', 'Italiano'),
                ('MULTI', 'MULTI'),
              ])
                FilterChip(
                  selected: _langResultFilters.contains(entry.$1),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _langResultFilters.add(entry.$1);
                    } else {
                      _langResultFilters.remove(entry.$1);
                    }
                  }),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CountryFlag(code: entry.$1, width: 17, height: 12),
                      const SizedBox(width: 6),
                      Text(entry.$2, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
            ]),
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
