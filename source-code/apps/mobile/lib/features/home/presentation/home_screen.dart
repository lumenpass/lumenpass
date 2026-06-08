import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/routes.dart';
import '../../../core/repository/database_save_sync.dart';
import '../../../core/repository/providers.dart';
import '../../../core/ui/app_snack_bar.dart';
import '../../../core/ui/floating_glass_search_bar.dart';
import '../../unlock/application/database_registry.dart';
import '../../autofill/presentation/autofill_reminder_sheet.dart';
import '../../settings/application/vault_security_provider.dart';
import '../../startup/presentation/startup_router.dart';
import '../../unlock/presentation/unlock_vault_screen.dart';
import '../../vault/application/vault_entries_providers.dart';
import '../../vault/application/vault_items_list_providers.dart';
import '../../vault/presentation/vault_category_filter_dropdown.dart';
import '../../vault/presentation/vault_create_item.dart';
import '../../vault/presentation/vault_create_item_models.dart';
import '../../vault/presentation/vault_entry_avatar.dart';
import '../../vault/presentation/vault_entry_context_menu.dart';
import '../../vault/presentation/vault_entry_list_tile.dart';
import '../../vault/presentation/vault_item_details_modal.dart';
import '../../vault/presentation/vault_items_tab.dart';
import '../../vault/presentation/vault_search_floating_toolbar.dart';
import '../../vault/presentation/vault_toast.dart';
import '../application/home_vault_providers.dart';
import '../application/mobile_home_tab_provider.dart';
import 'password_generator_modal.dart';
import 'profile_tab.dart';
import 'vault_settings_modal.dart';

const _homeBackground = Color(0xFFF4F9FA);
const _homeSurface = Colors.white;
const _homeInk = Color(0xFF0A3B48);
const _homeText = Color(0xFF163640);
const _homeMuted = Color(0xFF6B858D);
const _homeBorder = Color(0xFFE3EAF0);

bool _entryIsLoginOrSecureNote(KdbxEntry entry) {
  final t = classifyVaultItemType(entry);
  return t == VaultItemType.login || t == VaultItemType.secureNote;
}

void _showUnlockForLockedVault(
  BuildContext context,
  DatabaseRecord lockedRecord,
) {
  final navigator = Navigator.of(context);
  navigator.pushNamedAndRemoveUntil(Routes.vaults, (route) => false);
  navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => UnlockVaultScreen(record: lockedRecord),
    ),
  );
}

Future<void> _confirmLockVault(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lock vault?',
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF0B1F26),
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You will need your master password to open this vault again.',
              style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF243047),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _homeInk,
                      side: const BorderSide(color: Color(0xFFD1DEE5)),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: _homeInk,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Lock',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  if (ok != true || !context.mounted) return;

  // Capture the record BEFORE tearing down providers.
  final lockedRecord = ref.read(homeVaultRecordProvider);

  ref.read(kdbxRepositoryProvider).closeDatabase();
  ref.read(activeDatabaseProvider.notifier).state = null;
  ref.read(cachedMasterPasswordProvider.notifier).state = null;
  ref.read(vaultSearchUiStateProvider.notifier).clear();
  ref.read(vaultSelectedGroupProvider.notifier).state = kCategoryFilterAll;
  ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state = null;

  if (!context.mounted) return;

  if (lockedRecord != null) {
    _showUnlockForLockedVault(context, lockedRecord);
    return;
  }

  // No matching registry record (shouldn't happen in practice) — fall back
  // to the vault picker so the user has a way forward.
  ref.read(mobileHomeTabProvider.notifier).state = MobileHomeTab.home;
  Navigator.of(
    context,
  ).pushNamedAndRemoveUntil(Routes.vaults, (route) => false);
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  DateTime? _unlockTime;
  Timer? _autoLockTimer;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _unlockTime = DateTime.now();

    // Apply pending default-tab from startup router + nudge AutoFill setup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = ref.read(activeHomeTabAfterUnlockProvider);
      if (pending != null) {
        ref.read(mobileHomeTabProvider.notifier).state = pending;
        ref.read(activeHomeTabAfterUnlockProvider.notifier).state = null;
      }
      _promptAutoFillReminder();
    });

    _lifecycleListener = AppLifecycleListener(onResume: _resetAutoLockTimer);

    _resetAutoLockTimer();
  }

  /// Surfaces the "Turn On AutoFill" sheet right after the vault opens if
  /// the provider isn't enabled yet. Delayed by a frame so the HomeScreen
  /// has time to paint before the modal slides in — avoids flashing the
  /// sheet on top of an empty scaffold.
  void _promptAutoFillReminder() {
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      // ignore: discarded_futures
      maybeShowAutoFillReminder(context, ref);
    });
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _resetAutoLockTimer() {
    _autoLockTimer?.cancel();
    final minutes = ref.read(vaultSecuritySettingsProvider).autoLock.minutes;
    if (minutes == null) return; // "Never"

    final lockAt = (_unlockTime ?? DateTime.now()).add(
      Duration(minutes: minutes),
    );
    final remaining = lockAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _doAutoLock();
      return;
    }
    _autoLockTimer = Timer(remaining, _doAutoLock);
  }

  void _doAutoLock() {
    if (!mounted) return;
    final lockedRecord = ref.read(homeVaultRecordProvider);
    ref.read(kdbxRepositoryProvider).closeDatabase();
    ref.read(activeDatabaseProvider.notifier).state = null;
    ref.read(cachedMasterPasswordProvider.notifier).state = null;
    ref.read(vaultSearchUiStateProvider.notifier).clear();
    ref.read(vaultSelectedGroupProvider.notifier).state = kCategoryFilterAll;
    ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state = null;

    if (lockedRecord != null) {
      _showUnlockForLockedVault(context, lockedRecord);
      return;
    }

    // Fallback only when the registry lost track of the active vault.
    ref.read(mobileHomeTabProvider.notifier).state = MobileHomeTab.home;
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(Routes.vaults, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    // Re-arm timer when auto-lock setting changes.
    ref.listen(
      vaultSecuritySettingsProvider.select((s) => s.autoLock),
      (previous, next) => _resetAutoLockTimer(),
    );

    ref.listen<bool>(vaultItemsIsDeletingProvider, (previous, next) {
      if (previous == true && next == false && mounted) {
        showVaultFloatingToast(context, 'Entry deleted');
      }
    });

    // When the vault is re-unlocked (database re-opened) after being locked,
    // reset the auto-lock timer so the next lock is scheduled from now.
    ref.listen<dynamic>(activeDatabaseProvider, (previous, next) {
      if (previous == null && next != null) {
        _unlockTime = DateTime.now();
        _resetAutoLockTimer();
        _promptAutoFillReminder();
      }
    });

    final tab = ref.watch(mobileHomeTabProvider);
    final isDeleting = ref.watch(vaultItemsIsDeletingProvider);

    return Scaffold(
      backgroundColor: _homeBackground,
      body: SafeArea(
        top: tab != MobileHomeTab.profile,
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                if (tab != MobileHomeTab.profile)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(10, 14, 10, 0),
                    child: _TopBar(),
                  ),
                Expanded(
                  child: switch (tab) {
                    MobileHomeTab.home => Stack(
                      children: [
                        ListView(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 96),
                          children: const [
                            VaultCategorySearchRow(),
                            SizedBox(height: 14),
                            _LastUsedSection(),
                            SizedBox(height: 14),
                            _QuickAccessSection(),
                            SizedBox(height: 14),
                            _TagsSection(),
                          ],
                        ),
                        Positioned(
                          left: 20,
                          right: 20,
                          bottom: 12,
                          child: VaultSearchFloatingToolbar(
                            hintText: 'Search items',
                            onAdd: () => showAddNewItemOverlay(context),
                            addSemanticLabel: 'Create item',
                          ),
                        ),
                      ],
                    ),
                    MobileHomeTab.items => const VaultItemsTab(),
                    MobileHomeTab.totp => const _TotpTab(),
                    MobileHomeTab.profile => const ProfileTab(),
                  },
                ),
                const _BottomNavBar(),
              ],
            ),
            if (isDeleting)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x55000000),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _AddTotpStep { input, preview, target }

enum _TotpSaveMode { existingItem, newItem }

void showAddTotpOverlay(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (ctx, animation, secondaryAnimation) =>
          _AddTotpOverlay(onClose: () => Navigator.of(ctx).pop()),
    ),
  );
}

class _AddTotpOverlay extends ConsumerStatefulWidget {
  const _AddTotpOverlay({required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<_AddTotpOverlay> createState() => _AddTotpOverlayState();
}

class _AddTotpOverlayState extends ConsumerState<_AddTotpOverlay> {
  static const TOTPService _totpService = TOTPService();

  _AddTotpStep _step = _AddTotpStep.input;
  final TextEditingController _manualCtrl = TextEditingController();
  final TextEditingController _itemSearchCtrl = TextEditingController();
  Timer? _timer;
  DateTime _now = DateTime.now();
  String? _otpauthUrl;
  String? _error;
  String _itemQuery = '';
  String? _selectedEntryUuid;
  _TotpSaveMode _saveMode = _TotpSaveMode.existingItem;
  bool _isLaunchingScanner = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _timer?.cancel();
    _manualCtrl.dispose();
    _itemSearchCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  String? _normalizeOtpAuth(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri?.scheme == 'otpauth') {
      return trimmed;
    }
    final clean = trimmed.replaceAll(' ', '').toUpperCase();
    if (RegExp(r'^[A-Z2-7=]{8,}$').hasMatch(clean)) {
      return 'otpauth://totp/Account?secret=$clean&issuer=Added manually';
    }
    return null;
  }

  ({String issuer, String account}) _parseOtpInfo(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return (issuer: '', account: '');
    }
    final path = Uri.decodeComponent(uri.path.replaceFirst('/', '')).trim();
    String issuer = uri.queryParameters['issuer']?.trim() ?? '';
    String account = path;
    if (path.contains(':')) {
      final parts = path.split(':');
      if (issuer.isEmpty) {
        issuer = parts.first.trim();
      }
      account = parts.sublist(1).join(':').trim();
    }
    if (issuer.isEmpty) {
      issuer = account;
    }
    if (account == issuer) {
      account = '';
    }
    return (issuer: issuer, account: account);
  }

  void _goToPreviewFromInput(String rawInput) {
    final normalized = _normalizeOtpAuth(rawInput);
    if (normalized == null) {
      setState(
        () => _error = 'Enter a valid otpauth:// URL or Base32 TOTP secret.',
      );
      return;
    }
    setState(() {
      _otpauthUrl = normalized;
      _error = null;
      _step = _AddTotpStep.preview;
    });
    _startTimer();
  }

  void _goToPreview() => _goToPreviewFromInput(_manualCtrl.text);

  Future<void> _scanWithCamera() async {
    if (_isLaunchingScanner || _isSaving) return;
    setState(() {
      _isLaunchingScanner = true;
      _error = null;
    });
    final scanned = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TotpCameraScannerSheet(),
    );
    if (!mounted) return;
    setState(() => _isLaunchingScanner = false);
    if (scanned == null || scanned.trim().isEmpty) return;
    _manualCtrl.text = scanned.trim();
    _goToPreviewFromInput(scanned);
  }

  void _goToTarget() {
    final entries = _sortedEntries(
      ref
          .read(vaultVisibleEntriesProvider)
          .where(_entryIsLoginOrSecureNote)
          .toList(),
    );
    setState(() {
      _step = _AddTotpStep.target;
      if (entries.isEmpty) {
        _saveMode = _TotpSaveMode.newItem;
        _selectedEntryUuid = null;
      } else {
        _saveMode = _TotpSaveMode.existingItem;
        _selectedEntryUuid = null;
      }
    });
  }

  bool _isOtpFieldKey(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized == 'otp' ||
        normalized == 'otpauth' ||
        normalized == 'otp auth' ||
        normalized.contains('otpauth') ||
        normalized.contains('otp auth');
  }

  String _preferredOtpFieldKey(KdbxEntry entry) {
    for (final field in entry.fields) {
      if (_isOtpFieldKey(field.key)) return field.key;
    }
    return 'otp';
  }

  List<KdbxEntry> _sortedEntries(List<KdbxEntry> entries) {
    final copy = List<KdbxEntry>.of(entries);
    copy.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return copy;
  }

  List<KdbxEntry> _filterEntries(List<KdbxEntry> entries, String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) return entries;
    return entries
        .where((entry) {
          final haystack = [
            entry.title,
            entry.username ?? '',
            entry.url ?? '',
            entry.notes ?? '',
            ...entry.tags,
          ].join(' ').toLowerCase();
          return terms.every(haystack.contains);
        })
        .toList(growable: false);
  }

  Future<void> _saveToExistingItem({
    required KdbxEntry entry,
    required String otpAuthUrl,
  }) async {
    final repository = ref.read(kdbxRepositoryProvider);
    final preserved = <EntryField>[
      for (final field in entry.fields)
        if (!_isOtpFieldKey(field.key)) field,
    ];
    preserved.add(
      EntryField(
        key: _preferredOtpFieldKey(entry),
        value: otpAuthUrl,
        isProtected: true,
        isStandard: true,
      ),
    );
    await repository.updateEntry(
      entryUuid: entry.uuid,
      fields: preserved,
      notes: entry.notes,
      tags: List<String>.unmodifiable(entry.tags),
    );
  }

  Future<void> _createNewItemWithTotp({required String otpAuthUrl}) async {
    final repository = ref.read(kdbxRepositoryProvider);
    final categories = ref.read(vaultSidebarCategoriesProvider);
    final selectedGroupUuid = ref.read(vaultSelectedGroupProvider);
    final targetGroupUuid = resolveEffectiveCategoryUuid(
      categories: categories,
      rootGroupUuid: repository.rootGroupUuid,
      selectedGroupUuid: selectedGroupUuid,
    );
    if (targetGroupUuid == null || targetGroupUuid.isEmpty) {
      throw const VaultStateException('Select a category before saving');
    }

    final info = _parseOtpInfo(otpAuthUrl);
    final title = info.issuer.isNotEmpty
        ? info.issuer
        : (info.account.isNotEmpty ? info.account : 'Authenticator');
    final fields = <EntryField>[
      EntryField(key: AppKdbxFieldKeys.title, value: title, isStandard: true),
      if (info.account.isNotEmpty)
        EntryField(
          key: AppKdbxFieldKeys.userName,
          value: info.account,
          isStandard: true,
        ),
      EntryField(
        key: 'otp',
        value: otpAuthUrl,
        isProtected: true,
        isStandard: true,
      ),
    ];
    await repository.createEntry(groupUuid: targetGroupUuid, fields: fields);
  }

  Future<void> _confirmAddTotp() async {
    final url = _otpauthUrl;
    if (url == null || url.trim().isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      final entries = _sortedEntries(
        ref
            .read(vaultVisibleEntriesProvider)
            .where(_entryIsLoginOrSecureNote)
            .toList(),
      );
      if (_saveMode == _TotpSaveMode.existingItem) {
        final selectedUuid = _selectedEntryUuid;
        if (selectedUuid == null) {
          throw const VaultStateException('Select an item to add 2FA');
        }
        KdbxEntry? selected;
        for (final entry in entries) {
          if (entry.uuid == selectedUuid) {
            selected = entry;
            break;
          }
        }
        if (selected == null) {
          throw const VaultStateException('Selected item was not found');
        }
        await _saveToExistingItem(entry: selected, otpAuthUrl: url);
      } else {
        await _createNewItemWithTotp(otpAuthUrl: url);
      }

      final repository = ref.read(kdbxRepositoryProvider);
      final registry = ref.read(databaseRegistryProvider);
      final database = await saveAndSyncDatabase(repository, registry);
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultVisibleEntriesProvider);
      ref.invalidate(vaultAllTagsProvider);
      ref.invalidate(vaultSidebarCategoriesProvider);

      if (!mounted) return;
      final success = _saveMode == _TotpSaveMode.existingItem
          ? '2FA code added to item'
          : 'New item with 2FA created';
      AppSnackBar.success(context, success);
      widget.onClose();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      AppSnackBar.error(context, 'Unable to add 2FA code: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: widget.onClose,
        child: Container(
          color: const Color(0x52000000),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
          child: GestureDetector(
            onTap: () {},
            child: switch (_step) {
              _AddTotpStep.input => _buildInputStep(context),
              _AddTotpStep.preview => _buildPreviewStep(context),
              _AddTotpStep.target => _buildTargetStep(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInputStep(BuildContext context) {
    final canContinue = _manualCtrl.text.trim().isNotEmpty;

    return Container(
      width: MediaQuery.sizeOf(context).width - 32,
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDADFE8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1C172033),
            blurRadius: 44,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Add 2FA Code',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF202939),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Scan QR with camera or paste an otpauth URL/setup key manually.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF667085),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isLaunchingScanner ? null : _scanWithCamera,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0A3B48),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: _isLaunchingScanner
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: Text(
              _isLaunchingScanner ? 'Opening camera...' : 'Scan QR With Camera',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Divider(color: Color(0xFFE4E9F2))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'or enter manually',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A97AC),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: Color(0xFFE4E9F2))),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _manualCtrl,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _goToPreview(),
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'otpauth://totp/... or TOTP secret (Base32)',
              hintStyle: const TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              fillColor: const Color(0xFFF7F9FB),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD8DEE8)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD8DEE8)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF4B6CFF)),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFE53E3E),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3E4A5E),
                    side: const BorderSide(color: Color(0xFFD6DCE6)),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: canContinue ? _goToPreview : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A3B48),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewStep(BuildContext context) {
    final url = _otpauthUrl!;
    final info = _parseOtpInfo(url);
    final rawCode = _totpService.generateCode(url, timestamp: _now);
    final formattedCode = _formatTotpCode(rawCode);
    final seconds = _totpService.secondsRemaining(url, timestamp: _now);
    final countdownColor = _totpCountdownColor(seconds);
    final progress = seconds / 30.0;

    return Container(
      width: MediaQuery.sizeOf(context).width - 32,
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDADFE8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1C172033),
            blurRadius: 44,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () {
                  setState(() => _step = _AddTotpStep.input);
                },
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Add 2FA Code',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF202939),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: Color(0xFF059669),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '2FA code ready to add',
                    style: TextStyle(
                      color: Color(0xFF065F46),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (info.issuer.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              info.issuer,
              style: const TextStyle(
                color: Color(0xFF202939),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (info.account.isNotEmpty)
              Text(
                info.account,
                style: const TextStyle(
                  color: Color(0xFF73839D),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E9F2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current TOTP Code',
                  style: TextStyle(
                    color: Color(0xFF8A97AC),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      formattedCode,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        height: 1,
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${seconds.toString().padLeft(2, '0')}s',
                          style: TextStyle(
                            color: countdownColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 78,
                          height: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: const Color(0xFFE8EDF5),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                countdownColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onClose,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3E4A5E),
                    side: const BorderSide(color: Color(0xFFD6DCE6)),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Dismiss'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _isSaving ? null : _goToTarget,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A3B48),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetStep(BuildContext context) {
    final entries = _sortedEntries(
      ref
          .watch(vaultVisibleEntriesProvider)
          .where(_entryIsLoginOrSecureNote)
          .toList(),
    );
    final filteredEntries = _filterEntries(entries, _itemQuery);
    final hasEntries = entries.isNotEmpty;
    final url = _otpauthUrl!;
    final info = _parseOtpInfo(url);
    final rawCode = _totpService.generateCode(url, timestamp: _now);
    final formattedCode = _formatTotpCode(rawCode);
    final seconds = _totpService.secondsRemaining(url, timestamp: _now);
    final countdownColor = _totpCountdownColor(seconds);
    final canSave =
        !_isSaving &&
        (_saveMode == _TotpSaveMode.newItem || _selectedEntryUuid != null);

    return Container(
      width: MediaQuery.sizeOf(context).width - 32,
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDADFE8)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1C172033),
            blurRadius: 44,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => setState(() => _step = _AddTotpStep.preview),
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Save 2FA Code',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF202939),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5EAF1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (info.issuer.isNotEmpty)
                        Text(
                          info.issuer,
                          style: const TextStyle(
                            color: Color(0xFF202939),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (info.account.isNotEmpty)
                        Text(
                          info.account,
                          style: const TextStyle(
                            color: Color(0xFF73839D),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        formattedCode,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: countdownColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${seconds.toString().padLeft(2, '0')}s',
                    style: TextStyle(
                      color: countdownColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F6FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD6DCE6)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: hasEntries
                        ? () => setState(
                            () => _saveMode = _TotpSaveMode.existingItem,
                          )
                        : null,
                    child: Container(
                      alignment: Alignment.center,
                      color: _saveMode == _TotpSaveMode.existingItem
                          ? const Color(0xFF0A3B48)
                          : Colors.transparent,
                      child: Text(
                        'Add To Existing Item',
                        style: TextStyle(
                          color: _saveMode == _TotpSaveMode.existingItem
                              ? Colors.white
                              : const Color(0xFF475467),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(width: 1, color: const Color(0xFFD6DCE6)),
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        setState(() => _saveMode = _TotpSaveMode.newItem),
                    child: Container(
                      alignment: Alignment.center,
                      color: _saveMode == _TotpSaveMode.newItem
                          ? const Color(0xFF0A3B48)
                          : Colors.transparent,
                      child: Text(
                        'Create New Item',
                        style: TextStyle(
                          color: _saveMode == _TotpSaveMode.newItem
                              ? Colors.white
                              : const Color(0xFF475467),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_saveMode == _TotpSaveMode.existingItem) ...[
            TextField(
              controller: _itemSearchCtrl,
              onChanged: (value) => setState(() => _itemQuery = value),
              style: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Search item to attach this 2FA',
                hintStyle: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: Color(0xFF6E8A93),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                fillColor: const Color(0xFFF7F9FB),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD8DEE8)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFD8DEE8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF4B6CFF)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE4E9F2)),
              ),
              clipBehavior: Clip.antiAlias,
              child: !hasEntries
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      child: Text(
                        'No items found in this vault. Choose "Create New Item".',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : filteredEntries.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      child: Text(
                        'No matching items',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      primary: false,
                      padding: EdgeInsets.zero,
                      itemCount: filteredEntries.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1, color: Color(0xFFF0F3F8)),
                      itemBuilder: (context, index) {
                        final entry = filteredEntries[index];
                        final selected = entry.uuid == _selectedEntryUuid;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () =>
                                setState(() => _selectedEntryUuid = entry.uuid),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  VaultEntryAvatar(entry: entry, size: 28),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF163640),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    size: 18,
                                    color: selected
                                        ? const Color(0xFF0A3B48)
                                        : const Color(0xFF9AA7BA),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE4E9F2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A new item will be created with this 2FA code.',
                    style: TextStyle(
                      color: Color(0xFF344054),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Title: ${info.issuer.isNotEmpty ? info.issuer : 'Authenticator'}',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (info.account.isNotEmpty)
                    Text(
                      'Username: ${info.account}',
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving
                      ? null
                      : () => setState(() => _step = _AddTotpStep.preview),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3E4A5E),
                    side: const BorderSide(color: Color(0xFFD6DCE6)),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: canSave ? _confirmAddTotp : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0A3B48),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _isSaving
                        ? 'Saving...'
                        : (_saveMode == _TotpSaveMode.existingItem
                              ? 'Add To Item'
                              : 'Create Item'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotpCameraScannerSheet extends StatefulWidget {
  const _TotpCameraScannerSheet();

  @override
  State<_TotpCameraScannerSheet> createState() =>
      _TotpCameraScannerSheetState();
}

class _TotpCameraScannerSheetState extends State<_TotpCameraScannerSheet> {
  late final MobileScannerController _controller;
  bool _handled = false;
  bool _torchOn = false;
  bool _frontCamera = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(raw);
      return;
    }
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) return;
    setState(() => _torchOn = !_torchOn);
  }

  Future<void> _switchCamera() async {
    await _controller.switchCamera();
    if (!mounted) return;
    setState(() => _frontCamera = !_frontCamera);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.86,
        decoration: const BoxDecoration(
          color: Color(0xFF0C1820),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              child: Row(
                children: [
                  const Text(
                    'Scan TOTP QR',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _toggleTorch,
                    icon: Icon(
                      _torchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: _switchCamera,
                    icon: Icon(
                      _frontCamera
                          ? Icons.camera_rear_rounded
                          : Icons.camera_front_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) {
                          return Container(
                            color: const Color(0xFF101A23),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Camera unavailable. Please allow camera permission in settings, or use manual input.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          );
                        },
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xAAFFFFFF),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 18),
              child: Text(
                'Point the camera at the QR code',
                style: TextStyle(
                  color: Color(0xFFD6E1EC),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _homeText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _homeMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotpTab extends ConsumerStatefulWidget {
  const _TotpTab();

  @override
  ConsumerState<_TotpTab> createState() => _TotpTabState();
}

class _TotpTabState extends ConsumerState<_TotpTab>
    with WidgetsBindingObserver {
  static const _totp = TOTPService();
  Timer? _clock;
  late final TextEditingController _searchCtrl;
  String _query = '';

  /// Broadcast ticker. Using a [ValueNotifier] instead of `setState` on every
  /// tick means only the rows that actually show the TOTP countdown rebuild
  /// each second — the surrounding tab, search bar, and entry list stay put.
  late final ValueNotifier<DateTime> _nowNotifier;

  // Cache TOTP codes per entry — codes only rotate every 30 s.
  final Map<String, String?> _codeCache = {};
  int _lastWindow = -1;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _nowNotifier = ValueNotifier<DateTime>(DateTime.now());
    WidgetsBinding.instance.addObserver(this);
    _startClock();
  }

  @override
  void deactivate() {
    // Fired when the element is removed (tab switch, navigation pop, etc).
    // Stop the ticker immediately so we never tick after the user has left
    // this tab, even in the brief window before `dispose` runs.
    _stopClock();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopClock();
    _nowNotifier.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause the per-second ticker whenever the app is not in the foreground
    // — avoids burning CPU and scheduling frame callbacks while nothing on
    // this screen is visible.
    switch (state) {
      case AppLifecycleState.resumed:
        _startClock();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _stopClock();
        break;
    }
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _stopClock();
        return;
      }
      _nowNotifier.value = DateTime.now();
    });
  }

  void _stopClock() {
    _clock?.cancel();
    _clock = null;
  }

  String? _cachedCode(KdbxEntry entry, DateTime now) {
    final window = now.millisecondsSinceEpoch ~/ 30000;
    if (window != _lastWindow) {
      _codeCache.clear();
      _lastWindow = window;
    }
    return _codeCache.putIfAbsent(
      entry.uuid,
      () => _totp.generateCode(entry.otpAuthUrl, timestamp: now),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(vaultVisibleEntriesProvider);
    final totpEntries =
        entries
            .where((e) => _entryIsLoginOrSecureNote(e) && entryHasTotp(e))
            .toList(growable: false)
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
    final terms = _query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    final filtered = terms.isEmpty
        ? totpEntries
        : totpEntries
              .where((entry) {
                final haystack = [
                  entry.title,
                  entry.username ?? '',
                  entry.url ?? '',
                  entry.notes ?? '',
                  ...entry.tags,
                ].join(' ').toLowerCase();
                return terms.every(haystack.contains);
              })
              .toList(growable: false);

    if (totpEntries.isEmpty) {
      return const _PlaceholderTab(
        title: 'TOTP',
        message: 'No items with TOTP in this vault yet.',
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No matching TOTP items',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _homeMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 96),
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    // Each row subscribes individually to the tick so only
                    // the row body rebuilds every second — the list and
                    // surrounding chrome do not.
                    return RepaintBoundary(
                      child: ValueListenableBuilder<DateTime>(
                        valueListenable: _nowNotifier,
                        builder: (context, now, _) {
                          final rawCode = _cachedCode(entry, now);
                          final secondsRemaining = _totp.secondsRemaining(
                            entry.otpAuthUrl,
                            timestamp: now,
                          );
                          final code = _formatTotpCode(rawCode);
                          final accent = _totpCountdownColor(secondsRemaining);

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                final rawToCopy = (rawCode ?? '').replaceAll(
                                  RegExp(r'\s+'),
                                  '',
                                );
                                if (rawToCopy.isEmpty) {
                                  return;
                                }
                                await Clipboard.setData(
                                  ClipboardData(text: rawToCopy),
                                );
                                if (!context.mounted) return;
                                AppSnackBar.success(
                                  context,
                                  'Copied TOTP for ${entry.title}',
                                );
                              },
                              child: Ink(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: _homeSurface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _homeBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        VaultEntryAvatar(
                                          entry: entry,
                                          size: 34,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            entry.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _homeText,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: accent.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.timer_outlined,
                                                size: 13,
                                                color: accent,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${secondsRemaining.toString().padLeft(2, '0')}s',
                                                style: TextStyle(
                                                  color: accent,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      code,
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 34,
                                        height: 1,
                                        letterSpacing: 1.1,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemCount: filtered.length,
                ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 12,
          child: FloatingGlassSearchToolbar(
            controller: _searchCtrl,
            hintText: 'Search TOTP items',
            onChanged: (value) => setState(() => _query = value),
            onAdd: () => showAddTotpOverlay(context),
            addSemanticLabel: 'Add TOTP',
          ),
        ),
      ],
    );
  }
}

String _formatTotpCode(String? raw) {
  final value = (raw ?? '').replaceAll(RegExp(r'\s+'), '');
  if (value.length == 6) {
    return '${value.substring(0, 3)} ${value.substring(3)}';
  }
  return value.isEmpty ? '------' : value;
}

Color _totpCountdownColor(int secondsRemaining) {
  if (secondsRemaining <= 9) {
    return const Color(0xFFDC2626);
  }
  if (secondsRemaining <= 15) {
    return const Color(0xFFF59E0B);
  }
  return const Color(0xFF16A34A);
}

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(homeVaultTitleProvider);
    final storageType = ref.watch(homeVaultStorageTypeProvider);

    final vaultIconAsset = switch (storageType) {
      'googleDrive' => 'assets/images/google-drive.png',
      'dropbox' => 'assets/images/dropbox.png',
      'oneDrive' => 'assets/images/onedrive.png',
      'webdav' => 'assets/images/webdav.png',
      _ => 'assets/images/dir.png',
    };

    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              vaultIconAsset,
              width: 22,
              height: 22,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF0B1F26),
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _IconAction(
                  icon: Icons.lock_outline_rounded,
                  filled: true,
                  onTap: () => _confirmLockVault(context, ref),
                ),
                const SizedBox(width: 2),
                _IconAction(
                  icon: Icons.key_outlined,
                  filled: true,
                  onTap: () => showPasswordGeneratorModal(context),
                ),
              ],
            ),
            _IconAction(
              icon: Icons.settings_outlined,
              filled: true,
              onTap: () => showVaultSettingsModal(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, this.filled = false, this.onTap});

  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: filled ? _homeInk : const Color(0xFFDCEEF2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 20,
            color: filled ? const Color(0xFFEAF6F9) : _homeInk,
          ),
        ),
      ),
    );
  }
}

class _LastUsedSection extends ConsumerStatefulWidget {
  const _LastUsedSection();

  @override
  ConsumerState<_LastUsedSection> createState() => _LastUsedSectionState();
}

class _LastUsedSectionState extends ConsumerState<_LastUsedSection> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(homeRecentEntriesProvider);
    final query = ref.watch(vaultSearchQueryProvider).trim();
    final emptyMessage = query.isNotEmpty
        ? 'No matching items'
        : 'No items in this vault';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: Color(0xFF4B8591),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Last used items',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _homeText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => showAddNewItemOverlay(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _homeInk,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '+ Create item',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFEAF6F9),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: _homeSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6EDF2)),
          ),
          clipBehavior: Clip.antiAlias,
          child: recent.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: Center(
                    child: Text(
                      emptyMessage,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _homeMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < recent.length; i++)
                      VaultEntryListTile(
                        entry: recent[i],
                        selected: false,
                        showBottomBorder: i < recent.length - 1,
                        onTap: () async {
                          final categories = ref.read(
                            vaultSidebarCategoriesProvider,
                          );
                          String? categoryName;
                          for (final c in categories) {
                            if (c.uuid == recent[i].groupUuid) {
                              categoryName = c.name;
                              break;
                            }
                          }
                          ref
                              .read(
                                vaultItemsSelectedEntryUuidProvider.notifier,
                              )
                              .state = recent[i]
                              .uuid;
                          await showItemDetailsModal(
                            context,
                            entry: recent[i],
                            categoryName: categoryName,
                          );
                        },
                        onLongPress: () =>
                            _showHomeContextMenu(context, ref, recent[i]),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

void _showHomeContextMenu(
  BuildContext context,
  WidgetRef ref,
  KdbxEntry entry,
) {
  ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state = entry.uuid;
  showVaultEntryContextMenuDialog(
    context,
    entry: entry,
    onItemSaved: (uuid) {
      ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state = uuid;
    },
  );
}

class _QuickAccessSection extends ConsumerWidget {
  const _QuickAccessSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(homeQuickAccessCountsProvider);
    final cards = [
      _QuickCardData(
        title: 'All items',
        count: '${counts.all} items',
        icon: Icons.inventory_2_outlined,
      ),
      _QuickCardData(
        title: 'TOTP',
        count: '${counts.totp} items',
        icon: Icons.verified_user_outlined,
      ),
      _QuickCardData(
        title: 'Secure Notes',
        count: '${counts.secureNotes} items',
        icon: Icons.sticky_note_2_outlined,
      ),
      _QuickCardData(
        title: 'SSH',
        count: '${counts.ssh} items',
        icon: Icons.dns_outlined,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF1A6272)),
            const SizedBox(width: 6),
            Text(
              'Quick access',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: _homeText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < cards.length; row += 2) ...[
          Row(
            children: [
              Expanded(child: _QuickCard(card: cards[row])),
              const SizedBox(width: 8),
              Expanded(child: _QuickCard(card: cards[row + 1])),
            ],
          ),
          if (row + 2 < cards.length) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.card});

  final _QuickCardData card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _homeSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _homeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(card.icon, size: 16, color: const Color(0xFF1C6374)),
          const SizedBox(height: 6),
          Text(
            card.title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _homeText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            card.count,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF7A849A),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagsSection extends ConsumerWidget {
  const _TagsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(homePopularTagsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tags',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: _homeText,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (tags.isEmpty)
          Text(
            'No tags yet',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _homeMuted,
              fontWeight: FontWeight.w500,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCEEF2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _homeInk,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _BottomNavBar extends ConsumerWidget {
  const _BottomNavBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(mobileHomeTabProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    void select(MobileHomeTab next) {
      ref.read(mobileHomeTabProvider.notifier).state = next;
      if (next == MobileHomeTab.items) {
        final list = ref.read(vaultItemsSortedEntriesProvider);
        final sel = ref.read(vaultItemsSelectedEntryUuidProvider);
        if (sel == null && list.isNotEmpty) {
          ref.read(vaultItemsSelectedEntryUuidProvider.notifier).state =
              list.first.uuid;
        }
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset > 0 ? 16 : 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(
              color: Color(0x240A2F3D),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              height: 68,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xDFFFFFFF),
                    Color(0xB8F8FEFF),
                    Color(0x96D9EDF1),
                  ],
                  stops: [0, 0.54, 1],
                ),
                border: Border.all(color: Color(0xBFFFFFFF), width: 1.1),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 18,
                    right: 18,
                    top: 3,
                    child: IgnorePointer(
                      child: Container(
                        height: 17,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: const LinearGradient(
                            colors: [Color(0x8AFFFFFF), Color(0x12FFFFFF)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _NavItem(
                          icon: Icons.house_rounded,
                          label: 'HOME',
                          active: tab == MobileHomeTab.home,
                          onTap: () => select(MobileHomeTab.home),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          icon: Icons.grid_view_rounded,
                          label: 'ITEMS',
                          active: tab == MobileHomeTab.items,
                          onTap: () => select(MobileHomeTab.items),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          icon: Icons.timer_outlined,
                          label: 'TOTP',
                          active: tab == MobileHomeTab.totp,
                          onTap: () => select(MobileHomeTab.totp),
                        ),
                      ),
                      Expanded(
                        child: _NavItem(
                          icon: Icons.person_outline_rounded,
                          label: 'ACCOUNT',
                          active: tab == MobileHomeTab.profile,
                          onTap: () => select(MobileHomeTab.profile),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : _homeMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: active
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0C5562), Color(0xFF063B46)],
                  )
                : null,
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x330A3B48),
                      blurRadius: 14,
                      offset: Offset(0, 5),
                    ),
                    BoxShadow(
                      color: Color(0x55FFFFFF),
                      blurRadius: 8,
                      offset: Offset(-2, -2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickCardData {
  const _QuickCardData({
    required this.title,
    required this.count,
    required this.icon,
  });

  final String title;
  final String count;
  final IconData icon;
}
