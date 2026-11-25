import 'package:flutter/material.dart';
import 'package:safetorrent/l10n/app_l10n.dart';
import 'package:safetorrent/models/movie_suggestion.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/models/watchlist_item.dart';
import 'package:safetorrent/services/allocine_service.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/ui/home_shell.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({
    super.key,
    required this.storage,
    required this.onRerunSearch,
    required this.onDataChanged,
  });

  final LocalStorageService storage;
  final ValueChanged<PendingSearchRequest> onRerunSearch;
  final VoidCallback onDataChanged;

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _allocineService = AllocineService();
  MediaType _manualType = MediaType.movie;
  final Set<String> _refreshingIds = {};

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _addManual() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final notes = _notesCtrl.text.trim();

    MovieSuggestion? resolved;
    final hits = await _allocineService.resolveTitles(title, mediaType: _manualType, limit: 1);
    if (hits.isNotEmpty) resolved = hits.first;

    await widget.storage.addToWatchlist(
      WatchlistItem(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        titleFr: resolved?.titleFr ?? title,
        titleOriginal: resolved?.titleOriginal,
        titleEn: resolved?.titleEn,
        titleEs: resolved?.titleEs,
        posterUrl: resolved?.posterUrl,
        mediaType: _manualType,
        tvMazeId: resolved?.tvMazeId,
        seriesStatus: resolved?.seriesStatus,
        seasonCount: resolved?.seasonCount,
        nextSeasonInfo: resolved?.nextSeasonInfo,
        nextReleaseDate: resolved?.nextReleaseDate,
        year: resolved?.year,
        languages: const [LanguageFilter.all],
        notes: notes.isNotEmpty ? notes : null,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    _titleCtrl.clear();
    _notesCtrl.clear();
    if (mounted) {
      setState(() {});
      widget.onDataChanged();
    }
  }

  Future<void> _refreshSeriesDate(WatchlistItem item) async {
    final l10n = AppL10n.of(context);
    setState(() => _refreshingIds.add(item.id));
    final info = await _allocineService.refreshSeriesSchedule(
      tvMazeId: item.tvMazeId,
      fallbackTitle: item.titleEn ?? item.titleOriginal ?? item.titleFr,
    );
    if (info != null) {
      await widget.storage.updateWatchlistItem(
        item.copyWith(
          tvMazeId: info.tvMazeId,
          seriesStatus: info.status ?? item.seriesStatus,
          seasonCount: info.seasonCount ?? item.seasonCount,
          nextSeasonInfo: info.nextSeasonInfo ?? item.nextSeasonInfo,
          nextReleaseDate: info.nextReleaseDate ?? item.nextReleaseDate,
          posterUrl: item.posterUrl ?? info.posterUrl,
        ),
      );
    }
    if (mounted) {
      setState(() => _refreshingIds.remove(item.id));
      widget.onDataChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            info?.nextSeasonInfo != null
                ? '${item.titleFr} : ${info!.nextSeasonInfo}'
                : l10n.t('schedule_checked', {
                    'title': item.titleFr,
                    'status': info?.status ?? l10n.t('no_new_date'),
                  }),
          ),
        ),
      );
    }
  }

  Widget _buildPoster(WatchlistItem item) {
    if (item.posterUrl != null && item.posterUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          item.posterUrl!,
          width: 54,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _posterFallback(item.mediaType),
        ),
      );
    }
    return _posterFallback(item.mediaType);
  }

  Widget _posterFallback(MediaType type) {
    return Container(
      width: 54,
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF172542),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF243559)),
      ),
      child: Icon(
        type == MediaType.series ? Icons.tv_outlined : Icons.movie_outlined,
        color: const Color(0xFF94A3B8),
        size: 26,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final items = widget.storage.watchlist;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.t('watchlist_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.t('watchlist_subtitle'),
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          selected: _manualType == MediaType.movie,
                          onSelected: (_) => setState(() => _manualType = MediaType.movie),
                          label: Text(l10n.t('chip_movie')),
                        ),
                        ChoiceChip(
                          selected: _manualType == MediaType.series,
                          onSelected: (_) => setState(() => _manualType = MediaType.series),
                          label: Text(l10n.t('chip_series')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleCtrl,
                      decoration: InputDecoration(
                        labelText: _manualType == MediaType.series
                            ? l10n.t('add_series_watch')
                            : l10n.t('add_movie_watch'),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _notesCtrl,
                            decoration: InputDecoration(
                              hintText: l10n.t('note_hint'),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addManual,
                          child: Text(l10n.t('add_plus')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.t('watchlist_empty'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ),
              )
            else
              ...items.map((item) => _buildWatchlistCard(l10n, item)),
          ],
        ),
      ),
    );
  }

  Widget _buildWatchlistCard(AppL10n l10n, WatchlistItem item) {
    final isSeries = item.mediaType == MediaType.series;
    final refreshing = _refreshingIds.contains(item.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPoster(item),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.year != null ? '${item.titleFr} (${item.year})' : item.titleFr,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      Text(
                        item.found
                            ? l10n.t('found_count', {'n': '${item.lastResultCount}'})
                            : l10n.t('pending_status'),
                        style: TextStyle(
                          fontSize: 12,
                          color: item.found ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      _badge(
                        isSeries ? l10n.t('chip_series') : l10n.t('chip_movie'),
                        const Color(0xFF1E293B),
                        const Color(0xFFCBD5E1),
                      ),
                      if (isSeries && item.seasonCount != null)
                        _badge(
                          '${item.seasonCount} ${item.seasonCount! > 1 ? l10n.t('season_plural') : l10n.t('season_singular')}',
                          const Color(0xFF1E3A8A),
                          const Color(0xFFBFDBFE),
                        ),
                      if (isSeries && item.seriesStatus != null && item.seriesStatus!.isNotEmpty)
                        _badge(
                          item.seriesStatus!,
                          const Color(0xFF14532D),
                          const Color(0xFF86EFAC),
                        ),
                      if (isSeries &&
                          item.nextSeasonInfo != null &&
                          item.nextSeasonInfo!.isNotEmpty)
                        _badge(
                          '📅 ${item.nextSeasonInfo}',
                          const Color(0xFF78350F),
                          const Color(0xFFFDE68A),
                        ),
                    ],
                  ),
                  if (item.titleOriginal != null || item.notes != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      [
                        if (item.titleOriginal != null) 'VO : ${item.titleOriginal}',
                        if (item.notes != null) 'Note : ${item.notes}',
                      ].join(' • '),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.icon(
                        onPressed: () => widget.onRerunSearch(
                          PendingSearchRequest(
                            movie: item.toMovieSuggestion(),
                            watchlistId: item.id,
                          ),
                        ),
                        icon: const Icon(Icons.search, size: 16),
                        label: Text(l10n.t('relaunch')),
                      ),
                      if (isSeries)
                        OutlinedButton.icon(
                          onPressed: refreshing ? null : () => _refreshSeriesDate(item),
                          icon: refreshing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.event_repeat_outlined, size: 16),
                          label: Text(l10n.t('refresh_date')),
                        ),
                      TextButton.icon(
                        onPressed: () async {
                          await widget.storage.deleteWatchlistItem(item.id);
                          setState(() {});
                          widget.onDataChanged();
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Color(0xFFEF4444),
                        ),
                        label: Text(
                          l10n.t('delete'),
                          style: const TextStyle(color: Color(0xFFEF4444)),
                        ),
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

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
