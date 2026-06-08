import 'package:flutter/material.dart';

import '../../../core/ui/app_snack_bar.dart';

/// Shared floating toast for vault flows.
void showVaultFloatingToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 15),
}) => AppSnackBar.info(context, message, duration: duration);
