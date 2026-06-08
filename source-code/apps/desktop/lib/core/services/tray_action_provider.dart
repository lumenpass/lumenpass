import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TrayAction {
  openDashboard,
  quickSearch,
  generatePassword,
  newItem,
  switchVaults,
  lockVault,
}

final pendingTrayActionProvider = StateProvider<TrayAction?>((ref) => null);
final pendingEditItemRequestProvider = StateProvider<String?>((ref) => null);
