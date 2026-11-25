import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safetorrent/models/history_item.dart';
import 'package:safetorrent/models/movie_suggestion.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/models/watchlist_item.dart';
import 'package:safetorrent/services/allocine_service.dart';
import 'package:safetorrent/services/indexers_service.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/release_parser.dart';
import 'package:safetorrent/ui/home_shell.dart';
import 'package:safetorrent/ui/nfo_dialog.dart';
import 'package:safetorrent/ui/sandbox_dialog.dart';

enum _SortMode { seeders, quality, sizeDesc, sizeAsc }

enum _SearchStage { input, pickMovie, results }

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.storage,
    required this.pendingRequest,
    required this.triggerId,
    required this.onDataChanged,
  });

  final LocalStorageService storage;
  final PendingSearchRequest? pendingRequest;
  final int triggerId;
  final VoidCallback onDataChanged;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _movieCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _movieFocus = FocusNode();

  final _allocineService = AllocineService();
  final _indexersService = IndexersService();

  _SearchStage _stage = _SearchStage.input;

  // Multi-language selection (can combine FR + EN + ES simultaneously)
  final Set<LanguageFilter> _selectedLangs = {LanguageFilter.fr};

  // Selected movie from step 2 (AlloCiné / Wikidata / IMDb) and active title choices
  MovieSuggestion? _selectedMovie;
  final Set<String> _activeSearchTitles = {};

  // Quick filter tags applied live to search results (CAM/TS excluded by default!)
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
      _movieCtrl.text = req.query;
      _yearCtrl.text = req.year?.toString() ?? '';
      _selectedLangs
        ..clear()
        ..addAll(req.languages.isEmpty ? [LanguageFilter.fr] : req.languages);
      _selectedMovie = MovieSuggestion(
        titleFr: req.query,
        titleOriginal: (req.originalTitle ?? '').trim().isNotEmpty
            ? req.originalTitle!.trim()
            : req.query,
        titleEn: (req.originalTitle ?? '').trim().isNotEmpty ? req.originalTitle!.trim() : null,
        year: req.year,
        source: 'Liste sauvegardée',
      );
      _activeSearchTitles
        ..clear()
        ..addAll(_selectedMovie!.allDistinctTitles);
      _activeWatchlistId = req.watchlistId;
      _suggestions = [];
      _stage = _SearchStage.results;
      _performTorrentSearch();
    }
  }

  @override
  void dispose() {
    _movieCtrl.dispose();
    _yearCtrl.dispose();
    _movieFocus.dispose();
    super.dispose();
  }

  bool get _allLangsSelected => _selectedLangs.length >= LanguageFilter.selectableFlags.length;

  void _toggleLanguage(LanguageFilter lang) {
    setState(() {
      if (_selectedLangs.contains(lang)) {
        if (_selectedLangs.length > 1) {
          _selectedLangs.remove(lang);
        }
      } else {
        _selectedLangs.add(lang);
      }
    });
  }

  void _selectAllLanguages() {
    setState(() {
      _selectedLangs
        ..clear()
        ..addAll(LanguageFilter.selectableFlags);
    });
  }

  /// Complete reset to start a brand-new search from scratch.
  void _resetAllToZero() {
    setState(() {
      _movieCtrl.clear();
      _yearCtrl.clear();
      _stage = _SearchStage.input;
      _selectedMovie = null;
      _activeSearchTitles.clear();
      _suggestions = [];
      _results = [];
      _queriedIndexers = [];
      _activeWatchlistId = null;
      _loadingTitles = false;
      _searchingTorrents = false;
      _hasSearchedTorrents = false;
      // Restore default filter tags (Exclure CAM/TS active by default)
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
  // Step 1 -> Step 2: Identify movie via AlloCiné / Wikidata / IMDb
  // -------------------------------------------------------------------
  Future<void> _identifyMovie() async {
    final query = _movieCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack('Saisissez d\'abord le nom d\'un film.');
      _movieFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    final year = int.tryParse(_yearCtrl.text.trim());

    setState(() {
      _loadingTitles = true;
      _stage = _SearchStage.pickMovie;
      _suggestions = [];
      _selectedMovie = null;
      _results = [];
      _hasSearchedTorrents = false;
    });

    final hits = await _allocineService.resolveMovieTitles(query, year: year);
    if (!mounted) return;
    setState(() {
      _loadingTitles = false;
      _suggestions = hits;
    });
  }

  // -------------------------------------------------------------------
  // Step 2 -> Step 3: Pick movie match & display vignette + titles
  // -------------------------------------------------------------------
  void _selectMovieAndSearch(MovieSuggestion movie, {bool autoLaunchTorrents = true}) {
    final titles = movie.allDistinctTitles;
    setState(() {
      _selectedMovie = movie;
      _movieCtrl.text = movie.titleFr;
      if (movie.year != null) _yearCtrl.text = '${movie.year}';
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

  /// Bypass AlloCiné/Wikidata matching and search torrents directly with user's input.
  void _skipMatchingAndSearchDirect() {
    final query = _movieCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack('Saisissez d\'abord le nom d\'un film.');
      return;
    }
    final year = int.tryParse(_yearCtrl.text.trim());
    final manual = MovieSuggestion(
      titleFr: query,
      titleOriginal: query,
      year: year,
      source: 'Recherche directe',
    );
    _selectMovieAndSearch(manual, autoLaunchTorrents: true);
  }

  // -------------------------------------------------------------------
  // Step 3: Execute torrent search with selected titles, year, & flags
  // -------------------------------------------------------------------
  Future<void> _performTorrentSearch({bool includeAllLanguages = false}) async {
    final activeList = _activeSearchTitles.toList();
    final primaryQuery = activeList.isNotEmpty ? activeList.first : _movieCtrl.text.trim();
    if (primaryQuery.isEmpty) {
      _showSnack('Sélectionnez au moins un titre à rechercher.');
      return;
    }

    FocusScope.of(context).unfocus();
    final year = _selectedMovie?.year ?? int.tryParse(_yearCtrl.text.trim());
    final langs = includeAllLanguages
        ? LanguageFilter.selectableFlags.toSet()
        : Set<LanguageFilter>.from(_selectedLangs);

    setState(() {
      _searchingTorrents = true;
      _hasSearchedTorrents = true;
      _stage = _SearchStage.results;
      _results = [];
    });

    final summary = await _indexersService.search(
      query: primaryQuery,
      extraTitles: activeList.skip(1).toList(),
      languages: langs,
      year: year,
      includeAllLanguages: includeAllLanguages,
      settings: widget.storage.settings,
    );

    // Only store history if user explicitly enabled it (disabled by default to avoid clutter)
    if (widget.storage.settings.saveHistory) {
      await widget.storage.addHistory(
        HistoryItem(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          query: _selectedMovie?.titleFr ?? primaryQuery,
          originalTitle: _selectedMovie?.titleEn ?? _selectedMovie?.titleOriginal,
          year: year,
          languages: langs.toList(),
          resultCount: summary.results.length,
          createdAt: DateTime.now().toUtc(),
        ),
      );
    }

    if (_activeWatchlistId != null) {
      final idx = widget.storage.watchlist.indexWhere((e) => e.id == _activeWatchlistId);
      if (idx != -1) {
        final item = widget.storage.watchlist[idx];
        await widget.storage.updateWatchlistItem(
          item.copyWith(
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

  Future<void> _saveForLater() async {
    final titleFr = _selectedMovie?.titleFr ?? _movieCtrl.text.trim();
    if (titleFr.isEmpty) {
      _showSnack('Saisissez d\'abord un nom de film.');
      return;
    }
    final titleOrig = _selectedMovie?.titleEn ??
        (_selectedMovie != null &&
                _selectedMovie!.titleOriginal.toLowerCase() != titleFr.toLowerCase()
            ? _selectedMovie!.titleOriginal
            : null);
    final year = _selectedMovie?.year ?? int.tryParse(_yearCtrl.text.trim());

    final added = await widget.storage.addToWatchlist(
      WatchlistItem(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        titleFr: titleFr,
        titleOriginal: titleOrig,
        languages: _selectedLangs.toList(),
        year: year,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    widget.onDataChanged();
    _showSnack(
      added
          ? '« $titleFr » sauvegardé dans « Plus tard ».'
          : '« $titleFr » est déjà dans votre liste « Plus tard ».',
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

  static String _flagForLangCode(String code) {
    return switch (code.toUpperCase()) {
      'FR' => '🇫🇷 FR',
      'EN' => '🇬🇧 EN',
      'ES' => '🇪🇸 ES',
      'MULTI' => '🌍 MULTI',
      'DE' => '🇩🇪 DE',
      'IT' => '🇮🇹 IT',
      'PT' => '🇵🇹 PT',
      'JA' || 'JP' => '🇯🇵 JP',
      _ => '🗣️ ${code.toUpperCase()}',
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
      ),
    );
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
        _yearCtrl.text.isNotEmpty ||
        _selectedMovie != null ||
        _results.isNotEmpty;

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
                      _stepPill('1. Film', active: _stage == _SearchStage.input, done: _stage != _SearchStage.input),
                      _stepPill('2. Correspondance', active: _stage == _SearchStage.pickMovie, done: _stage == _SearchStage.results),
                      _stepPill('3. Torrents', active: _stage == _SearchStage.results, done: false),
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

            // STEP 1: Movie input card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: _movieCtrl,
                            focusNode: _movieFocus,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _identifyMovie(),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Nom du film',
                              hintText: 'Ex : Les Évadés, Dune, Inception...',
                              prefixIcon: Icon(Icons.movie_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 102,
                          child: TextField(
                            controller: _yearCtrl,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _identifyMovie(),
                            decoration: const InputDecoration(
                              labelText: 'Année',
                              hintText: '2024',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Langues voulues (plusieurs choix possibles) :',
                      style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...LanguageFilter.selectableFlags.map((lang) {
                          final selected = _selectedLangs.contains(lang);
                          return FilterChip(
                            selected: selected,
                            onSelected: (_) => _toggleLanguage(lang),
                            label: Text('${lang.flag} ${lang.label}'),
                          );
                        }),
                        ActionChip(
                          avatar: Icon(
                            _allLangsSelected ? Icons.check_circle : Icons.public,
                            size: 16,
                          ),
                          label: const Text('🌍 Toutes'),
                          onPressed: _selectAllLanguages,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _loadingTitles ? null : _identifyMovie,
                          icon: _loadingTitles
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search),
                          label: const Text('Identifier le film (AlloCiné / Bases)'),
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

            // STEP 2: Movie matching results (AlloCiné + Wikidata + IMDb)
            if (_stage == _SearchStage.pickMovie) _buildStep2Suggestions(),

            // STEP 3: Selected movie card (vignette + multilingual titles) & Torrent results
            if (_stage == _SearchStage.results && _selectedMovie != null) ...[
              _buildSelectedMovieBanner(_selectedMovie!),
              const SizedBox(height: 12),
            ],

            if (_stage == _SearchStage.results && _results.isNotEmpty) ...[
              _buildFilterTagsCard(visibleResults.length),
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
                      Text('Recherche des torrents en cours...'),
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
                      const Text(
                        'Aucun torrent trouvé dans ces langues',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Sauvegardez ce film dans « Plus tard » pour y retourner facilement, élargissez à toutes les langues ou lancez une nouvelle recherche.',
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
                            onPressed: () => _performTorrentSearch(includeAllLanguages: true),
                            icon: const Icon(Icons.public),
                            label: const Text('Essayer toutes langues'),
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
                        'Aucun des ${_results.length} torrent(s) ne correspond aux tags actifs'
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
                            label: const Text('Afficher tous les résultats'),
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
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Recherche du film sur AlloCiné, Wikidata et IMDb...'),
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
                'Aucune fiche correspondante trouvée sur AlloCiné / Wikidata',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Vous pouvez lancer directement la recherche de torrents avec votre texte ou sauvegarder ce film pour plus tard.',
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
            const Text(
              'Étape 2 — Sélectionnez le bon film pour lancer la recherche de torrents :',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
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
                  'Vous ne trouvez pas le bon film ?',
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
        child: const Icon(Icons.movie_outlined, color: Color(0xFF94A3B8), size: 30),
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
                  runSpacing: 4,
                  children: [
                    _pill('🇫🇷 ${s.titleFr}', const Color(0xFF172542), const Color(0xFFE2E8F0)),
                    if (s.titleEn != null && s.titleEn!.isNotEmpty)
                      _pill('🇬🇧 ${s.titleEn}', const Color(0xFF172542), const Color(0xFF7DD3FC)),
                    if (s.titleEs != null && s.titleEs!.isNotEmpty)
                      _pill('🇪🇸 ${s.titleEs}', const Color(0xFF172542), const Color(0xFFFCD34D)),
                    if (s.titleOriginal.toLowerCase() != s.titleFr.toLowerCase() &&
                        s.titleOriginal.toLowerCase() != (s.titleEn ?? '').toLowerCase() &&
                        s.titleOriginal.toLowerCase() != (s.titleEs ?? '').toLowerCase())
                      _pill(
                        '🎬 VO : ${s.titleOriginal}',
                        const Color(0xFF172542),
                        const Color(0xFFD8B4FE),
                      ),
                  ],
                ),
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
                      onPressed: () => _selectMovieAndSearch(s, autoLaunchTorrents: true),
                      icon: const Icon(Icons.search, size: 17),
                      label: const Text('Sélectionner & chercher les torrents'),
                    ),
                    OutlinedButton(
                      onPressed: () => _selectMovieAndSearch(s, autoLaunchTorrents: false),
                      child: const Text('Choisir les titres d\'abord'),
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

  Widget _buildSelectedMovieBanner(MovieSuggestion movie) {
    final allTitles = movie.allDistinctTitles;
    String labelForTitle(String t) {
      final low = t.toLowerCase();
      if (low == movie.titleFr.toLowerCase()) return '🇫🇷 $t';
      if (movie.titleEn != null && low == movie.titleEn!.toLowerCase()) return '🇬🇧 $t';
      if (movie.titleEs != null && low == movie.titleEs!.toLowerCase()) return '🇪🇸 $t';
      return '🎬 $t';
    }

    return Card(
      color: const Color(0xFF13203B),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPoster(movie.posterUrl, width: 74, height: 110),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${movie.titleFr}${movie.year != null ? ' (${movie.year})' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                      if (_suggestions.length > 1)
                        TextButton(
                          onPressed: () => setState(() => _stage = _SearchStage.pickMovie),
                          child: const Text('Changer de film'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Titres utilisés pour la recherche torrent (cochez/décochez) :',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: allTitles.map((t) {
                      final selected = _activeSearchTitles.contains(t);
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
                        label: Text(labelForTitle(t), style: const TextStyle(fontSize: 12)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _searchingTorrents ? null : () => _performTorrentSearch(),
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

  Widget _buildFilterTagsCard(int visibleCount) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // Seeders tags
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
                // Size limit tags
                for (final gb in [2, 5, 10])
                  FilterChip(
                    selected: _maxSizeGb == gb,
                    onSelected: (v) => setState(() => _maxSizeGb = v ? gb : null),
                    label: Text('< $gb Go', style: TextStyle(fontSize: 12)),
                  ),
                // Resolution tags
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
                // Source / Codec tags (including H.264 / x264)
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
                // Excluded by default
                FilterChip(
                  selected: _excludeCam,
                  onSelected: (v) => setState(() => _excludeCam = v),
                  label: const Text('🚫 Sans CAM/TS', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
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
                // Language badges WITH flags directly on every torrent result
                ...item.detectedLanguages.map(
                  (l) => _pill(
                    _flagForLangCode(l),
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
