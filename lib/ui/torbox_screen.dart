import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safetorrent/models/torbox_models.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/release_parser.dart';
import 'package:safetorrent/services/torbox_service.dart';
import 'package:url_launcher/url_launcher.dart';

class TorboxScreen extends StatefulWidget {
  const TorboxScreen({
    super.key,
    required this.storage,
    required this.refreshSignal,
    required this.onProfilesChanged,
  });

  final LocalStorageService storage;
  final int refreshSignal;
  final VoidCallback onProfilesChanged;

  @override
  State<TorboxScreen> createState() => _TorboxScreenState();
}

class _TorboxScreenState extends State<TorboxScreen> {
  late final TorboxService _torbox = TorboxService(storage: widget.storage);

  List<TorboxTorrentItem> _torrents = [];
  bool _loading = false;
  String? _error;
  Timer? _countdownTicker;
  Timer? _liveTransferTimer;
  int _lastSignal = 0;

  @override
  void initState() {
    super.initState();
    // Tick every 30s so any official cooldown_until countdown stays fresh
    _countdownTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && widget.storage.torboxProfiles.any((p) => p.isInCooldown())) {
        setState(() {});
      }
    });
    if (_torbox.hasProfile) {
      _refreshActive();
    }
  }

  @override
  void didUpdateWidget(covariant TorboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != _lastSignal) {
      _lastSignal = widget.refreshSignal;
      if (_torbox.hasProfile) {
        _refreshActive();
      }
    }
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _liveTransferTimer?.cancel();
    super.dispose();
  }

  void _syncLiveTimer() {
    final hasActive = _torrents.any((t) => t.active && !t.downloadFinished);
    if (hasActive && _liveTransferTimer == null) {
      _liveTransferTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (mounted && _torbox.hasProfile && !_loading) {
          _refreshActive(silent: true);
        }
      });
    } else if (!hasActive) {
      _liveTransferTimer?.cancel();
      _liveTransferTimer = null;
    }
  }

  Future<void> _refreshActive({bool silent = false}) async {
    final active = _torbox.activeProfile;
    if (active == null) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await _torbox.syncProfile(active);
      final updated = _torbox.activeProfile ?? active;
      final list = await _torbox.listTorrents(updated);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _torrents = list;
      });
      widget.onProfilesChanged();
      _syncLiveTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _switchProfile(TorboxProfile profile) async {
    await widget.storage.setActiveTorboxProfile(profile.id);
    widget.onProfilesChanged();
    setState(() {
      _torrents = [];
      _error = null;
    });
    await _refreshActive();
  }

  Future<void> _openAddProfileDialog() async {
    final nameCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    var busy = false;
    String? dialogErr;

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF111C33),
          title: const Text('Ajouter un profil TorBox'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ajoutez le nom du profil (ex : Moi, Sœur, Fille) et la clé API officielle disponible dans torbox.app/settings.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom du profil',
                    hintText: 'Ex : Mon compte, Sœur, Fille...',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Clé API TorBox',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openExternalUrl('https://torbox.app/settings'),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('Récupérer ma clé sur torbox.app/settings'),
                  ),
                ),
                if (dialogErr != null) ...[
                  const SizedBox(height: 6),
                  Text(dialogErr!, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12.5)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() {
                        busy = true;
                        dialogErr = null;
                      });
                      try {
                        await _torbox.addProfile(
                          label: nameCtrl.text,
                          apiKey: keyCtrl.text,
                          makeActive: true,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setLocal(() {
                          busy = false;
                          dialogErr = e.toString();
                        });
                      }
                    },
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, size: 17),
              label: const Text('Vérifier & Ajouter'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    keyCtrl.dispose();

    if (added == true && mounted) {
      widget.onProfilesChanged();
      _showSnack('Profil TorBox ajouté et vérifié !');
      await _refreshActive();
    }
  }

  Future<void> _deleteProfile(TorboxProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111C33),
        title: const Text('Retirer ce profil TorBox ?'),
        content: Text('Supprimer le profil « ${profile.label} » de SafeTorrent ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.storage.deleteTorboxProfile(profile.id);
    if (!mounted) return;
    setState(() {
      _torrents = [];
      _error = null;
    });
    widget.onProfilesChanged();
    if (_torbox.hasProfile) {
      await _refreshActive();
    }
  }

  Future<void> _promptAddMagnet() async {
    final active = _torbox.activeProfile;
    if (active == null) return;
    final ctrl = TextEditingController();
    final magnet = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111C33),
        title: Text('Ajouter un Magnet sur TorBox (${active.label})'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Lien magnet:?xt=urn:btih:...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (magnet == null || magnet.isEmpty) return;
    try {
      final msg = await _torbox.addMagnet(active, magnet);
      _showSnack('⚡ $msg');
      await _refreshActive();
    } catch (e) {
      _showSnack('$e');
    }
  }

  Future<void> _downloadItem({
    required TorboxTorrentItem torrent,
    int? fileId,
    bool zipLink = false,
    bool copyOnly = false,
  }) async {
    final active = _torbox.activeProfile;
    if (active == null) return;
    try {
      _showSnack('Génération du lien direct HTTPS TorBox...');
      final url = await _torbox.requestDownloadUrl(
        active,
        torrent.id,
        fileId: fileId,
        zipLink: zipLink,
      );
      if (!mounted) return;
      if (copyOnly) {
        await Clipboard.setData(ClipboardData(text: url));
        _showSnack('Lien direct HTTPS copié (valide 3h).');
      } else {
        await _openExternalUrl(url);
      }
    } catch (e) {
      _showSnack('Erreur téléchargement : $e');
    }
  }

  Future<void> _controlTorrent(TorboxTorrentItem torrent, String op, String label) async {
    final active = _torbox.activeProfile;
    if (active == null) return;
    if (op == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF111C33),
          title: const Text('Supprimer de TorBox ?'),
          content: Text('Voulez-vous supprimer « ${torrent.name} » de TorBox (${active.label}) ?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await _torbox.controlTorrent(active, torrent.id, op);
      _showSnack('$label effectuée.');
      await _refreshActive();
    } catch (e) {
      _showSnack('Erreur : $e');
    }
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: rawUrl));
      _showSnack('Lien copié dans le presse-papiers.');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.storage.torboxProfiles;
    final active = _torbox.activeProfile;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: profiles.isEmpty || active == null
            ? _buildEmptyOnboarding()
            : _buildDashboard(profiles, active),
      ),
    );
  }

  Widget _buildEmptyOnboarding() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bolt, color: Color(0xFF22C55E), size: 32),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connecter un ou plusieurs profils TorBox',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'Chaque membre de la famille peut enregistrer sa clé API TorBox et basculer sur son profil en 1 clic.',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _openAddProfileDialog,
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('Ajouter un profil TorBox'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openExternalUrl('https://torbox.app/settings'),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Ouvrir torbox.app/settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard(List<TorboxProfile> profiles, TorboxProfile active) {
    return RefreshIndicator(
      onRefresh: () => _refreshActive(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Multi-profile switcher card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '👥 Profils TorBox',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      TextButton.icon(
                        onPressed: _openAddProfileDialog,
                        icon: const Icon(Icons.person_add_outlined, size: 17),
                        label: const Text('Ajouter un profil'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: profiles.map((p) {
                      final isSelected = p.id == active.id;
                      final cooldown = p.remainingCooldown();
                      final subtitle = p.isPremium
                          ? '⭐ ${p.planLabel}'
                          : (cooldown > Duration.zero
                              ? '⏳ ${TorboxProfile.formatDuration(cooldown)}'
                              : 'Gratuit • Prêt');
                      return ChoiceChip(
                        selected: isSelected,
                        onSelected: (_) => _switchProfile(p),
                        avatar: Icon(
                          p.isPremium ? Icons.workspace_premium : Icons.person_outline,
                          size: 17,
                          color: p.isPremium ? const Color(0xFFFBBF24) : null,
                        ),
                        label: Text('${p.label} ($subtitle)'),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Active profile details card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        active.isPremium ? Icons.workspace_premium : Icons.bolt,
                        color: active.isPremium
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFF38BDF8),
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              active.label,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            if (active.email != null)
                              Text(
                                active.email!,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Actualiser le compte TorBox',
                        onPressed: _loading ? null : () => _refreshActive(),
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: 'Retirer ce profil',
                        onPressed: () => _deleteProfile(active),
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _badge(
                        active.isPremium
                            ? '⭐ ${active.planLabel} — Sans limite'
                            : 'Offre : ${active.planLabel}',
                        active.isPremium ? const Color(0xFF78350F) : const Color(0xFF1E293B),
                        active.isPremium ? const Color(0xFFFDE68A) : const Color(0xFFCBD5E1),
                      ),
                      if (!active.isPremium)
                        _badge(
                          active.isInCooldown()
                              ? '⏳ Cooldown officiel : ${TorboxProfile.formatDuration(active.remainingCooldown())}'
                              : '✅ Disponible',
                          active.isInCooldown()
                              ? const Color(0xFF7F1D1D)
                              : const Color(0xFF14532D),
                          active.isInCooldown()
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF86EFAC),
                        ),
                      if (active.totalDownloaded > 0)
                        _badge(
                          'Téléchargé : ${ReleaseParser.formatSize(active.totalDownloaded)}',
                          const Color(0xFF0C4A6E),
                          const Color(0xFF7DD3FC),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _promptAddMagnet,
                        icon: const Icon(Icons.add_link, size: 17),
                        label: const Text('Ajouter un Magnet'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _openExternalUrl('https://torbox.app/dashboard'),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Ouvrir TorBox Web'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          if (_error != null)
            Card(
              color: const Color(0xFF450A0A),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFFCA5A5))),
              ),
            ),

          if (_loading && _torrents.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_torrents.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucun torrent sur ce profil TorBox. Envoyez un film ou une série depuis l\'onglet Rechercher !',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            ..._torrents.map(_buildTorrentCard),
        ],
      ),
    );
  }

  Widget _buildTorrentCard(TorboxTorrentItem t) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                if (t.cached)
                  _badge('⚡ En cache', const Color(0xFF14532D), const Color(0xFF86EFAC)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: t.progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF1E293B),
              valueColor: AlwaysStoppedAnimation<Color>(
                t.downloadFinished ? const Color(0xFF22C55E) : const Color(0xFF38BDF8),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${t.progressPercent.toStringAsFixed(1)}% • ${ReleaseParser.formatSize(t.sizeBytes)}'
              '${t.downloadState.isNotEmpty ? ' • ${t.downloadState}' : ''}'
              '${t.downloadSpeed > 0 ? ' • ${ReleaseParser.formatSize(t.downloadSpeed)}/s' : ''}'
              ' • ▲ ${t.seeds} seeders',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (t.downloadFinished)
                  FilledButton.icon(
                    onPressed: () => _downloadItem(torrent: t, zipLink: true),
                    icon: const Icon(Icons.folder_zip_outlined, size: 16),
                    label: const Text('Télécharger ZIP (HTTPS)'),
                  ),
                if (t.active && !t.downloadFinished)
                  OutlinedButton.icon(
                    onPressed: () => _controlTorrent(t, 'pause', 'Mise en pause'),
                    icon: const Icon(Icons.pause, size: 16),
                    label: const Text('Pause'),
                  )
                else if (!t.downloadFinished)
                  OutlinedButton.icon(
                    onPressed: () => _controlTorrent(t, 'resume', 'Reprise'),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Reprendre'),
                  ),
                TextButton.icon(
                  onPressed: () => _controlTorrent(t, 'delete', 'Suppression'),
                  icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                  label: const Text('Supprimer', style: TextStyle(color: Color(0xFFEF4444))),
                ),
              ],
            ),
            if (t.downloadFinished && t.files.isNotEmpty) ...[
              const Divider(height: 18),
              ...t.files.take(20).map(
                    (f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            f.isVideo
                                ? Icons.movie_creation_outlined
                                : Icons.insert_drive_file_outlined,
                            size: 18,
                            color: f.isVideo ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${f.shortName} (${ReleaseParser.formatSize(f.sizeBytes)})',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Télécharger ce fichier (HTTPS)',
                            icon: const Icon(Icons.download, size: 19, color: Color(0xFF38BDF8)),
                            onPressed: () => _downloadItem(torrent: t, fileId: f.id),
                          ),
                          IconButton(
                            tooltip: 'Copier le lien direct HTTPS',
                            icon: const Icon(Icons.copy, size: 17),
                            onPressed: () =>
                                _downloadItem(torrent: t, fileId: f.id, copyOnly: true),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}
