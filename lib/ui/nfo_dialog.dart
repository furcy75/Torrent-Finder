import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safetorrent/l10n/app_l10n.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/services/nfo_service.dart';

/// Plain-text secure NFO / MediaInfo viewer (zero HTML/JS execution).
class NfoDialog extends StatefulWidget {
  const NfoDialog({super.key, required this.torrent});

  final TorrentResult torrent;

  @override
  State<NfoDialog> createState() => _NfoDialogState();
}

class _NfoDialogState extends State<NfoDialog> {
  final _nfoService = NfoService();
  NfoDetails? _details;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await _nfoService.fetchDetails(widget.torrent);
    if (mounted) setState(() => _details = res);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final details = _details;

    return AlertDialog(
      backgroundColor: const Color(0xFF111C33),
      title: Row(
        children: [
          const Icon(Icons.description_outlined, color: Color(0xFF38BDF8)),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.t('nfo_title'))),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 440,
        child: details == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(l10n.t('nfo_loading')),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.torrent.title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.t('nfo_source', {'source': details.sourceLabel}),
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1120),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF243559)),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          details.content,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.4,
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (details != null)
          TextButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: details.content));
              messenger.showSnackBar(SnackBar(content: Text(l10n.t('nfo_copied'))));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(l10n.t('copy')),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('close')),
        ),
      ],
    );
  }
}
