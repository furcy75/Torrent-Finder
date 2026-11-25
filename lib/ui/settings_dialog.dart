import 'package:flutter/material.dart';
import 'package:safetorrent/l10n/app_l10n.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/release_parser.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.storage,
    this.onOpenSeedrTab,
  });

  final LocalStorageService storage;
  final VoidCallback? onOpenSeedrTab;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late AppSettings _draft;

  final _tzNameCtrl = TextEditingController();
  final _tzUrlCtrl = TextEditingController();
  final _tzKeyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _draft = widget.storage.settings;
  }

  @override
  void dispose() {
    _tzNameCtrl.dispose();
    _tzUrlCtrl.dispose();
    _tzKeyCtrl.dispose();
    super.dispose();
  }

  void _addTorznab() {
    final name = _tzNameCtrl.text.trim();
    final url = _tzUrlCtrl.text.trim();
    final uri = Uri.tryParse(url);
    if (name.isEmpty || uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return;
    }
    final next = [
      ..._draft.torznabIndexers,
      TorznabConfig(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        baseUrl: url,
        apiKey: _tzKeyCtrl.text.trim(),
      ),
    ];
    setState(() {
      _draft = _draft.copyWith(torznabIndexers: next);
      _tzNameCtrl.clear();
      _tzUrlCtrl.clear();
      _tzKeyCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final seedrAccounts = widget.storage.seedrAccounts;

    return AlertDialog(
      backgroundColor: const Color(0xFF111C33),
      title: Text(l10n.t('settings_title')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.t('settings_sandbox_section'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.strictVideoOnly,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(strictVideoOnly: v)),
                title: Text(l10n.t('settings_strict_video')),
                subtitle: Text(l10n.t('settings_strict_video_sub')),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.blockArchives,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(blockArchives: v)),
                title: Text(l10n.t('settings_block_archives')),
                subtitle: Text(l10n.t('settings_block_archives_sub')),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.t('settings_seedr_section'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (widget.onOpenSeedrTab != null)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onOpenSeedrTab!.call();
                      },
                      icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                      label: Text(l10n.t('settings_manage_add')),
                    ),
                ],
              ),
              if (seedrAccounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    l10n.t('settings_no_seedr'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                )
              else
                ...seedrAccounts.map(
                  (acc) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cloud_done_outlined, color: Color(0xFF22C55E)),
                    title: Text(acc.displayName),
                    subtitle: Text(
                      [
                        if (acc.username != null && acc.username != acc.displayName) acc.username!,
                        if (acc.lastSpaceFree != null && acc.lastSpaceMax != null)
                          '${l10n.t('space_free', {'free': ReleaseParser.formatSize(acc.lastSpaceFree!)})} / ${ReleaseParser.formatSize(acc.lastSpaceMax!)}',
                      ].join(' • '),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      tooltip: l10n.t('delete'),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        await widget.storage.deleteSeedrAccount(acc.id);
                        setState(() {});
                      },
                    ),
                  ),
                ),
              const Divider(),
              Text(
                l10n.t('settings_sources_section'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableYts,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableYts: v)),
                title: const Text('YTS (HD / 4K Movies — direct .torrent)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableApibay,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableApibay: v)),
                title: const Text('APIBay (Movies & Series — full NFO)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableKnaben,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableKnaben: v)),
                title: const Text('Knaben (Multi-trackers: 1337x, TGx, TPB, RuTracker...)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableTorrentCsv,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableTorrentCsv: v)),
                title: const Text('TorrentCSV (Open-source JSON index)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableSolidTorrents,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableSolidTorrents: v)),
                title: const Text('SolidTorrents (Video JSON API)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableEztv,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableEztv: v)),
                title: const Text('EZTV (TV Series — direct .torrent)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableBitSearch,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableBitSearch: v)),
                title: const Text('BitSearch (Movies & Series meta-index)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableNyaa,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableNyaa: v)),
                title: const Text('Nyaa (Anime & Animation RSS — direct .torrent)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableLimeTorrents,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableLimeTorrents: v)),
                title: const Text('LimeTorrents (Movies & Series RSS — direct .torrent)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableArchiveOrg,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableArchiveOrg: v)),
                title: const Text('Internet Archive (Classics & public domain)'),
              ),
              const Divider(),
              Text(
                l10n.t('settings_torznab_section'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ..._draft.torznabIndexers.map(
                (tz) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tz.name),
                  subtitle: Text(tz.baseUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _draft = _draft.copyWith(
                          torznabIndexers:
                              _draft.torznabIndexers.where((e) => e.id != tz.id).toList(),
                        );
                      });
                    },
                  ),
                ),
              ),
              TextField(
                controller: _tzNameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.t('settings_torznab_name'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _tzUrlCtrl,
                decoration: InputDecoration(
                  labelText: l10n.t('settings_torznab_url'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tzKeyCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.t('settings_api_key'),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _addTorznab, child: Text(l10n.t('add'))),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: () async {
            await widget.storage.updateSettings(_draft);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text(l10n.t('save')),
        ),
      ],
    );
  }
}
