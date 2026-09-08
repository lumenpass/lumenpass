import 'package:flutter/material.dart';

/// App-wide navigator key so services without a [BuildContext] (e.g. the
/// background vault write scheduler) can surface snackbars and dialogs.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
