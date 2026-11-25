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
  final _originalCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();

  final _allocineService = AllocineService();
  final _indexersService = IndexersService();

  LanguageFilter _selectedLang = LanguageFilter.fr;
  _SortMode _sortMode = _SortMode.seeders;

  bool _showOriginalRow = false;
  bool _loadingAllocine = false;
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
      _originalCtrl.text = req.originalTitle ?? '';
      _yearCtrl.text = req.year?.toString() ?? '';
      _selectedLang = req.language;
      _showOriginalRow = (req.originalTitle ?? '').isNotEmpty;
      _activeWatchlistId = req.watchlistId;
      _suggestions = [];
      _performSearch();
    }
  }

  @override
  void dispose() {
    _movieCtrl.dispose();
    _originalCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupAllocine() async {
    final query = _movieCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack('Saisissez d\'abord le nom d\'un film.');
      return;
    }
    setState(() {
      _loadingAllocine = true;
      _suggestions = [];
    });
    final hits = await _allocineService.resolveMovieTitles(query);
    if (!mounted) return;
    setState(() {
      _loadingAllocine = false;
      _suggestions = hits;
    });
    if (hits.isEmpty) {
      _showSnack('Aucun titre original trouvé sur AlloCiné pour « $query ».');
    }
  }

  Future<void> _performSearch({bool includeAllLanguages = false}) async {
    final query = _movieCtrl.text.trim();
    if (query.isEmpty) {
      _showSnack('Entrez le nom d\'un film à rechercher.');
      return;
    }

    FocusScope.of(context).unfocus();
    final orig = _originalCtrl.text.trim();
    final year = int.tryParse(_yearCtrl.text.trim());
    final lang = includeAllLanguages ? LanguageFilter.all : _selectedLang;

    setState(() {
      _searching = true;
      _hasSearched = true;
      _suggestions = [];
      _results = [];
    });

    final summary = await _indexersService.search(
      query: query,
      originalTitle: orig.isNotEmpty ? orig : null,
      language: lang,
      year: year,
      includeAllLanguages: includeAllLanguages,
      settings: widget.storage.settings,
    );

    if (widget.storage.settings.saveHistory) {
      await widget.storage.addHistory(
        HistoryItem(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          query: query,
          originalTitle: orig.isNotEmpty ? orig : null,
          language: lang,
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
    final orig = _originalCtrl.text.trim();
    final year = int.tryParse(_yearCtrl.text.trim());

    final added = await widget.storage.addToWatchlist(
      WatchlistItem(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        titleFr: title,
        titleOriginal: orig.isNotEmpty ? orig : null,
        language: _selectedLang,
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

  List<TorrentResult> get _sortedResults {
    final list = List<TorrentResult>.from(_results);
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

  Future<void> _copyMagnet(String magnet) async {
    await Clipboard.setData(ClipboardData(text: magnet));
    _showSnack('Lien Magnet copié dans le presse-papiers.');
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedResults;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
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
                    TextField(
                      controller: _movieCtrl,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _performSearch(),
                      decoration: const InputDecoration(
                        labelText: 'Nom du film',
                        hintText: 'Ex : Les Évadés, Dune, Inception...',
                        prefixIcon: Icon(Icons.movie_outlined),
                      ),
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
                          onPressed: _loadingAllocine ? null : _lookupAllocine,
                          icon: _loadingAllocine
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.translate),
                          label: const Text('AlloCiné (Titre EN)'),
                        ),
                      ],
                    ),
                    if (_showOriginalRow) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _originalCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Titre original / anglais',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _yearCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Année',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Effacer le titre original',
                            onPressed: () {
                              _originalCtrl.clear();
                              _yearCtrl.clear();
                              setState(() => _showOriginalRow = false);
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'Langue voulue :',
                      style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: LanguageFilter.values.map((lang) {
                        final selected = _selectedLang == lang;
                        return ChoiceChip(
                          selected: selected,
                          onSelected: (_) => setState(() => _selectedLang = lang),
                          label: Text('${lang.flag} ${lang.label}'),
                        );
                      }).toList(),
                    ),
                    if (_suggestions.isNotEmpty) ...[
                      const Divider(height: 24),
                      const Text(
                        'Sélectionnez le film pour utiliser son titre original :',
                        style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 8),
                      ..._suggestions.map(
                        (s) => ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                          leading: s.posterUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    s.posterUrl!,
                                    width: 38,
                                    height: 54,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.movie),
                                  ),
                                )
                              : const Icon(Icons.movie_outlined),
                          title: Text(s.titleFr, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'VO : ${s.titleOriginal}${s.year != null ? ' (${s.year})' : ''} • ${s.source}',
                            style: const TextStyle(color: Color(0xFF38BDF8)),
                          ),
                          onTap: () {
                            setState(() {
                              _movieCtrl.text = s.titleFr;
                              _originalCtrl.text = s.titleOriginal;
                              _yearCtrl.text = s.year?.toString() ?? '';
                              _showOriginalRow = true;
                              _suggestions = [];
                            });
                            _showSnack('Titre original sélectionné : ${s.titleOriginal}');
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

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
            else if (_hasSearched && sorted.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.movie_filter_outlined, size: 44, color: Color(0xFF94A3B8)),
                      const SizedBox(height: 10),
                      const Text(
                        'Aucun torrent trouvé dans cette langue',
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
            else if (sorted.isNotEmpty) ...[
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Text(
                    '${sorted.length} torrent(s) • ${_queriedIndexers.join(", ")}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButton<_SortMode>(
                        value: _sortMode,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                            value: _SortMode.seeders,
                            child: Text('Tri : Seeders'),
                          ),
                          DropdownMenuItem(
                            value: _SortMode.quality,
                            child: Text('Tri : Qualité'),
                          ),
                          DropdownMenuItem(
                            value: _SortMode.sizeDesc,
                            child: Text('Tri : Taille ↓'),
                          ),
                          DropdownMenuItem(
                            value: _SortMode.sizeAsc,
                            child: Text('Tri : Taille ↑'),
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
                        label: const Text('Plus tard'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...sorted.map((item) => _buildResultCard(item)),
            ],
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
