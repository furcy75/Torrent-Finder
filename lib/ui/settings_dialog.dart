import 'package:flutter/material.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/services/local_storage.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.storage});

  final LocalStorageService storage;

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
    return AlertDialog(
      backgroundColor: const Color(0xFF111C33),
      title: const Text('⚙️ Réglages sécurité & sources'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🛡️ Règles du Bac à Sable', style: TextStyle(fontWeight: FontWeight.w700)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.strictVideoOnly,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(strictVideoOnly: v)),
                title: const Text('Mode vidéo strict'),
                subtitle: const Text('Bloque tout torrent sans fichier vidéo (.mkv, .mp4...)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.blockArchives,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(blockArchives: v)),
                title: const Text('Bloquer les archives (.zip, .rar, .7z)'),
                subtitle: const Text('Protège contre les faux films piégés par mot de passe'),
              ),
              const Divider(),
              const Text(
                '🔎 Sources intégrées (APIs JSON sans pub / sans JS)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableYts,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableYts: v)),
                title: const Text('YTS (HD / 4K — .torrent directs)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableApibay,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableApibay: v)),
                title: const Text('APIBay (JSON pur — NFO détaillé)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableKnaben,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableKnaben: v)),
                title: const Text('Knaben (Multi-trackers : 1337x, TGx, TPB, RuTracker...)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableTorrentCsv,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableTorrentCsv: v)),
                title: const Text('TorrentCSV (Base open-source JSON)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableSolidTorrents,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableSolidTorrents: v)),
                title: const Text('SolidTorrents (API JSON vidéo)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableArchiveOrg,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableArchiveOrg: v)),
                title: const Text('Internet Archive (Classiques & domaine public)'),
              ),
              const Divider(),
              const Text(
                '🔌 Torznab optionnel (Jackett / Prowlarr)',
                style: TextStyle(fontWeight: FontWeight.w700),
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
                decoration: const InputDecoration(labelText: 'Nom (ex : Jackett FR)', isDense: true),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _tzUrlCtrl,
                decoration:
                    const InputDecoration(labelText: 'URL Torznab (http/https)', isDense: true),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tzKeyCtrl,
                      decoration: const InputDecoration(labelText: 'Clé API', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _addTorznab, child: const Text('Ajouter')),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () async {
            await widget.storage.updateSettings(_draft);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
