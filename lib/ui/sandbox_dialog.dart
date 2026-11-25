import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:safetorrent/l10n/app_l10n.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/models/safety_report.dart';
import 'package:safetorrent/models/torrent_result.dart';
import 'package:safetorrent/sandbox/sandbox_worker.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/release_parser.dart';
import 'package:safetorrent/services/seedr_service.dart';
import 'package:safetorrent/ui/seedr_picker_dialog.dart';
import 'package:share_plus/share_plus.dart';

class SandboxDialog extends StatefulWidget {
  const SandboxDialog({
    super.key,
    required this.torrent,
    required this.settings,
    this.storage,
    this.onSentToSeedr,
    this.onSeedrTransferStarted,
  });

  final TorrentResult torrent;
  final AppSettings settings;
  final LocalStorageService? storage;
  final VoidCallback? onSentToSeedr;
  final ValueChanged<String>? onSeedrTransferStarted;

  @override
  State<SandboxDialog> createState() => _SandboxDialogState();
}

class _SandboxDialogState extends State<SandboxDialog> {
  SandboxExecutionResult? _result;
  bool _saving = false;
  bool _sendingSeedr = false;
  String? _savedMessage;

  @override
  void initState() {
    super.initState();
    _runSandbox();
  }

  Future<void> _runSandbox() async {
    final allowedLocal = <String>{};
    for (final tz in widget.settings.torznabIndexers.where((e) => e.enabled)) {
      final host = Uri.tryParse(tz.baseUrl)?.host.toLowerCase();
      if (host != null && host.isNotEmpty) allowedLocal.add(host);
    }

    final res = await SandboxWorker.fetchAndSanitize(
      torrentUrl: widget.torrent.torrentUrl,
      infoHash: widget.torrent.infoHash,
      strictVideoOnly: widget.settings.strictVideoOnly,
      blockArchives: widget.settings.blockArchives,
      allowedLocalHosts: allowedLocal,
    );
    if (mounted) {
      setState(() => _result = res);
    }
  }

  String _safeFileName(String raw) {
    var clean = raw.replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_').trim();
    if (clean.isEmpty) clean = 'verified_video';
    if (!clean.toLowerCase().endsWith('.torrent')) clean = '$clean.torrent';
    return clean.length > 100 ? '${clean.substring(0, 92)}.torrent' : clean;
  }

  Future<void> _exportSanitizedTorrent(Uint8List bytes, String rawName) async {
    final l10n = AppL10n.of(context);
    setState(() => _saving = true);
    try {
      final fileName = _safeFileName(rawName);
      if (Platform.isAndroid || Platform.isIOS) {
        final tmpDir = await getTemporaryDirectory();
        final file = File('${tmpDir.path}${Platform.pathSeparator}$fileName');
        await file.writeAsBytes(bytes, flush: true);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/x-bittorrent', name: fileName)],
          subject: fileName,
        );
        if (mounted) {
          setState(() {
            _savedMessage = l10n.t('sandbox_ready_mobile', {'name': fileName});
          });
        }
      } else {
        final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
        final file = File('${dir.path}${Platform.pathSeparator}$fileName');
        await file.writeAsBytes(bytes, flush: true);
        if (mounted) {
          setState(() {
            _savedMessage = l10n.t('sandbox_saved_desktop', {'path': file.path});
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savedMessage = l10n.t('sandbox_save_error', {'err': '$e'}));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendSanitizedToSeedr(
    Uint8List bytes,
    String rawName,
    int totalSizeBytes,
  ) async {
    final storage = widget.storage;
    if (storage == null || storage.seedrAccounts.isEmpty) return;
    final l10n = AppL10n.of(context);

    final chosen = await SeedrPickerDialog.show(
      context,
      storage: storage,
      torrentTitle: rawName,
      torrentSizeBytes: totalSizeBytes > 0 ? totalSizeBytes : widget.torrent.sizeBytes,
    );
    if (chosen == null || !mounted) return;

    setState(() => _sendingSeedr = true);
    try {
      final seedr = SeedrService(storage: storage);
      final msg = await seedr.addTorrentBytes(
        bytes,
        _safeFileName(rawName),
        account: chosen,
      );
      await storage.setActiveSeedrAccount(chosen.id);
      widget.onSeedrTransferStarted?.call(chosen.id);
      if (!mounted) return;
      setState(
        () => _savedMessage = l10n.t('sent_to_seedr', {
          'account': chosen.displayName,
          'msg': msg,
        }),
      );
      widget.onSentToSeedr?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _savedMessage = '$e');
    } finally {
      if (mounted) setState(() => _sendingSeedr = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final res = _result;
    final report = res?.report;
    final seedrReady = (widget.storage?.seedrAccounts.isNotEmpty ?? false);

    return AlertDialog(
      backgroundColor: const Color(0xFF111C33),
      title: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFF22C55E)),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.t('sandbox_title'))),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: res == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.t('sandbox_loading'), textAlign: TextAlign.center),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _statusBanner(l10n, report!),
                    const SizedBox(height: 8),
                    Text(
                      l10n.t('sandbox_isolation', {'mode': report.sandboxMode}),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                    if (report.infoHash != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'SHA-1 : ${report.infoHash} • ${report.fileCount} (${report.videoFileCount} video) • ${ReleaseParser.formatSize(report.totalSizeBytes)}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                    ],
                    if (report.blockedReasons.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF450A0A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          report.blockedReasons.join('\n'),
                          style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
                        ),
                      ),
                    ],
                    if (report.warnings.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF451A03),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          report.warnings.join('\n'),
                          style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 13),
                        ),
                      ),
                    ],
                    if (report.sanitizedFieldsRemoved.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.t('sandbox_removed_meta', {
                          'fields': report.sanitizedFieldsRemoved.join(', '),
                        }),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                    ],
                    if (report.files.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        l10n.t('sandbox_files_header'),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      ...report.files.map(
                        (f) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Text(_categoryIcon(f.category)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  f.flaggedReason != null
                                      ? '${f.path} (${f.flaggedReason})'
                                      : f.path,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: f.category == FileCategory.blocked
                                        ? const Color(0xFFFCA5A5)
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                ReleaseParser.formatSize(f.sizeBytes),
                                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_savedMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF052E16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _savedMessage!,
                          style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 12.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('close')),
        ),
        if (report != null && report.safeToDownload && res?.sanitizedBytes != null) ...[
          if (seedrReady)
            OutlinedButton.icon(
              onPressed: _sendingSeedr
                  ? null
                  : () => _sendSanitizedToSeedr(
                        res!.sanitizedBytes!,
                        widget.torrent.title,
                        report.totalSizeBytes,
                      ),
              icon: _sendingSeedr
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined, size: 17),
              label: Text(l10n.t('send_to_seedr')),
            ),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () => _exportSanitizedTorrent(res!.sanitizedBytes!, widget.torrent.title),
            icon: const Icon(Icons.download_done),
            label: Text(
              Platform.isAndroid || Platform.isIOS
                  ? l10n.t('sandbox_save_mobile')
                  : l10n.t('sandbox_save_desktop'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _statusBanner(AppL10n l10n, SafetyReport report) {
    final (label, bg, fg) = switch (report.status) {
      SafetyStatus.safe => (
          l10n.t('sandbox_safe'),
          const Color(0xFF14532D),
          const Color(0xFF86EFAC),
        ),
      SafetyStatus.warning => (
          l10n.t('sandbox_warning'),
          const Color(0xFF78350F),
          const Color(0xFFFCD34D),
        ),
      SafetyStatus.blocked => (
          l10n.t('sandbox_blocked'),
          const Color(0xFF7F1D1D),
          const Color(0xFFFCA5A5),
        ),
      SafetyStatus.unverified => (
          l10n.t('sandbox_unverified'),
          const Color(0xFF1E293B),
          const Color(0xFFCBD5E1),
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }

  String _categoryIcon(FileCategory c) {
    return switch (c) {
      FileCategory.video => '🎬',
      FileCategory.subtitle => '💬',
      FileCategory.metadata => '📄',
      FileCategory.blocked => '⛔',
      FileCategory.unknown => '⚠️',
    };
  }
}
