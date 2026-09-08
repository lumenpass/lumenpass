import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../application/vault_entries_providers.dart';
import '../application/vault_items_list_providers.dart';
import 'vault_all_items_screen.dart';
import 'vault_category_filter_dropdown.dart';
import 'vault_create_item_models.dart';

const _pageBackground = Color(0xFFF4F9FA);
const _sectionTitle = Color(0xFF163640);
const _sectionSubtitle = Color(0xFF6B858D);
const _cardBorder = Color(0xFFE3EAF0);
const _cardSurface = Colors.white;
const _countText = Color(0xFF56717A);
const _chipFill = Color(0xFFE8F3F5);
const _chipText = Color(0xFF24505A);
const _floatingHeaderContentTopPadding = 92.0;
const _contentBottomPadding = 176.0;
const _maxVisibleTags = 24;
const String _kCategoryIconNotesPrefix = 'lumenpass-category-icon:';

/// Tag summaries are derived from the visible entries. Computing them in a
/// provider (rather than inline in `build`) caches the O(entries x tags)
/// aggregation so it only re-runs when the entries list actually changes, not
/// on every unrelated rebuild of the tab.
final _vaultTagSummariesProvider = Provider<List<_TagSummary>>((ref) {
  final entries = ref.watch(vaultVisibleEntriesProvider);
  return _buildTagSummaries(entries);
});

/// Item-type counts, memoized for the same reason as [_vaultTagSummariesProvider].
final _vaultItemTypeSummariesProvider = Provider<List<_ItemTypeSummary>>((
  ref,
) {
  final entries = ref.watch(vaultVisibleEntriesProvider);
  return _buildItemTypeSummaries(entries);
});

class VaultItemsTab extends ConsumerWidget {
  const VaultItemsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(vaultVisibleEntriesProvider);
    final categories = ref.watch(vaultSidebarCategoriesProvider);
    final uncategorizedCount = ref.watch(vaultUncategorizedCountProvider);
    final tagSummaries = ref.watch(_vaultTagSummariesProvider);
    final itemTypes = ref.watch(_vaultItemTypeSummariesProvider);
    final displayedTags = tagSummaries
        .take(_maxVisibleTags)
        .toList(growable: false);
    final hiddenTagCount = tagSummaries.length - displayedTags.length;

    return ColoredBox(
      color: _pageBackground,
      child: Stack(
        children: [
          RefreshIndicator(
            color: const Color(0xFF2F67E3),
            onRefresh: () => refreshVaultSnapshot(ref),
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                _floatingHeaderContentTopPadding,
                20,
                MediaQuery.paddingOf(context).bottom + _contentBottomPadding,
              ),
              children: [
                _PrimaryBrowseRow(
                  title: 'All Items',
                  count: entries.length,
                  icon: Icons.inventory_2_outlined,
                  iconColor: const Color(0xFF4B79E5),
                  iconBackground: const Color(0xFFE4EDFF),
                  onTap: () => openVaultAllItemsScreen(context),
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: 'All Categories',
                  subtitle: 'Browse by vault category',
                  trailing: _SectionCircleButton(
                    semanticLabel: 'Add category',
                    icon: Icons.add_rounded,
                    onTap: () => openCreateCategoryDialog(context, ref),
                  ),
                ),
                const SizedBox(height: 10),
                _ItemsHubCard(
                  child: categories.isEmpty && uncategorizedCount == 0
                      ? const _EmptySectionState(
                          title: 'No categories yet',
                          message: 'Create a category to organize items here.',
                        )
                      : Column(
                          children: [
                            if (uncategorizedCount > 0)
                              _BrowseListRow(
                                title: 'Uncategorized',
                                count: uncategorizedCount,
                                leading: const _CategoryLeadingVisual(
                                  categoryId: kCategoryFilterUncategorized,
                                  notes: '',
                                ),
                                showDivider: categories.isNotEmpty,
                                onTap: () => openVaultAllItemsScreen(
                                  context,
                                  title: 'Uncategorized',
                                  uncategorizedOnly: true,
                                ),
                              ),
                            for (var i = 0; i < categories.length; i++)
                              _BrowseListRow(
                                title: categories[i].name,
                                count: categories[i].count,
                                leading: _CategoryLeadingVisual(
                                  categoryId: categories[i].uuid,
                                  notes: categories[i].notes,
                                ),
                                showDivider: i < categories.length - 1,
                                onTap: () => openVaultAllItemsScreen(
                                  context,
                                  title: categories[i].name,
                                  categoryUuid: categories[i].uuid,
                                ),
                                onLongPress: () => showCategoryActionSheet(
                                  context,
                                  ref,
                                  category: categories[i],
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
                const _SectionHeader(
                  title: 'Tags',
                  subtitle: 'Jump into frequently used tags',
                ),
                const SizedBox(height: 10),
                _ItemsHubCard(
                  child: tagSummaries.isEmpty
                      ? const _EmptySectionState(
                          title: 'No tags yet',
                          message:
                              'Add tags to items and they will show up here.',
                        )
                      : Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: displayedTags
                                    .map(
                                      (tag) => _TagChip(
                                        label: tag.label,
                                        count: tag.count,
                                        onTap: () => openVaultAllItemsScreen(
                                          context,
                                          title: '#${tag.label}',
                                          tag: tag.label,
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                              if (hiddenTagCount > 0) ...[
                                const SizedBox(height: 14),
                                Text(
                                  '$hiddenTagCount more tags available',
                                  style: const TextStyle(
                                    color: _sectionSubtitle,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                const _SectionHeader(
                  title: 'Item Types',
                  subtitle: 'Open items by template type',
                ),
                const SizedBox(height: 10),
                _ItemsHubCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < itemTypes.length; i++)
                        _BrowseListRow(
                          title: itemTypes[i].label,
                          count: itemTypes[i].count,
                          leading: _ItemTypeLeadingVisual(type: itemTypes[i]),
                          showDivider: i < itemTypes.length - 1,
                          onTap: () => openVaultAllItemsScreen(
                            context,
                            title: itemTypes[i].label,
                            itemTypeId: itemTypes[i].id,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<_TagSummary> _buildTagSummaries(List<KdbxEntry> entries) {
  final counts = <String, int>{};
  for (final entry in entries) {
    for (final raw in entry.tags) {
      final tag = raw.trim();
      if (tag.isEmpty) {
        continue;
      }
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }

  final summaries = counts.entries
      .map((entry) => _TagSummary(label: entry.key, count: entry.value))
      .toList(growable: false);

  summaries.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) {
      return byCount;
    }
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return summaries;
}

List<_ItemTypeSummary> _buildItemTypeSummaries(List<KdbxEntry> entries) {
  final counts = <String, int>{for (final type in kAllNewItemTypes) type.id: 0};

  for (final entry in entries) {
    switch (classifyVaultItemType(entry)) {
      case VaultItemType.login:
        counts['login'] = counts['login']! + 1;
        break;
      case VaultItemType.secureNote:
        counts['secure-note'] = counts['secure-note']! + 1;
        break;
      case VaultItemType.creditCard:
        counts['credit-card'] = counts['credit-card']! + 1;
        break;
      case VaultItemType.identity:
        counts['identity'] = counts['identity']! + 1;
        break;
      case VaultItemType.sshKey:
        counts['ssh-key'] = counts['ssh-key']! + 1;
        break;
      case VaultItemType.bankAccount:
        counts['bank-account'] = counts['bank-account']! + 1;
        break;
      default:
        break;
    }
  }

  return kAllNewItemTypes
      .map(
        (type) => _ItemTypeSummary(
          id: type.id,
          label: type.label,
          count: counts[type.id] ?? 0,
          icon: type.icon ?? Icons.label_outline_rounded,
          iconColor: type.iconColor,
          imagePath: type.imagePath,
        ),
      )
      .toList(growable: false);
}

class _PrimaryBrowseRow extends StatelessWidget {
  const _PrimaryBrowseRow({
    required this.title,
    required this.count,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.onTap,
  });

  final String title;
  final int count;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12093C49),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                _SquareIconBadge(
                  icon: icon,
                  iconColor: iconColor,
                  backgroundColor: iconBackground,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _sectionTitle,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: _countText,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFC7D1D6),
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _sectionTitle,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: _sectionSubtitle,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _SectionCircleButton extends StatelessWidget {
  const _SectionCircleButton({
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);

    return Semantics(
      button: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18,
              spreadRadius: -5,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF202020),
                    Color(0xF20B0B0B),
                    Color(0xFF050505),
                  ],
                  stops: [0, 0.48, 1],
                ),
              ),
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.14),
                              Colors.white.withValues(alpha: 0.02),
                              Colors.black.withValues(alpha: 0.22),
                            ],
                            stops: const [0, 0.46, 1],
                          ),
                        ),
                      ),
                    ),
                    Icon(icon, size: 23, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemsHubCard extends StatelessWidget {
  const _ItemsHubCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10093C49),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _BrowseListRow extends StatelessWidget {
  const _BrowseListRow({
    required this.title,
    required this.count,
    required this.leading,
    required this.showDivider,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final int count;
  final Widget leading;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: showDivider ? _cardBorder : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _sectionTitle,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  color: _countText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFC7D1D6),
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.count,
    required this.onTap,
  });

  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _chipFill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFD3E7EA)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '#$label',
                style: const TextStyle(
                  color: _chipText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: const TextStyle(
                  color: _sectionSubtitle,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySectionState extends StatelessWidget {
  const _EmptySectionState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _sectionTitle,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: _sectionSubtitle,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SquareIconBadge extends StatelessWidget {
  const _SquareIconBadge({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: iconColor, size: 22),
    );
  }
}

class _ItemTypeLeadingVisual extends StatelessWidget {
  const _ItemTypeLeadingVisual({required this.type});

  final _ItemTypeSummary type;

  @override
  Widget build(BuildContext context) {
    if (type.imagePath != null && type.imagePath!.isNotEmpty) {
      return Image.asset(
        type.imagePath!,
        width: 34,
        height: 34,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _SquareIconBadge(
          icon: type.icon,
          iconColor: type.iconColor,
          backgroundColor: type.iconColor.withValues(alpha: 0.14),
        ),
      );
    }

    return _SquareIconBadge(
      icon: type.icon,
      iconColor: type.iconColor,
      backgroundColor: type.iconColor.withValues(alpha: 0.14),
    );
  }
}

class _CategoryLeadingVisual extends StatelessWidget {
  const _CategoryLeadingVisual({required this.categoryId, required this.notes});

  final String categoryId;
  final String notes;

  @override
  Widget build(BuildContext context) {
    if (categoryId == kCategoryFilterUncategorized) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/images/categories/383.png',
          width: 34,
          height: 34,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const _SquareIconBadge(
            icon: Icons.folder_open_outlined,
            iconColor: Color(0xFF5A78C5),
            backgroundColor: Color(0xFFE8EEF9),
          ),
        ),
      );
    }

    final decoded = _decodeCategoryVisualPayload(notes);
    if (decoded == null) {
      return const _SquareIconBadge(
        icon: Icons.folder_outlined,
        iconColor: Color(0xFF5A78C5),
        backgroundColor: Color(0xFFE8EEF9),
      );
    }

    if (decoded.presetId.startsWith('img:')) {
      final id = decoded.presetId.substring(4).trim();
      if (id.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            'assets/images/categories/$id.png',
            width: 34,
            height: 34,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _SquareIconBadge(
              icon: Icons.folder_outlined,
              iconColor: Color(0xFF5A78C5),
              backgroundColor: Color(0xFFE8EEF9),
            ),
          ),
        );
      }
    }

    final colors = _categoryColorForId(decoded.colorId);
    return _SquareIconBadge(
      icon: _iconForCategoryPresetId(decoded.presetId),
      iconColor: colors.iconColor,
      backgroundColor: colors.fillColor,
    );
  }
}

({String presetId, String colorId})? _decodeCategoryVisualPayload(
  String? notes,
) {
  final raw = notes?.trim() ?? '';
  if (!raw.startsWith(_kCategoryIconNotesPrefix)) {
    return null;
  }

  final payload = raw.substring(_kCategoryIconNotesPrefix.length);
  final parts = payload.split('|');
  if (parts.length != 2 || parts.any((part) => part.trim().isEmpty)) {
    return null;
  }
  return (presetId: parts[0], colorId: parts[1]);
}

({Color fillColor, Color iconColor}) _categoryColorForId(String colorId) {
  switch (colorId) {
    case 'blue':
      return (
        fillColor: const Color(0xFFE1EDFF),
        iconColor: const Color(0xFF2B7FFF),
      );
    case 'purple':
      return (
        fillColor: const Color(0xFFEEDDFB),
        iconColor: const Color(0xFF8D57B0),
      );
    case 'teal':
      return (
        fillColor: const Color(0xFFD8F3F4),
        iconColor: const Color(0xFF1D9AAF),
      );
    case 'gold':
      return (
        fillColor: const Color(0xFFFFE7B8),
        iconColor: const Color(0xFFDB8A11),
      );
    case 'pink':
      return (
        fillColor: const Color(0xFFF9D6E8),
        iconColor: const Color(0xFFE0539A),
      );
    default:
      return (
        fillColor: const Color(0xFFE8EEF9),
        iconColor: const Color(0xFF5A78C5),
      );
  }
}

IconData _iconForCategoryPresetId(String id) {
  switch (id) {
    case 'plus':
      return Icons.add;
    case 'home':
      return Icons.home_outlined;
    case 'school':
      return Icons.school_outlined;
    case 'camping':
      return Icons.cabin;
    case 'shop':
      return Icons.storefront_outlined;
    case 'briefcase':
      return Icons.work_outline;
    case 'scale':
      return Icons.balance;
    case 'tools':
      return Icons.build_outlined;
    case 'pen':
      return Icons.edit_outlined;
    case 'notes':
      return Icons.note_outlined;
    case 'terminal':
      return Icons.terminal;
    case 'cards':
      return Icons.style_rounded;
    case 'key':
      return Icons.key_outlined;
    case 'crown':
      return Icons.emoji_events_outlined;
    case 'basket':
      return Icons.shopping_bag_outlined;
    case 'building':
      return Icons.account_balance;
    case 'settings':
      return Icons.settings_outlined;
    case 'chat':
      return Icons.chat_bubble_outline;
    case 'quote':
      return Icons.format_quote_outlined;
    case 'gift':
      return Icons.card_giftcard_outlined;
    case 'heart':
      return Icons.favorite_border_rounded;
    case 'star':
      return Icons.star_border_rounded;
    default:
      return Icons.folder_outlined;
  }
}

class _TagSummary {
  const _TagSummary({required this.label, required this.count});

  final String label;
  final int count;
}

class _ItemTypeSummary {
  const _ItemTypeSummary({
    required this.id,
    required this.label,
    required this.count,
    required this.icon,
    required this.iconColor,
    this.imagePath,
  });

  final String id;
  final String label;
  final int count;
  final IconData icon;
  final Color iconColor;
  final String? imagePath;
}
