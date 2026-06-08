import 'package:flutter/material.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

/// Visual treatment for a [VaultItemType] on the home screen (icons match desktop semantics).
({IconData icon, Color background, Color iconColor}) homeEntryStyle(
  VaultItemType type,
) {
  switch (type) {
    case VaultItemType.login:
      return (
        icon: Icons.public_rounded,
        background: const Color(0xFFE8F1FF),
        iconColor: const Color(0xFF4B78E6),
      );
    case VaultItemType.apiCredential:
      return (
        icon: Icons.vpn_key_rounded,
        background: const Color(0xFFEEE8FC),
        iconColor: const Color(0xFF8A63F6),
      );
    case VaultItemType.creditCard:
    case VaultItemType.bankAccount:
      return (
        icon: Icons.credit_card_rounded,
        background: const Color(0xFFEEF2FF),
        iconColor: const Color(0xFF6679D8),
      );
    case VaultItemType.server:
      return (
        icon: Icons.apartment_rounded,
        background: const Color(0xFFDBEAFE),
        iconColor: const Color(0xFF3A77DE),
      );
    case VaultItemType.sshKey:
      return (
        icon: Icons.terminal_rounded,
        background: const Color(0xFFEAF4E6),
        iconColor: const Color(0xFF5D8C45),
      );
    case VaultItemType.secureNote:
    case VaultItemType.document:
      return (
        icon: Icons.sticky_note_2_outlined,
        background: const Color(0xFFF3F4F6),
        iconColor: const Color(0xFF5B6474),
      );
    case VaultItemType.identity:
    case VaultItemType.passport:
      return (
        icon: Icons.badge_outlined,
        background: const Color(0xFFE0F2FE),
        iconColor: const Color(0xFF0369A1),
      );
    case VaultItemType.wifiPassword:
      return (
        icon: Icons.wifi_rounded,
        background: const Color(0xFFE8F5E9),
        iconColor: const Color(0xFF2E7D32),
      );
  }
}

String homeEntryShortDate(KdbxEntry entry) {
  final label = formatVaultEntryListDateLabel(
    now: DateTime.now(),
    updatedAt: entry.updatedAt,
    createdAt: entry.createdAt,
  );
  if (label.isEmpty) {
    return '—';
  }
  return label;
}
