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

  final _allocineService = AllocineService();
  final _indexersService = IndexersService();

  // Multi-language selection (can combine FR + EN + ES simultaneously)
  final Set<LanguageFilter> _selectedLangs = {LanguageFilter.fr};

  // Extra localized titles chosen from AlloCiné / Wikidata (FR / EN / ES / VO)
  final List<String> _extraTitles = [];

  // Quick filter tags applied live to search results
  bool _onlyActiveSeeders = false;
  bool _minTenSeeders = false;
  bool _excludeCam = false;
  int? _maxSizeGb; // 2, 5, 10, or null
  final Set<String> _resolutionFilters = {}; // '4K', '1080p', '720p'
  final Set<String> _formatFilters = {}; // 'BluRay', 'WEB-DL', 'WEBRip', 'HDRip', 'x265', 'HDR'

  _SortMode _sortMode = _SortMode.seeders;
  bool _loadingTitles = false;
  bool _searching = false;
  bool _hasSearched = false;

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
      _extraTitles
        ..clear()
        ..addAll(
          (req.originalTitle ?? '').trim().isNotEmpty ? [req.originalTitle!.trim()] : const [],
        );
      _selectedLangs
        ..clear()
        ..addAll(req.languages.isEmpty ? [LanguageFilter.fr] : req.languages);
      _activeWatchlistId = req.watchlistId;
      _suggestions = [];
      _performSearch();
    }
  }

  @override
  void dispose() {
    _movieCtrl.dispose();
    _yearCtrl.dispose();
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

  bool get _hasActiveTagFilters =>
      _onlyActiveSeeders ||
      _minTenSeeders ||
      _excludeCam ||
      _maxSizeGb != null ||
      _resolutionFilters.isNotEmpty ||
      _formatFilters.isNotEmpty;

  void _resetTagFilters() {
    setState(() {
      _onlyActiveSeeders = false;
      _minTenSeeders = false;
      _excludeCam = false;
      _maxSizeGb = null;
      _resolutionFilters.clear();
      _formatFilters.clear();
    });
  }

  Future<void> _lookupMultilingualTitles() async {
    final query = _movieCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack('Saisissez d\'abord le nom d\'un film.');
      return;
    }
    final year = int.tryParse(_yearCtrl.text.trim());
    setState(() {
      _loadingTitles = true;
      _suggestions = [];
    });
    final hits = await _allocineService.resolveMovieTitles(query, year: year);
    if (!mounted) return;
    setState(() {
      _loadingTitles = false;
      _suggestions = hits;
    });
    if (hits.isEmpty) {
      _showSnack('Aucun film trouvé sur AlloCiné / Wikidata pour « $query ».');
    }
  }

  void _applyMovieSuggestion(MovieSuggestion s, {String? preferredPrimaryTitle}) {
    final primary = (preferredPrimaryTitle ?? s.titleFr).trim();
    final extras = s.allDistinctTitles
        .where((t) => t.toLowerCase() != primary.toLowerCase())
        .toList();

    setState(() {
      _movieCtrl.text = primary;
      if (s.year != null) _yearCtrl.text = '${s.year}';
      _extraTitles
        ..clear()
        ..addAll(extras);
      _suggestions = [];
    });
    _showSnack(
      'Film sélectionné : $primary${s.year != null ? ' (${s.year})' : ''}'
      '${extras.isNotEmpty ? ' • ${extras.length} titre(s) international(aux) ajouté(s)' : ''}',
    );
  }

  Future<void> _performSearch({bool includeAllLanguages = false}) async {
    final query = _movieCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack('Entrez le nom d\'un film à rechercher.');
      return;
    }

    FocusScope.of(context).unfocus();
    final year = int.tryParse(_yearCtrl.text.trim());
    final langs = includeAllLanguages
        ? LanguageFilter.selectableFlags.toSet()
        : Set<LanguageFilter>.from(_selectedLangs);

    setState(() {
      _searching = true;
      _hasSearched = true;
      _suggestions = [];
      _results = [];
    });

    final summary = await _indexersService.search(
      query: query,
      extraTitles: _extraTitles,
      languages: langs,
      year: year,
      includeAllLanguages: includeAllLanguages,
      settings: widget.storage.settings,
    );

    if (widget.storage.settings.saveHistory) {
      await widget.storage.addHistory(
        HistoryItem(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          query: query,
          originalTitle: _extraTitles.isNotEmpty ? _extraTitles.first : null,
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
      _searching = false;
      _results = summary.results;
      _queriedIndexers = summary.indexersQueried;
    });
    widget.onDataChanged();
  }

  Future<void> _saveForLater() async {
    final title = _movieCtrl.text.trim();
    if (title.isEmpty) return;
    final year = int.tryParse(_yearCtrl.text.trim());

    final added = await widget.storage.addToWatchlist(
      WatchlistItem(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        titleFr: title,
        titleOriginal: _extraTitles.isNotEmpty ? _extraTitles.first : null,
        languages: _selectedLangs.toList(),
        year: year,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    widget.onDataChanged();
    _showSnack(
      added
          ? '« $title » sauvegardé dans « Plus tard ».'
          : '« $title » est déjà dans votre liste « Plus tard ».',
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
        if (f == 'x265') return hay.contains('x265') || hay.contains('hevc') || hay.contains('265');
        if (f == 'bluray') return hay.contains('bluray') || hay.contains('blu-ray') || hay.contains('bdrip');
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Search Card
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
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _performSearch(),
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
                            onSubmitted: (_) => _performSearch(),
                            decoration: const InputDecoration(
                              labelText: 'Année',
                              hintText: '2024',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _searching ? null : () => _performSearch(),
                          icon: const Icon(Icons.search),
                          label: const Text('Chercher'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loadingTitles ? null : _lookupMultilingualTitles,
                          icon: _loadingTitles
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.translate),
                          label: const Text('Titres AlloCiné / Toutes langues'),
                        ),
                      ],
                    ),

                    // Active multilingual titles selected from AlloCiné / Wikidata
                    if (_extraTitles.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'Titres associés :',
                            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                          ..._extraTitles.map(
                            (t) => InputChip(
                              label: Text(t, style: const TextStyle(fontSize: 12)),
                              onDeleted: () => setState(() => _extraTitles.remove(t)),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),
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

                    // Multilingual Movie Suggestions (AlloCiné + Wikidata FR/EN/ES)
                    if (_suggestions.isNotEmpty) ...[
                      const Divider(height: 24),
                      const Text(
                        'Titres trouvés — cliquez sur un film (ou sur un titre précis) pour rechercher :',
                        style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 8),
                      ..._suggestions.map(_buildSuggestionCard),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Quick Filter Tags Bar (always visible once results exist or user wants to pre-filter)
            if (_results.isNotEmpty) _buildFilterTagsCard(visibleResults.length),

            const SizedBox(height: 12),

            if (_searching)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Recherche sur les indexeurs sans pub...'),
                    ],
                  ),
                ),
              )
            else if (_hasSearched && _results.isEmpty)
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
                        'Sauvegardez ce film dans votre liste « Plus tard » pour y retourner en un clic, ou élargissez à toutes les langues.',
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
                            label: const Text('Garder pour plus tard'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _performSearch(includeAllLanguages: true),
                            icon: const Icon(Icons.public),
                            label: const Text('Essayer toutes langues'),
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
                        'Aucun des ${_results.length} torrent(s) ne correspond aux tags sélectionnés.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _resetTagFilters,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Réinitialiser les tags filtres'),
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

  Widget _buildSuggestionCard(MovieSuggestion s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1120),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF243559)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.posterUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                s.posterUrl!,
                width: 46,
                height: 68,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.movie, size: 36),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Icon(Icons.movie_outlined, size: 34, color: Color(0xFF94A3B8)),
            ),
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
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
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
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      label: Text('🇫🇷 ${s.titleFr}', style: const TextStyle(fontSize: 12)),
                      onPressed: () => _applyMovieSuggestion(s, preferredPrimaryTitle: s.titleFr),
                    ),
                    if (s.titleEn != null && s.titleEn!.isNotEmpty)
                      ActionChip(
                        label: Text('🇬🇧 ${s.titleEn}', style: const TextStyle(fontSize: 12)),
                        onPressed: () =>
                            _applyMovieSuggestion(s, preferredPrimaryTitle: s.titleEn),
                      ),
                    if (s.titleEs != null && s.titleEs!.isNotEmpty)
                      ActionChip(
                        label: Text('🇪🇸 ${s.titleEs}', style: const TextStyle(fontSize: 12)),
                        onPressed: () =>
                            _applyMovieSuggestion(s, preferredPrimaryTitle: s.titleEs),
                      ),
                    if (s.titleOriginal.toLowerCase() != s.titleFr.toLowerCase() &&
                        s.titleOriginal.toLowerCase() != (s.titleEn ?? '').toLowerCase() &&
                        s.titleOriginal.toLowerCase() != (s.titleEs ?? '').toLowerCase())
                      ActionChip(
                        label:
                            Text('🎬 VO : ${s.titleOriginal}', style: const TextStyle(fontSize: 12)),
                        onPressed: () =>
                            _applyMovieSuggestion(s, preferredPrimaryTitle: s.titleOriginal),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      _applyMovieSuggestion(s);
                      _performSearch();
                    },
                    icon: const Icon(Icons.search, size: 15),
                    label: Text(
                      'Rechercher avec tous ces titres${s.year != null ? ' (${s.year})' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                if (_hasActiveTagFilters)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _resetTagFilters,
                    icon: const Icon(Icons.close, size: 15),
                    label: const Text('Réinitialiser', style: TextStyle(fontSize: 12)),
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
                    label: Text('< $gb Go', style: const TextStyle(fontSize: 12)),
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
                // Source / Codec tags
                for (final fmt in ['BluRay', 'WEB-DL', 'WEBRip', 'HDRip', 'x265', 'HDR'])
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
                ...item.detectedLanguages.map(
                  (l) => _pill(l, const Color(0xFF14532D), const Color(0xFF86EFAC)),
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
