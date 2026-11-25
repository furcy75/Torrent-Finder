import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safetorrent/models/seedr_models.dart';
import 'package:safetorrent/services/local_storage.dart';
import 'package:safetorrent/services/release_parser.dart';
import 'package:safetorrent/services/seedr_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SeedrScreen extends StatefulWidget {
  const SeedrScreen({
    super.key,
    required this.storage,
    required this.refreshSignal,
    required this.onSessionChanged,
  });

  final LocalStorageService storage;
  final int refreshSignal;
  final VoidCallback onSessionChanged;

  @override
  State<SeedrScreen> createState() => _SeedrScreenState();
}

class _SeedrScreenState extends State<SeedrScreen> {
  late final SeedrService _seedr = SeedrService(storage: widget.storage);

  // Add-account / login UI state
  bool _showAddAccountForm = false;
  bool _useDeviceFlow = true;
  final _labelCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _authBusy = false;
  String? _authError;
  SeedrDeviceCode? _pendingDeviceCode;
  Timer? _devicePollTimer;

  // Live account explorer state
  SeedrFolderContents? _contents;
  final List<(String id, String name)> _folderStack = [];
  bool _loadingFolder = false;
  String? _folderError;
  Timer? _liveTransferTimer;
  int _lastHandledSignal = 0;

  @override
  void initState() {
    super.initState();
    if (_seedr.isConnected) {
      _loadFolder();
    }
  }

  @override
  void didUpdateWidget(covariant SeedrScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != _lastHandledSignal) {
      _lastHandledSignal = widget.refreshSignal;
      if (_seedr.isConnected && !_showAddAccountForm) {
        _loadFolder(folderId: _currentFolderId);
      }
    }
  }

  @override
  void dispose() {
    _devicePollTimer?.cancel();
    _liveTransferTimer?.cancel();
    _labelCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String? get _currentFolderId => _folderStack.isEmpty ? null : _folderStack.last.$1;

  void _syncLiveTransferTimer() {
    final hasTransfers = (_contents?.torrents.isNotEmpty ?? false) &&
        _seedr.isConnected &&
        !_showAddAccountForm;
    if (hasTransfers && _liveTransferTimer == null) {
      _liveTransferTimer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (mounted && _seedr.isConnected && !_loadingFolder && !_showAddAccountForm) {
          _loadFolder(folderId: _currentFolderId, silent: true);
        }
      });
    } else if (!hasTransfers) {
      _liveTransferTimer?.cancel();
      _liveTransferTimer = null;
    }
  }

  Future<void> _switchAccount(String accountId) async {
    if (widget.storage.activeSeedrAccount?.id == accountId && !_showAddAccountForm) {
      await _loadFolder(folderId: _currentFolderId);
      return;
    }
    _devicePollTimer?.cancel();
    await widget.storage.setActiveSeedrAccount(accountId);
    if (!mounted) return;
    setState(() {
      _showAddAccountForm = false;
      _pendingDeviceCode = null;
      _authError = null;
      _contents = null;
      _folderStack.clear();
      _folderError = null;
    });
    widget.onSessionChanged();
    await _loadFolder();
  }

  // -------------------------------------------------------------------
  // Auth Mode 1: Device Code Flow
  // -------------------------------------------------------------------
  Future<void> _startDeviceFlow() async {
    _devicePollTimer?.cancel();
    setState(() {
      _authBusy = true;
      _authError = null;
      _pendingDeviceCode = null;
    });
    try {
      final code = await _seedr.requestDeviceCode();
      if (!mounted) return;
      setState(() {
        _authBusy = false;
        _pendingDeviceCode = code;
      });
      final interval = Duration(seconds: code.intervalSeconds.clamp(4, 15));
      _devicePollTimer = Timer.periodic(interval, (_) => _checkDeviceApproval(silent: true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authBusy = false;
        _authError = e.toString();
      });
    }
  }

  Future<void> _checkDeviceApproval({bool silent = false}) async {
    final pending = _pendingDeviceCode;
    if (pending == null) return;
    try {
      final session = await _seedr.pollDeviceAuthorization(
        pending.deviceCode,
        label: _labelCtrl.text,
      );
      if (!mounted) return;
      if (session != null) {
        _devicePollTimer?.cancel();
        _devicePollTimer = null;
        _labelCtrl.clear();
        setState(() {
          _pendingDeviceCode = null;
          _authError = null;
          _showAddAccountForm = false;
          _contents = null;
          _folderStack.clear();
        });
        widget.onSessionChanged();
        _showSnack('Compte Seedr « ${session.displayName} » connecté !');
        await _loadFolder();
      } else if (!silent) {
        _showSnack('En attente de validation sur seedr.cc/devices...');
      }
    } catch (e) {
      _devicePollTimer?.cancel();
      _devicePollTimer = null;
      if (!mounted) return;
      setState(() {
        _pendingDeviceCode = null;
        _authError = e.toString();
      });
    }
  }

  // -------------------------------------------------------------------
  // Auth Mode 2: Email + Password Flow
  // -------------------------------------------------------------------
  Future<void> _loginWithPassword() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _authError = 'Veuillez saisir votre email et votre mot de passe Seedr.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _authBusy = true;
      _authError = null;
    });
    try {
      final session = await _seedr.loginWithPassword(
        email: email,
        password: pass,
        label: _labelCtrl.text,
      );
      _labelCtrl.clear();
      _emailCtrl.clear();
      _passCtrl.clear();
      if (!mounted) return;
      setState(() {
        _authBusy = false;
        _showAddAccountForm = false;
        _contents = null;
        _folderStack.clear();
      });
      widget.onSessionChanged();
      _showSnack('Compte Seedr « ${session.displayName} » connecté !');
      await _loadFolder();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authBusy = false;
        _authError = e.toString();
      });
    }
  }

  Future<void> _promptRenameAccount(SeedrSession account) async {
    final ctrl = TextEditingController(text: account.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111C33),
        title: const Text('Renommer ce profil Seedr'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom du profil (ex : Moi, Sœur, Fille)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName == null || newName.isEmpty) return;
    await widget.storage.renameSeedrAccount(account.id, newName);
    if (!mounted) return;
    setState(() {});
    widget.onSessionChanged();
  }

  Future<void> _disconnectActiveAccount() async {
    final active = _seedr.activeAccount;
    if (active == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111C33),
        title: const Text('Déconnecter ce compte Seedr ?'),
        content: Text(
          'Voulez-vous retirer le profil « ${active.displayName} » de cet appareil ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _liveTransferTimer?.cancel();
    _liveTransferTimer = null;
    await _seedr.disconnectAccount(active.id);
    if (!mounted) return;
    setState(() {
      _contents = null;
      _folderStack.clear();
      _folderError = null;
      _showAddAccountForm = false;
    });
    widget.onSessionChanged();
    _showSnack('Compte « ${active.displayName} » déconnecté.');
    if (_seedr.isConnected) {
      await _loadFolder();
    }
  }

  // -------------------------------------------------------------------
  // Live Seedr Folder / Transfer / Download Operations
  // -------------------------------------------------------------------
  Future<void> _loadFolder({String? folderId, bool silent = false}) async {
    final active = _seedr.activeAccount;
    if (active == null) return;
    if (!silent) {
      setState(() {
        _loadingFolder = true;
        _folderError = null;
      });
    }
    try {
      final data = await _seedr.listContents(account: active, folderId: folderId);
      if (!mounted) return;
      setState(() {
        _loadingFolder = false;
        _contents = data;
      });
      _syncLiveTransferTimer();
    } on SeedrApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFolder = false;
        _folderError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFolder = false;
        _folderError = 'Erreur réseau Seedr : $e';
      });
    }
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      await Clipboard.setData(ClipboardData(text: rawUrl));
      _showSnack('Lien copié dans le presse-papiers (impossible d\'ouvrir le navigateur).');
    }
  }

  Future<void> _downloadFile(SeedrFileEntry file, {bool copyOnly = false}) async {
    try {
      _showSnack('Récupération du lien direct HTTPS...');
      final url = await _seedr.fetchFileDownloadUrl(file.folderFileId);
      if (!mounted) return;
      if (copyOnly) {
        await Clipboard.setData(ClipboardData(text: url));
        _showSnack('Lien direct HTTPS copié (prêt pour VLC ou gestionnaire de téléchargement).');
      } else {
        await _openExternalUrl(url);
      }
    } catch (e) {
      _showSnack('Erreur : $e');
    }
  }

  Future<void> _downloadFolderZip(SeedrFolderEntry folder) async {
    try {
      _showSnack('Préparation de l\'archive ZIP Seedr...');
      final url = await _seedr.createFolderZipUrl(folder.id);
      if (!mounted) return;
      await _openExternalUrl(url);
    } catch (e) {
      _showSnack('Erreur ZIP : $e');
    }
  }

  Future<void> _confirmAndDelete({
    required String type,
    required String id,
    required String label,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111C33),
        title: const Text('Supprimer de Seedr ?'),
        content: Text('Voulez-vous supprimer « $label » de cet espace Seedr ?'),
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
    try {
      await _seedr.deleteItem(type: type, id: id);
      _showSnack('« $label » supprimé de Seedr.');
      await _loadFolder(folderId: _currentFolderId);
    } catch (e) {
      _showSnack('Erreur suppression : $e');
    }
  }

  Future<void> _promptAddManualMagnet() async {
    final active = _seedr.activeAccount;
    if (active == null) return;
    final ctrl = TextEditingController();
    final magnet = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111C33),
        title: Text('Ajouter un Magnet sur « ${active.displayName} »'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Lien magnet:?xt=urn:btih:...',
          ),
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
      final msg = await _seedr.addMagnet(magnet, account: active);
      _showSnack('☁️ ${active.displayName} : $msg');
      await _loadFolder(folderId: _currentFolderId);
    } catch (e) {
      _showSnack('$e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final showLogin = !_seedr.isConnected || _showAddAccountForm;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: showLogin ? _buildLoginView() : _buildDashboard(),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Family Accounts Switcher Card
  // -------------------------------------------------------------------
  Widget _buildFamilyAccountsBar() {
    final accounts = _seedr.accounts;
    final activeId = _seedr.activeAccount?.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.group_outlined, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 6),
                Text(
                  'Comptes Seedr famille (${accounts.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    _devicePollTimer?.cancel();
                    setState(() {
                      _showAddAccountForm = true;
                      _pendingDeviceCode = null;
                      _authError = null;
                    });
                  },
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                  label: const Text('Ajouter un compte'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: accounts.map((acc) {
                final selected = acc.id == activeId && !_showAddAccountForm;
                final free = acc.lastSpaceFree;
                final suffix = free != null ? ' • ${ReleaseParser.formatSize(free)} libre' : '';
                return ChoiceChip(
                  selected: selected,
                  onSelected: (_) => _switchAccount(acc.id),
                  avatar: Icon(
                    selected ? Icons.cloud_done : Icons.cloud_outlined,
                    size: 16,
                    color: selected ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                  ),
                  label: Text('${acc.displayName}$suffix'),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Login View (Add First or Additional Family Account)
  // -------------------------------------------------------------------
  Widget _buildLoginView() {
    final pending = _pendingDeviceCode;
    final hasExistingAccounts = _seedr.isConnected;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hasExistingAccounts) _buildFamilyAccountsBar(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_outlined, color: Color(0xFF38BDF8), size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasExistingAccounts
                                ? 'Ajouter un compte Seedr famille'
                                : 'Connexion à Seedr.cc',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const Text(
                            'Connectez un ou plusieurs comptes familiaux et choisissez celui à utiliser selon le quota disponible.',
                            style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                    if (hasExistingAccounts)
                      TextButton.icon(
                        onPressed: () {
                          _devicePollTimer?.cancel();
                          setState(() {
                            _showAddAccountForm = false;
                            _pendingDeviceCode = null;
                            _authError = null;
                          });
                        },
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: const Text('Retour'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom du profil (ex : Moi, Sœur, Fille)',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      selected: _useDeviceFlow,
                      onSelected: (_) => setState(() {
                        _useDeviceFlow = true;
                        _authError = null;
                      }),
                      avatar: const Icon(Icons.qr_code_2, size: 17),
                      label: const Text('Code Appareil (Recommandé)'),
                    ),
                    ChoiceChip(
                      selected: !_useDeviceFlow,
                      onSelected: (_) => setState(() {
                        _useDeviceFlow = false;
                        _authError = null;
                      }),
                      avatar: const Icon(Icons.mail_outline, size: 17),
                      label: const Text('Email & Mot de passe'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_useDeviceFlow) ...[
                  const Text(
                    'Méthode la plus sûre : aucun mot de passe n\'est saisi dans l\'application. Un code court vous permet d\'autoriser SafeTorrent depuis seedr.cc/devices.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 14),
                  if (pending == null)
                    FilledButton.icon(
                      onPressed: _authBusy ? null : _startDeviceFlow,
                      icon: _authBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.key_outlined),
                      label: const Text('Générer un code de connexion Seedr'),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1120),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF38BDF8)),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Saisissez ce code sur seedr.cc/devices :',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            pending.userCode,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(text: pending.userCode));
                                  _showSnack('Code « ${pending.userCode} » copié.');
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copier le code'),
                              ),
                              FilledButton.icon(
                                onPressed: () => _openExternalUrl(pending.verificationUrl),
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text('Ouvrir seedr.cc/devices'),
                              ),
                              TextButton.icon(
                                onPressed: () => _checkDeviceApproval(silent: false),
                                icon: const Icon(Icons.check_circle_outline, size: 16),
                                label: const Text('Vérifier maintenant'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Vérification automatique en cours...',
                                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ] else ...[
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Seedr',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscurePass,
                    onSubmitted: (_) => _loginWithPassword(),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe Seedr',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscurePass = !_obscurePass),
                        icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Votre mot de passe n\'est jamais enregistré : seul le jeton OAuth est conservé localement sur votre appareil.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _authBusy ? null : _loginWithPassword,
                    icon: _authBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text('Se connecter à Seedr'),
                  ),
                ],
                if (_authError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF450A0A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _authError!,
                      style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Connected Live Dashboard
  // -------------------------------------------------------------------
  Widget _buildDashboard() {
    final s = _seedr.activeAccount!;
    final c = _contents;
    final ratio = c?.usedRatio ?? s.usedRatio;
    final spaceUsed = c?.spaceUsed ?? s.lastSpaceUsed ?? 0;
    final spaceMax = c?.spaceMax ?? s.lastSpaceMax ?? 0;
    final barColor = ratio > 0.9
        ? const Color(0xFFEF4444)
        : ratio > 0.75
            ? const Color(0xFFF59E0B)
            : const Color(0xFF22C55E);

    return RefreshIndicator(
      onRefresh: () => _loadFolder(folderId: _currentFolderId),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildFamilyAccountsBar(),

          // Active Account & Quota Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_done_outlined, color: Color(0xFF22C55E), size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            Text(
                              [
                                if (s.username != null && s.username != s.displayName) s.username!,
                                if (s.packageName != null) 'Offre : ${s.packageName}',
                                s.authMode == 'device' ? 'Code Appareil' : 'OAuth Email',
                              ].join(' • '),
                              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Renommer ce profil',
                        onPressed: () => _promptRenameAccount(s),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Actualiser Seedr',
                        onPressed:
                            _loadingFolder ? null : () => _loadFolder(folderId: _currentFolderId),
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: 'Déconnecter ce compte',
                        onPressed: _disconnectActiveAccount,
                        icon: const Icon(Icons.logout, color: Color(0xFFEF4444)),
                      ),
                    ],
                  ),
                  if (spaceMax > 0) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Espace utilisé : ${ReleaseParser.formatSize(spaceUsed)} / ${ReleaseParser.formatSize(spaceMax)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Libre : ${ReleaseParser.formatSize((spaceMax - spaceUsed).clamp(0, spaceMax))}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF86EFAC)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        backgroundColor: const Color(0xFF1E293B),
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _promptAddManualMagnet,
                        icon: const Icon(Icons.add_link, size: 17),
                        label: const Text('Ajouter un Magnet'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _openExternalUrl('https://www.seedr.cc/files'),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Ouvrir Seedr Web'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          if (_folderError != null)
            Card(
              color: const Color(0xFF450A0A),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_folderError!, style: const TextStyle(color: Color(0xFFFCA5A5))),
              ),
            ),

          if (_loadingFolder && c == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (c != null) ...[
            // Active transfers section
            if (c.torrents.isNotEmpty) ...[
              const Text(
                '⏳ Téléchargements en cours sur Seedr (actualisation auto)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
              const SizedBox(height: 8),
              ...c.torrents.map(
                (t) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.name,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Annuler ce transfert',
                              icon: const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444)),
                              onPressed: () => _confirmAndDelete(
                                type: 'torrent',
                                id: t.id,
                                label: t.name,
                              ),
                            ),
                          ],
                        ),
                        LinearProgressIndicator(
                          value: t.progress / 100.0,
                          minHeight: 6,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${t.progress.toStringAsFixed(1)}% • ${ReleaseParser.formatSize(t.sizeBytes)} • '
                          '${ReleaseParser.formatSize(t.downloadRate)}/s • ▲ ${t.seeders} seeders',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Folder navigation breadcrumb
            Row(
              children: [
                if (_folderStack.isNotEmpty)
                  IconButton(
                    tooltip: 'Dossier parent',
                    onPressed: () {
                      setState(() => _folderStack.removeLast());
                      _loadFolder(folderId: _currentFolderId);
                    },
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Text(
                    _folderStack.isEmpty
                        ? '📁 Fichiers Seedr (${s.displayName})'
                        : '📁 ${_folderStack.map((e) => e.$2).join(' / ')}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (c.folders.isEmpty && c.files.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Ce dossier Seedr est vide. Envoyez un film ou une série depuis l\'onglet Rechercher !',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ),
              ),

            // Folders list
            ...c.folders.map(
              (f) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    f.playVideo ? Icons.video_library_outlined : Icons.folder_outlined,
                    color: const Color(0xFF38BDF8),
                    size: 28,
                  ),
                  title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(ReleaseParser.formatSize(f.sizeBytes)),
                  onTap: () {
                    setState(() => _folderStack.add((f.id, f.name)));
                    _loadFolder(folderId: f.id);
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Télécharger le dossier en ZIP',
                        icon: const Icon(Icons.folder_zip_outlined),
                        onPressed: () => _downloadFolderZip(f),
                      ),
                      IconButton(
                        tooltip: 'Supprimer le dossier',
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                        onPressed: () => _confirmAndDelete(
                          type: 'folder',
                          id: f.id,
                          label: f.name,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Files list
            ...c.files.map(
              (f) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            f.playVideo
                                ? Icons.movie_creation_outlined
                                : Icons.insert_drive_file_outlined,
                            color: f.playVideo ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(
                                  ReleaseParser.formatSize(f.sizeBytes),
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _downloadFile(f, copyOnly: false),
                            icon: const Icon(Icons.download, size: 16),
                            label: const Text('Télécharger (HTTPS)'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _downloadFile(f, copyOnly: true),
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('Copier lien direct'),
                          ),
                          TextButton.icon(
                            onPressed: () => _confirmAndDelete(
                              type: 'file',
                              id: f.folderFileId,
                              label: f.name,
                            ),
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Color(0xFFEF4444),
                            ),
                            label: const Text(
                              'Supprimer',
                              style: TextStyle(color: Color(0xFFEF4444)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
