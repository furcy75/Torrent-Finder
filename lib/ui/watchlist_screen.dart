import 'package:flutter/material.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/models/watchlist_item.dart';
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

    await widget.storage.addToWatchlist(
      WatchlistItem(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        titleFr: title,
        languages: const [LanguageFilter.all],
        notes: notes.isNotEmpty ? notes : null,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    _titleCtrl.clear();
    _notesCtrl.clear();
    setState(() {});
    widget.onDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.storage.watchlist;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              '📌 Films non trouvés — À rechercher plus tard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sauvegardés localement sur cet appareil. Relancez la recherche en un clic.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ajouter un film à surveiller',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _notesCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Note (ex : 1080p VFF < 5 Go)',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addManual,
                          child: const Text('+ Ajouter'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Aucun film en attente pour le moment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ),
              )
            else
              ...items.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.year != null ? '${item.titleFr} (${item.year})' : item.titleFr,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          item.found ? '✅ ${item.lastResultCount} trouvé(s)' : '⏳ En attente',
                          style: TextStyle(
                            fontSize: 12,
                            color: item.found
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFF59E0B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      [
                        if (item.titleOriginal != null) 'VO : ${item.titleOriginal}',
                        if (item.notes != null) 'Note : ${item.notes}',
                      ].join(' • ').isNotEmpty
                          ? [
                              if (item.titleOriginal != null) 'VO : ${item.titleOriginal}',
                              if (item.notes != null) 'Note : ${item.notes}',
                            ].join(' • ')
                          : 'Prêt à relancer la recherche',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Relancer la recherche',
                          icon: const Icon(Icons.search, color: Color(0xFF38BDF8)),
                          onPressed: () => widget.onRerunSearch(
                            PendingSearchRequest(
                              query: item.titleFr,
                              originalTitle: item.titleOriginal,
                              year: item.year,
                              watchlistId: item.id,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                          onPressed: () async {
                            await widget.storage.deleteWatchlistItem(item.id);
                            setState(() {});
                            widget.onDataChanged();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
