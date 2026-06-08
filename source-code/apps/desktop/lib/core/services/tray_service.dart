import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';

import '../constants/dock_icon_assets.dart';
import '../repository/kdbx_repository_provider.dart';
import 'shortcut_service.dart';
import 'tray_action_provider.dart';

class TrayService with TrayListener {
  TrayService._();

  static final TrayService instance = TrayService._();

  static const _windowChannel = MethodChannel('lumenpass/window');

  ProviderContainer? _container;
  ProviderSubscription<ShortcutData?>? _spotlightShortcutSubscription;
  ProviderSubscription<ShortcutData?>? _lockVaultShortcutSubscription;
  bool _isLocked = true;

  Future<void> init(ProviderContainer container) async {
    _container = container;

    if (Platform.isMacOS) {
      trayManager.addListener(this);
      await trayManager.setIcon(await _resolvedDockIconAsset());
      await _applyLockedIconOpacity();
    }

    if (Platform.isWindows || Platform.isLinux) {
      await _applyWindowsVaultLockedState();
    }

    _spotlightShortcutSubscription = container.listen<ShortcutData?>(
      spotlightShortcutProvider,
      (_, __) => unawaited(_rebuildMenu()),
      fireImmediately: true,
    );
    _lockVaultShortcutSubscription = container.listen<ShortcutData?>(
      lockVaultShortcutProvider,
      (_, __) => unawaited(_rebuildMenu()),
      fireImmediately: true,
    );

    await _rebuildMenu();
  }

  /// Call this when the vault is locked or unlocked to update
  /// the tray icon opacity and menu items accordingly.
  Future<void> setVaultLocked(bool locked) async {
    if (_isLocked == locked) return;
    _isLocked = locked;

    if (Platform.isMacOS) {
      await _applyLockedIconOpacity();
      await _rebuildMenu();
    }

    if (Platform.isWindows) {
      await _applyWindowsVaultLockedState();
    }
  }

  Future<void> _applyWindowsVaultLockedState() async {
    try {
      await _windowChannel.invokeMethod<void>('setTrayVaultLocked', _isLocked);
    } catch (_) {}
  }

  Future<void> _applyLockedIconOpacity() async {
    try {
      await _windowChannel.invokeMethod<void>(
        'setTrayIconOpacity',
        _isLocked ? 0.7 : 1.0,
      );
    } catch (_) {}
  }

  Future<void> refreshIconFromPreferences() async {
    if (!Platform.isMacOS) return;
    await trayManager.setIcon(await _resolvedDockIconAsset());
    await _applyLockedIconOpacity();
  }

  Future<String> _resolvedDockIconAsset() async {
    final storage = _container?.read(localStorageProvider);
    if (storage == null) {
      return dockIconDefaultAsset;
    }
    final savedAsset = await storage.read(key: dockIconPreferenceKey);
    final isKnownAsset = dockIconOptions.any(
      (option) => option.assetPath == savedAsset,
    );
    return isKnownAsset ? savedAsset! : dockIconDefaultAsset;
  }

  Future<void> _rebuildMenu() async {
    if (Platform.isWindows) {
      return;
    }

    if (_isLocked) {
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'unlock_vault', label: 'Unlock Vault'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Quit LumenPass'),
          ],
        ),
      );
      return;
    }

    final spotlightShortcut = _container?.read(spotlightShortcutProvider);
    final lockVaultShortcut = _container?.read(lockVaultShortcutProvider);
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open_dashboard', label: 'Open Dashboard'),
          MenuItem(
            key: 'quick_search',
            label: _menuLabelWithShortcut(
              'Quick Search',
              spotlightShortcut?.display ?? ShortcutData.defaultSpotlight.display,
            ),
          ),
          MenuItem(key: 'generate_password', label: 'Generate Password'),
          MenuItem(key: 'switch_vaults', label: 'Switch Vaults'),
          MenuItem.separator(),
          MenuItem(
            key: 'lock_vault',
            label: _menuLabelWithShortcut(
              'Lock Vault',
              lockVaultShortcut?.display ?? ShortcutData.defaultLockVault.display,
            ),
          ),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit LumenPass'),
        ],
      ),
    );
  }

  String _menuLabelWithShortcut(String label, String shortcut) {
    final trimmedShortcut = shortcut.trim();
    if (trimmedShortcut.isEmpty) {
      return label;
    }
    // macOS renders text after a tab character right-aligned in menu rows.
    // Keep a minimum text-column width so shortcut glyphs don't crowd labels.
    final paddedLabel = label.padRight(18);
    return '$paddedLabel\t$trimmedShortcut';
  }

  Future<void> _bringToFront() async {
    try {
      await _windowChannel.invokeMethod<void>('bringToFront');
    } catch (_) {}
  }

  void _dispatch(TrayAction action) {
    _container?.read(pendingTrayActionProvider.notifier).state = action;
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'unlock_vault':
        _bringToFront();
        _dispatch(TrayAction.openDashboard);
      case 'open_dashboard':
        _bringToFront();
        _dispatch(TrayAction.openDashboard);
      case 'quick_search':
        _bringToFront();
        _dispatch(TrayAction.quickSearch);
      case 'generate_password':
        _bringToFront();
        _dispatch(TrayAction.generatePassword);
      case 'switch_vaults':
        _bringToFront();
        _dispatch(TrayAction.switchVaults);
      case 'lock_vault':
        _dispatch(TrayAction.lockVault);
      case 'quit':
        _windowChannel.invokeMethod<void>('quit').catchError((_) => exit(0));
    }
  }

  Future<void> dispose() async {
    _spotlightShortcutSubscription?.close();
    _spotlightShortcutSubscription = null;
    _lockVaultShortcutSubscription?.close();
    _lockVaultShortcutSubscription = null;
    if (Platform.isMacOS) {
      trayManager.removeListener(this);
    }
  }
}
