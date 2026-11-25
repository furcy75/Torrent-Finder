import 'package:flutter/material.dart';
import 'package:safetorrent/models/watchlist_item.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/ui/home_shell.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.storage,
    required this.onRerunSearch,
    required this.onDataChanged,
  });

  final LocalStorageService storage;
  final ValueChanged<PendingSearchRequest> onRerunSearch;
  final VoidCallback onDataChanged;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final items = widget.storage.history;
    final enabled = widget.storage.settings.saveHistory;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    '🕘 Historique des recherches',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (items.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      await widget.storage.clearHistory();
                      setState(() {});
                      widget.onDataChanged();
                    },
                    icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF4444)),
                    label: const Text(
                      'Tout effacer',
                      style: TextStyle(color: Color(0xFFEF4444)),
                    ),
                  ),
              ],
            ),
            Text(
              enabled
                  ? 'Enregistrement activé (stocké uniquement en local sur votre appareil).'
                  : 'Enregistrement désactivé — vos nouvelles recherches ne sont pas mémorisées.',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Historique vide.',
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
                    title: Text(item.query, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${item.language.flag} ${item.language.label} • ${item.resultCount} résultat(s)'
                      '${item.originalTitle != null ? ' • VO : ${item.originalTitle}' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Relancer',
                          icon: const Icon(Icons.search, color: Color(0xFF38BDF8)),
                          onPressed: () => widget.onRerunSearch(
                            PendingSearchRequest(
                              query: item.query,
                              originalTitle: item.originalTitle,
                              language: item.language,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Garder pour plus tard',
                          icon: const Icon(Icons.bookmark_add_outlined),
                          onPressed: () async {
                            await widget.storage.addToWatchlist(
                              WatchlistItem(
                                id: '${DateTime.now().microsecondsSinceEpoch}',
                                titleFr: item.query,
                                titleOriginal: item.originalTitle,
                                language: item.language,
                                createdAt: DateTime.now().toUtc(),
                              ),
                            );
                            widget.onDataChanged();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('« ${item.query} » ajouté à Plus tard.')),
                              );
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () async {
                            await widget.storage.deleteHistory(item.id);
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
