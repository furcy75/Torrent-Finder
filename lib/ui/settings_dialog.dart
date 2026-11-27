import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safetorrent/l10n/app_l10n.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/services/custom_site_service.dart';
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
  final _customSiteService = CustomSiteService();

  // Torznab controllers
  final _tzNameCtrl = TextEditingController();
  final _tzUrlCtrl = TextEditingController();
  final _tzKeyCtrl = TextEditingController();

  // Custom website extractor controllers
  final _csNameCtrl = TextEditingController();
  final _csUrlCtrl = TextEditingController();
  final _csRowCtrl = TextEditingController();
  final _csTitleCtrl = TextEditingController();
  final _csLinkCtrl = TextEditingController();
  final _csSizeCtrl = TextEditingController();
  final _csSeedersCtrl = TextEditingController();
  final _csTestQueryCtrl = TextEditingController(text: 'ubuntu');

  bool _csFollowDetailPages = false;
  bool _testingCustomSite = false;
  String? _csTestFeedback;
  List<String> _csTestPreview = const [];
  bool _csTestIsError = false;

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
    _csNameCtrl.dispose();
    _csUrlCtrl.dispose();
    _csRowCtrl.dispose();
    _csTitleCtrl.dispose();
    _csLinkCtrl.dispose();
    _csSizeCtrl.dispose();
    _csSeedersCtrl.dispose();
    _csTestQueryCtrl.dispose();
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

  CustomSiteConfig? _buildDraftCustomSite() {
    final name = _csNameCtrl.text.trim();
    final url = _csUrlCtrl.text.trim();
    if (name.isEmpty || CustomSiteService.buildSearchUri(url, 'test') == null) {
      return null;
    }
    return CustomSiteConfig(
      id: 'cs_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      searchUrlTemplate: url,
      followDetailPages: _csFollowDetailPages,
      rowSelector: _csRowCtrl.text.trim(),
      titleSelector: _csTitleCtrl.text.trim(),
      linkSelector: _csLinkCtrl.text.trim(),
      sizeSelector: _csSizeCtrl.text.trim(),
      seedersSelector: _csSeedersCtrl.text.trim(),
    );
  }

  void _addCustomSite() {
    final l10n = AppL10n.of(context);
    final cfg = _buildDraftCustomSite();
    if (cfg == null) {
      setState(() {
        _csTestIsError = true;
        _csTestFeedback = l10n.t('custom_site_invalid_url');
        _csTestPreview = const [];
      });
      return;
    }
    setState(() {
      _draft = _draft.copyWith(customSites: [..._draft.customSites, cfg]);
      _csNameCtrl.clear();
      _csUrlCtrl.clear();
      _csRowCtrl.clear();
      _csTitleCtrl.clear();
      _csLinkCtrl.clear();
      _csSizeCtrl.clear();
      _csSeedersCtrl.clear();
      _csFollowDetailPages = false;
      _csTestFeedback = null;
      _csTestPreview = const [];
      _csTestIsError = false;
    });
  }

  Future<void> _testCustomSite({CustomSiteConfig? existing}) async {
    final l10n = AppL10n.of(context);
    final cfg = existing ?? _buildDraftCustomSite();
    if (cfg == null) {
      setState(() {
        _csTestIsError = true;
        _csTestFeedback = l10n.t('custom_site_invalid_url');
        _csTestPreview = const [];
      });
      return;
    }

    final testQuery = _csTestQueryCtrl.text.trim().isNotEmpty
        ? _csTestQueryCtrl.text.trim()
        : 'ubuntu';

    setState(() {
      _testingCustomSite = true;
      _csTestFeedback = null;
      _csTestPreview = const [];
      _csTestIsError = false;
    });

    final res = await _customSiteService.testSite(cfg, testQuery: testQuery);
    if (!mounted) return;

    if (res.error != null) {
      setState(() {
        _testingCustomSite = false;
        _csTestIsError = true;
        _csTestFeedback = '${cfg.name}: ${res.error}';
        _csTestPreview = const [];
      });
    } else if (res.results.isEmpty) {
      setState(() {
        _testingCustomSite = false;
        _csTestIsError = true;
        _csTestFeedback =
            '${cfg.name}: ${l10n.t('custom_site_test_empty', {'status': '${res.httpStatus ?? 200}'})}';
        _csTestPreview = const [];
      });
    } else {
      setState(() {
        _testingCustomSite = false;
        _csTestIsError = false;
        _csTestFeedback =
            '${cfg.name}: ${l10n.t('custom_site_test_ok', {'count': '${res.results.length}'})}';
        _csTestPreview = res.results
            .take(3)
            .map((r) => '• ${r.title} (${r.sizeHuman}, ▲${r.seeders})')
            .toList();
      });
    }
  }

  Future<void> _exportCustomSites() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppL10n.of(context);
    final payload = CustomSiteConfig.encodeListJson(_draft.customSites);
    await Clipboard.setData(ClipboardData(text: payload));
    messenger.showSnackBar(SnackBar(content: Text(l10n.t('custom_site_exported'))));
  }

  Future<void> _importCustomSites() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppL10n.of(context);
    var pasted = '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111C33),
        title: Text(l10n.t('custom_site_import_title')),
        content: SizedBox(
          width: 460,
          child: TextField(
            maxLines: 7,
            autofocus: true,
            onChanged: (v) => pasted = v,
            decoration: InputDecoration(
              hintText: l10n.t('custom_site_import_hint'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.t('custom_site_import')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final imported = CustomSiteConfig.decodeListJson(pasted);
    if (imported.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.t('custom_site_invalid_json'))));
      return;
    }

    final existingUrls = _draft.customSites.map((s) => s.searchUrlTemplate.toLowerCase()).toSet();
    final merged = [..._draft.customSites];
    var addedCount = 0;
    for (final site in imported) {
      if (existingUrls.add(site.searchUrlTemplate.toLowerCase())) {
        merged.add(site);
        addedCount++;
      }
    }
    setState(() => _draft = _draft.copyWith(customSites: merged));
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.t('custom_site_imported', {'count': '$addedCount'}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final seedrAccounts = widget.storage.seedrAccounts;

    return AlertDialog(
      backgroundColor: const Color(0xFF111C33),
      title: Text(l10n.t('settings_title')),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Sandbox rules
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

              // 2. Seedr accounts
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
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                ),
              const Divider(),

              // 3. 11 Built-in Full-Catalog Sources
              Text(
                l10n.t('settings_sources_section'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableKnaben,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableKnaben: v)),
                title: const Text('Knaben (Full catalog: 1337x, TPB, TGx, RuTracker, Nyaa...)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableApibay,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableApibay: v)),
                title: const Text('APIBay (Full catalog — full NFO)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableTorrentCsv,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableTorrentCsv: v)),
                title: const Text('TorrentCSV (Full catalog open-source JSON index)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableYts,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableYts: v)),
                title: const Text('YTS (Multi-mirror HD / 4K Movies — direct .torrent)'),
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
                title: const Text('BitSearch (Full catalog meta-index)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableNyaa,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableNyaa: v)),
                title: const Text('Nyaa (Full catalog / Anime RSS — direct .torrent)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableSubsPlease,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableSubsPlease: v)),
                title: const Text('SubsPlease (Anime JSON API — direct .torrent)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableSolidTorrents,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableSolidTorrents: v)),
                title: const Text('SolidTorrents (Full catalog multi-mirror JSON)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableLimeTorrents,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableLimeTorrents: v)),
                title: const Text('LimeTorrents (Full catalog multi-mirror RSS)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableArchiveOrg,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableArchiveOrg: v)),
                title: const Text('Internet Archive (Full catalog BitTorrent)'),
              ),
              const Divider(),

              // 4. Custom Websites Extractor (Cardigann / qBittorrent-plugin style)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    l10n.t('settings_custom_sites_section'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: _importCustomSites,
                        icon: const Icon(Icons.file_download_outlined, size: 16),
                        label: Text(l10n.t('custom_site_import'), style: const TextStyle(fontSize: 12)),
                      ),
                      if (_draft.customSites.isNotEmpty)
                        TextButton.icon(
                          onPressed: _exportCustomSites,
                          icon: const Icon(Icons.file_upload_outlined, size: 16),
                          label: Text(l10n.t('custom_site_export'), style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.t('settings_custom_sites_hint'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 8),
              ..._draft.customSites.map(
                (site) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(
                    value: site.enabled,
                    onChanged: (v) {
                      setState(() {
                        _draft = _draft.copyWith(
                          customSites: _draft.customSites
                              .map((s) => s.id == site.id ? s.copyWith(enabled: v ?? true) : s)
                              .toList(),
                        );
                      });
                    },
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          site.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (site.followDetailPages) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C4A6E),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            l10n.t('custom_site_2step_badge'),
                            style: const TextStyle(fontSize: 10, color: Color(0xFF7DD3FC)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    site.searchUrlTemplate,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.t('custom_site_test'),
                        icon: const Icon(Icons.play_arrow_outlined, size: 19),
                        onPressed: _testingCustomSite ? null : () => _testCustomSite(existing: site),
                      ),
                      IconButton(
                        tooltip: l10n.t('delete'),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          setState(() {
                            _draft = _draft.copyWith(
                              customSites:
                                  _draft.customSites.where((s) => s.id != site.id).toList(),
                            );
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              TextField(
                key: const Key('custom_site_name_field'),
                controller: _csNameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.t('custom_site_name'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('custom_site_url_field'),
                controller: _csUrlCtrl,
                decoration: InputDecoration(
                  labelText: l10n.t('custom_site_url_label'),
                  hintText: l10n.t('custom_site_url_hint'),
                  isDense: true,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _csFollowDetailPages,
                onChanged: (v) => setState(() => _csFollowDetailPages = v),
                title: Text(l10n.t('custom_site_2step'), style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  l10n.t('custom_site_2step_sub'),
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                ),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  l10n.t('custom_site_advanced_css'),
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                ),
                children: [
                  TextField(
                    controller: _csRowCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.t('custom_site_row_sel'),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _csTitleCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.t('custom_site_title_sel'),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _csLinkCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.t('custom_site_link_sel'),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _csSizeCtrl,
                          decoration: InputDecoration(
                            labelText: l10n.t('custom_site_size_sel'),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _csSeedersCtrl,
                          decoration: InputDecoration(
                            labelText: l10n.t('custom_site_seeders_sel'),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _csTestQueryCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.t('custom_site_test_query'),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _testingCustomSite ? null : () => _testCustomSite(),
                    icon: _testingCustomSite
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.science_outlined, size: 17),
                    label: Text(
                      _testingCustomSite
                          ? l10n.t('custom_site_testing')
                          : l10n.t('custom_site_test'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('add_custom_site_btn'),
                    onPressed: _addCustomSite,
                    child: Text(l10n.t('add')),
                  ),
                ],
              ),
              if (_csTestFeedback != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _csTestIsError
                        ? const Color(0xFF451A03)
                        : const Color(0xFF052E16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _csTestIsError
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF22C55E),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _csTestFeedback!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _csTestIsError
                              ? const Color(0xFFFDE68A)
                              : const Color(0xFF86EFAC),
                        ),
                      ),
                      if (_csTestPreview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        ..._csTestPreview.map(
                          (line) => Text(
                            line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFFE2E8F0)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const Divider(),

              // 5. Optional Torznab (Jackett / Prowlarr)
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
