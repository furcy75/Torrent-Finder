import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Selected movie or TV series (retains posterUrl, localized titles & series schedule!)
  MovieSuggestion? _selectedMedia;
  final Set<String> _activeSearchTitles = {};
  String? _selectedSeasonTag; // null (all), 'S01', 'S02', ..., or 'Complete'

  // Quick filter tags organized by category rows (CAM/TS excluded by default)
  final Set<String> _langResultFilters = {}; // 'FR', 'EN', 'ES', 'MULTI'
  bool _onlyActiveSeeders = false;
  bool _minTenSeeders = false;
  bool _excludeCam = true;
  int? _maxSizeGb; // 2, 5, 10, or null
  final Set<String> _resolutionFilters = {}; // '4K', '1080p', '720p'
  final Set<String> _formatFilters =
      {}; // 'BluRay', 'WEB-DL', 'WEBRip', 'HDRip', 'H.264 / x264', 'x265', 'HDR'

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

      // If this saved item did not yet have a posterUrl, try enriching it silently
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

  /// Complete reset to start a brand-new search from scratch.
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
      // Restore default filter tags (Exclure CAM/TS active by default)
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

  // -------------------------------------------------------------------
  // Step 1 -> Step 2: Identify movie or series via AlloCiné / TVMaze / Wikidata
  // -------------------------------------------------------------------
  Future<void> _identifyMedia() async {
    final query = _movieCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack(
        _mediaType == MediaType.series
            ? 'Saisissez d\'abord le nom d\'une série.'
            : 'Saisissez d\'abord le nom d\'un film.',
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

  // -------------------------------------------------------------------
  // Step 2 -> Step 3: Pick movie/series match & display vignette + titles
  // -------------------------------------------------------------------
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

  /// Bypass matching and search torrents directly with user's input.
  void _skipMatchingAndSearchDirect() {
    final query = _movieCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack('Saisissez d\'abord un titre.');
      return;
    }
    final manual = MovieSuggestion(
      titleFr: query,
      titleOriginal: query,
      mediaType: _mediaType,
      source: 'Recherche directe',
    );
    _selectMediaAndSearch(manual, autoLaunchTorrents: true);
  }

  // -------------------------------------------------------------------
  // Step 3: Execute torrent search with selected titles & optional season tag
  // -------------------------------------------------------------------
  Future<void> _performTorrentSearch() async {
    final activeList = _activeSearchTitles.toList();
    final primaryQuery = activeList.isNotEmpty ? activeList.first : _movieCtrl.text.trim();
    if (primaryQuery.isEmpty) {
      _showSnack('Sélectionnez au moins un titre à rechercher.');
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
    final m = overrideMedia ?? _selectedMedia;
    final titleFr = m?.titleFr ?? _movieCtrl.text.trim();
    if (titleFr.isEmpty) {
      _showSnack('Saisissez d\'abord un titre.');
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
          ? '« $titleFr » sauvegardé dans « Plus tard » (avec sa vignette).'
          : '« $titleFr » est déjà dans votre liste « Plus tard ».',
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
      'IT' => 'Italiano',
      'PT' => 'Português',
      'JA' || 'JP' => 'Japonais',
      _ => code.toUpperCase(),
    };
  }

  void _showSnack(String msg) {
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
    final seedr = SeedrService(storage: widget.storage);
    if (!seedr.isConnected) {
      _showSnack('Connectez un compte dans l\'onglet Seedr pour envoyer des torrents.');
      widget.onOpenSeedr?.call();
      return;
    }
    final magnet = item.magnetUrl;
    if (magnet == null || magnet.isEmpty) {
      _showSnack('Utilisez « Bac à sable (.torrent) » pour envoyer ce fichier vers Seedr.');
      return;
    }

    // Always let the user choose the Seedr account after inspecting live available quota
    final chosen = await SeedrPickerDialog.show(
      context,
      storage: widget.storage,
      torrentTitle: item.title,
      torrentSizeBytes: item.sizeBytes,
    );
    if (chosen == null || !mounted) return;

    try {
      _showSnack('Envoi vers Seedr (${chosen.displayName}) en cours...');
      final msg = await seedr.addMagnet(magnet, account: chosen);
      await widget.storage.setActiveSeedrAccount(chosen.id);
      widget.onSeedrTransferStarted?.call(chosen.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('☁️ Envoyé sur Seedr (${chosen.displayName}) : $msg'),
          action: widget.onOpenSeedr != null
              ? SnackBarAction(label: 'Ouvrir Seedr', onPressed: widget.onOpenSeedr!)
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
    await Clipboard.setData(ClipboardData(text: magnet));
    _showSnack('Lien Magnet copié dans le presse-papiers.');
  }

  @override
  Widget build(BuildContext context) {
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
            // Guided step indicator + "Nouvelle recherche" reset button
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _stepPill(
                        isSeries ? '1. Série' : '1. Film',
                        active: _stage == _SearchStage.input,
                        done: _stage != _SearchStage.input,
                      ),
                      _stepPill(
                        '2. Correspondance',
                        active: _stage == _SearchStage.pickMedia,
                        done: _stage == _SearchStage.results,
                      ),
                      _stepPill(
                        '3. Torrents',
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
                    label: const Text('Nouvelle recherche'),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // STEP 1: Clean title-only search card + Films / Séries toggle
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
                          label: const Text('Films'),
                        ),
                        ChoiceChip(
                          selected: _mediaType == MediaType.series,
                          onSelected: (_) => setState(() => _mediaType = MediaType.series),
                          avatar: const Icon(Icons.tv_outlined, size: 17),
                          label: const Text('Séries TV'),
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
                        labelText: isSeries ? 'Nom de la série' : 'Nom du film',
                        hintText: isSeries
                            ? 'Ex : Severance, Stranger Things, La Casa de Papel...'
                            : 'Ex : Les Évadés, Dune, Inception...',
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
                            isSeries
                                ? 'Identifier la série (AlloCiné / TVMaze)'
                                : 'Identifier le film (AlloCiné / Bases)',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _searchingTorrents ? null : _skipMatchingAndSearchDirect,
                          icon: const Icon(Icons.fast_forward_outlined, size: 18),
                          label: const Text('Passer (recherche directe)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // STEP 2: Matching results (AlloCiné + TVMaze + Wikidata + IMDb)
            if (_stage == _SearchStage.pickMedia) _buildStep2Suggestions(),

            // STEP 3: Selected movie/series card (poster + titles + seasons/dates)
            if (_stage == _SearchStage.results && _selectedMedia != null) ...[
              _buildSelectedMediaBanner(_selectedMedia!),
              const SizedBox(height: 12),
            ],

            if (_stage == _SearchStage.results && _results.isNotEmpty) ...[
              _buildCategorizedFiltersCard(visibleResults.length),
              const SizedBox(height: 12),
            ],

            if (_searchingTorrents)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Recherche des torrents sur les indexeurs sans pub...'),
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
                        isSeries
                            ? 'Aucun torrent trouvé pour cette série'
                            : 'Aucun torrent trouvé pour ce film',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Sauvegardez-le dans « Plus tard » pour y retourner facilement (sa vignette et ses dates seront conservées), ou lancez une nouvelle recherche.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF94A3B8)),
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
                            label: const Text('Sauvegarder pour plus tard'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _resetAllToZero,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Nouvelle recherche'),
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
                        'Aucun des ${_results.length} torrent(s) ne correspond aux filtres actifs'
                        '${_excludeCam ? ' (CAM/TS exclus par défaut)' : ''}.',
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
                            label: const Text('Tout afficher'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saveForLater,
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: const Text('Sauvegarder pour plus tard'),
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
                    '${visibleResults.length} / ${_results.length} torrent(s) • ${_queriedIndexers.join(", ")}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<_SortMode>(
                        value: _sortMode,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: _SortMode.seeders, child: Text('Tri : Seeders')),
                          DropdownMenuItem(value: _SortMode.quality, child: Text('Tri : Qualité')),
                          DropdownMenuItem(value: _SortMode.sizeDesc, child: Text('Tri : Taille ↓')),
                          DropdownMenuItem(value: _SortMode.sizeAsc, child: Text('Tri : Taille ↑')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _sortMode = v);
                        },
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _saveForLater,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Plus tard'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...visibleResults.map(_buildResultCard),
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

  Widget _buildStep2Suggestions() {
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
                    ? 'Recherche de la série (AlloCiné, TVMaze, Wikidata)...'
                    : 'Recherche du film (AlloCiné, Wikidata, IMDb)...',
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
              const Text(
                'Aucune fiche correspondante trouvée',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Vous pouvez lancer directement la recherche de torrents avec votre texte ou sauvegarder pour plus tard.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
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
                    label: const Text('Chercher les torrents quand même'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saveForLater,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Sauvegarder pour plus tard'),
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
                  ? 'Étape 2 — Sélectionnez la bonne série (dates des saisons incluses) :'
                  : 'Étape 2 — Sélectionnez le bon film pour lancer la recherche de torrents :',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
            const SizedBox(height: 10),
            ..._suggestions.map(_buildSuggestionCard),
            const Divider(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Vous ne trouvez pas la bonne fiche ?',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                ),
                OutlinedButton.icon(
                  onPressed: _skipMatchingAndSearchDirect,
                  icon: const Icon(Icons.fast_forward_outlined, size: 16),
                  label: const Text('Passer et chercher avec mon texte'),
                ),
                TextButton.icon(
                  onPressed: _saveForLater,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: const Text('Sauvegarder pour plus tard'),
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

  Widget _buildSeriesBadges(MovieSuggestion s) {
    if (s.mediaType != MediaType.series) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 5,
        children: [
          if (s.seasonCount != null)
            _pill(
              '📺 ${s.seasonCount} saison${s.seasonCount! > 1 ? 's' : ''}',
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

  Widget _buildSuggestionCard(MovieSuggestion s) {
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
                _buildSeriesBadges(s),
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
                      label: const Text('Sélectionner & chercher'),
                    ),
                    OutlinedButton(
                      onPressed: () => _selectMediaAndSearch(s, autoLaunchTorrents: false),
                      child: const Text('Choisir titres / saison'),
                    ),
                    TextButton.icon(
                      onPressed: () => _saveForLater(overrideMedia: s),
                      icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                      label: const Text('Plus tard'),
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

  Widget _buildSelectedMediaBanner(MovieSuggestion media) {
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
                                ? 'Changer de série'
                                : 'Changer de film',
                          ),
                        ),
                    ],
                  ),
                  _buildSeriesBadges(media),
                  const SizedBox(height: 6),
                  const Text(
                    'Titres utilisés pour la recherche torrent :',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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

                  // Quick Season selector for TV Series
                  if (media.mediaType == MediaType.series) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Cibler une saison :',
                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          selected: _selectedSeasonTag == null,
                          onSelected: (_) => setState(() => _selectedSeasonTag = null),
                          label: const Text('Toutes', style: TextStyle(fontSize: 12)),
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
                          label: const Text('Intégrale', style: TextStyle(fontSize: 12)),
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
                              ? 'Relancer la recherche torrent'
                              : 'Lancer la recherche torrent',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saveForLater,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                        label: const Text('Sauvegarder pour plus tard'),
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

  /// Quick filters organized cleanly in horizontal rows grouped by category.
  Widget _buildCategorizedFiltersCard(int visibleCount) {
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
                  '🏷️ Filtres rapides ($visibleCount affiché(s))',
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
                    label: const Text('Tout afficher', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            categoryRow('Langues', [
              for (final entry in const [
                ('FR', 'Français'),
                ('EN', 'English'),
                ('ES', 'Español'),
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
            categoryRow('Disponibilité', [
              FilterChip(
                selected: _onlyActiveSeeders,
                onSelected: (v) => setState(() => _onlyActiveSeeders = v),
                label: const Text('▲ Seeders actifs', style: TextStyle(fontSize: 12)),
              ),
              FilterChip(
                selected: _minTenSeeders,
                onSelected: (v) => setState(() => _minTenSeeders = v),
                label: const Text('🔥 ≥ 10 seeders', style: TextStyle(fontSize: 12)),
              ),
            ]),
            categoryRow('Taille max', [
              for (final gb in [2, 5, 10])
                FilterChip(
                  selected: _maxSizeGb == gb,
                  onSelected: (v) => setState(() => _maxSizeGb = v ? gb : null),
                  label: Text('< $gb Go', style: const TextStyle(fontSize: 12)),
                ),
            ]),
            categoryRow('Résolution', [
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
            categoryRow('Source & Codec', [
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
            categoryRow('Qualité', [
              FilterChip(
                selected: _excludeCam,
                onSelected: (v) => setState(() => _excludeCam = v),
                label: const Text('🚫 Sans CAM/TS', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(TorrentResult item) {
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
                  _pill('⛔ Suspect', const Color(0xFF7F1D1D), const Color(0xFFFCA5A5)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('Taille : ${item.sizeHuman}', style: const TextStyle(fontSize: 13)),
                Text(
                  '▲ Seeders : ${item.seeders}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF22C55E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '▼ Leechers : ${item.leechers}',
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
                    label: const Text('Bac à sable (.torrent)'),
                  ),
                if (item.magnetUrl != null)
                  OutlinedButton.icon(
                    onPressed: isBlocked ? null : () => _sendToSeedr(item),
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: const Text('Envoyer vers Seedr'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _openNfo(item),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('NFO / Détails'),
                ),
                if (item.magnetUrl != null)
                  OutlinedButton.icon(
                    onPressed: () => _copyMagnet(item.magnetUrl!),
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Copier Magnet'),
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
