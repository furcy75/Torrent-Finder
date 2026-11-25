import 'package:flutter/material.dart';
import 'package:safetorrent/l10n/app_l10n.dart';
import 'package:safetorrent/models/seedr_models.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/release_parser.dart';
import 'package:safetorrent/services/seedr_service.dart';

/// Displays all connected Seedr accounts with their live available quota and
/// whether a file is currently downloading, and lets the user manually choose
/// which account should receive the torrent.
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
    fresh.sort((a, b) {
      int rank(SeedrAccountQuota q) {
        final fit = q.canFit(widget.torrentSizeBytes);
        if (fit == true && !q.hasActiveDownloads) return 0;
        if (fit == true) return 1;
        if (fit == null && !q.hasActiveDownloads) return 2;
        if (fit == null) return 3;
        return 4;
      }

      final cmp = rank(a).compareTo(rank(b));
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
    final l10n = AppL10n.of(context);
    final sizeKnown = widget.torrentSizeBytes > 0;
    final sizeText = sizeKnown
        ? ReleaseParser.formatSize(widget.torrentSizeBytes)
        : l10n.t('picker_size_unknown');

    return AlertDialog(
      backgroundColor: const Color(0xFF111C33),
      title: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: Color(0xFF38BDF8)),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.t('picker_title'))),
          IconButton(
            tooltip: l10n.t('picker_refresh'),
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
                      l10n.t('picker_required_size', {'size': sizeText}),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF7DD3FC)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _loading ? l10n.t('picker_loading') : l10n.t('picker_prompt'),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 8),
              ..._quotas.map((q) => _buildAccountOption(l10n, q)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('cancel')),
        ),
      ],
    );
  }

  Widget _buildAccountOption(AppL10n l10n, SeedrAccountQuota q) {
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
          l10n.t('picker_fits', {'free': ReleaseParser.formatSize(free!)}),
          const Color(0xFF14532D),
          const Color(0xFF86EFAC),
        ),
      false => (
          l10n.t('picker_no_space', {'free': ReleaseParser.formatSize(free!)}),
          const Color(0xFF7F1D1D),
          const Color(0xFFFCA5A5),
        ),
      null => (
          free != null
              ? '☁️ ${l10n.t('free_suffix', {'size': ReleaseParser.formatSize(free)})}'
              : (q.error != null ? l10n.t('picker_check_failed') : l10n.t('picker_checking')),
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
                  const Icon(Icons.account_circle_outlined, color: Color(0xFF38BDF8), size: 22),
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
                    label: Text(l10n.t('send')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
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
                  if (q.hasActiveDownloads)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF78350F),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        q.activeDownloadsCount == 1
                            ? l10n.t('picker_downloading_one')
                            : l10n.t('picker_downloading_many', {
                                'n': '${q.activeDownloadsCount}',
                              }),
                        style: const TextStyle(
                          color: Color(0xFFFDE68A),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else if (!_loading && q.error == null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C4A6E),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l10n.t('picker_idle'),
                        style: const TextStyle(
                          color: Color(0xFF7DD3FC),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              if (q.spaceMax != null && q.spaceMax! > 0 && q.spaceUsed != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.t('space_used', {
                        'used': ReleaseParser.formatSize(q.spaceUsed!),
                        'max': ReleaseParser.formatSize(q.spaceMax!),
                      }),
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                    ),
                    Text(
                      l10n.t('space_free', {'free': ReleaseParser.formatSize(free ?? 0)}),
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
