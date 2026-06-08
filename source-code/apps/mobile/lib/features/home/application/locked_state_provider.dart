import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

/// Holds the [DatabaseRecord] for the vault that was just locked while the
/// user is still inside the home shell.
///
/// When non-null, an inline unlock overlay is shown on top of the home
/// scaffold so the user can resume their session without being navigated
/// back to the vault picker. Clearing it (after a successful unlock) hides
/// the overlay without tearing down the underlying item list state.
final mobileLockedRecordProvider =
    StateProvider<DatabaseRecord?>((ref) => null);
