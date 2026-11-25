import 'package:flutter/material.dart';
import 'package:safetorrent/models/app_settings.dart';
import 'package:safetorrent/models/torbox_models.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/torbox_service.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.storage});

  final LocalStorageService storage;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late AppSettings _draft;
  late final TorboxService _torbox = TorboxService(storage: widget.storage);

  final _tzNameCtrl = TextEditingController();
  final _tzUrlCtrl = TextEditingController();
  final _tzKeyCtrl = TextEditingController();

  final _tbLabelCtrl = TextEditingController();
  final _tbKeyCtrl = TextEditingController();
  bool _addingTorbox = false;
  String? _torboxMsg;

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
    _tbLabelCtrl.dispose();
    _tbKeyCtrl.dispose();
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

  Future<void> _addTorboxProfile() async {
    final key = _tbKeyCtrl.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _addingTorbox = true;
      _torboxMsg = null;
    });
    try {
      final p = await _torbox.addProfile(
        label: _tbLabelCtrl.text,
        apiKey: key,
        makeActive: true,
      );
      if (!mounted) return;
      setState(() {
        _addingTorbox = false;
        _tbLabelCtrl.clear();
        _tbKeyCtrl.clear();
        _torboxMsg = '✅ Profil « ${p.label} » ajouté (${p.planLabel}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _addingTorbox = false;
        _torboxMsg = '⛔ $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tbProfiles = widget.storage.torboxProfiles;

    return AlertDialog(
      backgroundColor: const Color(0xFF111C33),
      title: const Text('⚙️ Réglages sécurité, Cloud & sources'),
      content: SizedBox(
        width: 560,
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
                subtitle: const Text('Protège contre les faux fichiers piégés par mot de passe'),
              ),
              const Divider(),
              const Text(
                '⚡ Profils TorBox (clés API locales)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (tbProfiles.isEmpty)
                const Text(
                  'Aucun profil TorBox configuré.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                )
              else
                ...tbProfiles.map(
                  (p) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      p.isPremium ? Icons.workspace_premium : Icons.person_outline,
                      color: p.isPremium ? const Color(0xFFFBBF24) : const Color(0xFF94A3B8),
                    ),
                    title: Text('${p.label} — ${p.planLabel}'),
                    subtitle: Text(
                      p.isPremium
                          ? 'Sans limite${p.email != null ? ' • ${p.email}' : ''}'
                          : (p.isInCooldown()
                              ? '⏳ Cooldown : ${TorboxProfile.formatDuration(p.remainingCooldown())}'
                              : 'Disponible${p.email != null ? ' • ${p.email}' : ''}'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        await widget.storage.deleteTorboxProfile(p.id);
                        setState(() {});
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tbLabelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Profil (ex : Moi, Sœur)',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _tbKeyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Clé API TorBox',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: _addingTorbox ? null : _addTorboxProfile,
                    child: _addingTorbox
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Ajouter'),
                  ),
                ],
              ),
              if (_torboxMsg != null) ...[
                const SizedBox(height: 6),
                Text(_torboxMsg!, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              ],
              const Divider(),
              const Text(
                '🔎 10 sources intégrées (sans pub / sans navigateur JS)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableYts,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableYts: v)),
                title: const Text('YTS (Films HD / 4K — .torrent directs)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableApibay,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableApibay: v)),
                title: const Text('APIBay (Films & Séries — NFO détaillé)'),
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
                value: _draft.enableEztv,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableEztv: v)),
                title: const Text('EZTV (Spécialiste Séries TV — .torrent directs)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableBitSearch,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableBitSearch: v)),
                title: const Text('BitSearch (Méta-index Films & Séries)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableNyaa,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableNyaa: v)),
                title: const Text('Nyaa (RSS Anime & Animation — .torrent directs)'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.enableLimeTorrents,
                onChanged: (v) => setState(() => _draft = _draft.copyWith(enableLimeTorrents: v)),
                title: const Text('LimeTorrents (RSS Films & Séries — .torrent directs)'),
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
