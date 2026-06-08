import 'package:flutter_riverpod/flutter_riverpod.dart';

enum MobileHomeTab { home, items, totp, profile }

final mobileHomeTabProvider =
    StateProvider<MobileHomeTab>((ref) => MobileHomeTab.home);
