import 'package:flutter/material.dart';
import 'package:safetorrent/models/seedr_models.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/release_parser.dart';
import 'package:safetorrent/services/seedr_service.dart';

/// Displays all connected family Seedr accounts with their live available quota
/// compared against [torrentSizeBytes], and lets the user manually choose which
/// account should receive the torrent.
class SeedrPickerDialog extends StatefulWidget {
  const SeedrPickerDialog({
    super.key,
    required this.storage,
    required this.torrentTitle,
    required this.torrentSizeBytes,
  });

  final LocalStorageService storage;
  final String torrentTitle;
  final int torrentSizeBytes;

  static Future<SeedrSession?> show(
    BuildContext context, {
    required LocalStorageService storage,
    required String torrentTitle,
    required int torrentSizeBytes,
  }) {
    return showDialog<SeedrSession>(
      context: context,
      builder: (_) => SeedrPickerDialog(
        storage: storage,
        torrentTitle: torrentTitle,
        torrentSizeBytes: torrentSizeBytes,
      ),
    );
  }

  @override
  State<SeedrPickerDialog> createState() => _SeedrPickerDialogState();
}

class _SeedrPickerDialogState extends State<SeedrPickerDialog> {
  late final SeedrService _seedr = SeedrService(storage: widget.storage);
  bool _loading = true;
  List<SeedrAccountQuota> _quotas = [];

  @override
  void initState() {
    super.initState();
    // Show cached quotas immediately while live refresh loads
    _quotas = widget.storage.seedrAccounts
        .map(
          (a) => SeedrAccountQuota(
            account: a,
            spaceUsed: a.lastSpaceUsed,
            spaceMax: a.lastSpaceMax,
          ),
        )
        .toList();
    _refreshQuotas();
  }

  Future<void> _refreshQuotas() async {
    setState(() => _loading = true);
    final fresh = await _seedr.fetchAllAccountsQuota();
    if (!mounted) return;
    // Sort visually: accounts with enough space first, then highest free space
    fresh.sort((a, b) {
      final fitA = a.canFit(widget.torrentSizeBytes);
      final fitB = b.canFit(widget.torrentSizeBytes);
      int rank(bool? fit) => fit == true ? 0 : (fit == null ? 1 : 2);
      final cmp = rank(fitA).compareTo(rank(fitB));
      if (cmp != 0) return cmp;
      return (b.spaceFree ?? -1).compareTo(a.spaceFree ?? -1);
    });
    setState(() {
      _quotas = fresh;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sizeKnown = widget.torrentSizeBytes > 0;
    final sizeText =
        sizeKnown ? ReleaseParser.formatSize(widget.torrentSizeBytes) : 'Taille non précisée';

    return AlertDialog(
      backgroundColor: const Color(0xFF111C33),
      title: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: Color(0xFF38BDF8)),
          const SizedBox(width: 8),
          const Expanded(child: Text('Choisir un compte Seedr')),
          IconButton(
            tooltip: 'Actualiser les quotas',
            onPressed: _loading ? null : _refreshQuotas,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1120),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF243559)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.torrentTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Taille requise : $sizeText',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7DD3FC)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _loading
                    ? 'Vérification du quota disponible sur chaque compte...'
                    : 'Sélectionnez le compte Seedr vers lequel envoyer ce torrent :',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 8),
              ..._quotas.map(_buildAccountOption),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
      ],
    );
  }

  Widget _buildAccountOption(SeedrAccountQuota q) {
    final fit = q.canFit(widget.torrentSizeBytes);
    final free = q.spaceFree;
    final ratio = q.usedRatio;

    final borderColor = fit == true
        ? const Color(0xFF22C55E)
        : fit == false
            ? const Color(0xFFEF4444)
            : const Color(0xFF243559);

    final barColor = ratio > 0.9
        ? const Color(0xFFEF4444)
        : ratio > 0.75
            ? const Color(0xFFF59E0B)
            : const Color(0xFF22C55E);

    final (badgeText, badgeBg, badgeFg) = switch (fit) {
      true => (
          '✅ Espace suffisant (${ReleaseParser.formatSize(free!)} libre)',
          const Color(0xFF14532D),
          const Color(0xFF86EFAC),
        ),
      false => (
          '⚠️ Quota insuffisant (${ReleaseParser.formatSize(free!)} libre)',
          const Color(0xFF7F1D1D),
          const Color(0xFFFCA5A5),
        ),
      null => (
          free != null
              ? '☁️ ${ReleaseParser.formatSize(free)} libre'
              : (q.error != null ? '⚠️ Vérification impossible' : 'ℹ️ Quota en cours...'),
          const Color(0xFF1E293B),
          const Color(0xFFCBD5E1),
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF0B1120),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: fit == true ? 1.3 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).pop(q.account),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline, color: Color(0xFF38BDF8), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          q.account.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                        if (q.account.username != null || q.account.email != null)
                          Text(
                            [
                              if (q.account.username != null) q.account.username!,
                              if (q.account.packageName != null) q.account.packageName!,
                            ].join(' • '),
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                          ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).pop(q.account),
                    icon: const Icon(Icons.send_outlined, size: 15),
                    label: const Text('Envoyer'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(color: badgeFg, fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              if (q.spaceMax != null && q.spaceMax! > 0 && q.spaceUsed != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Utilisé : ${ReleaseParser.formatSize(q.spaceUsed!)} / ${ReleaseParser.formatSize(q.spaceMax!)}',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                    ),
                    Text(
                      'Libre : ${ReleaseParser.formatSize(free ?? 0)}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    backgroundColor: const Color(0xFF1E293B),
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
