import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

const _kInk = Color(0xFF0A3B48);
const _kMuted = Color(0xFF6B858D);
const _kBorder = Color(0xFFE3EAF0);
const _kAccent = Color(0xFF4B6CFF);
const _kOrange = Color(0xFFFF9800);
const _kOrangeBg = Color(0xFFFFF3E0);
const _kGreen = Color(0xFF22C55E);
const _kSurface = Colors.white;
const double _kPlanColumnWidth = 64;

void showPlanFeaturesModal(BuildContext context) {
  showGeneralDialog<void>(
    context: context,
    barrierLabel: 'Plans & Features',
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim, secondary) => const _PlanFeaturesDialog(),
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _PlanFeature {
  const _PlanFeature({
    required this.label,
    required this.category,
    required this.free,
    required this.premium,
  });

  final String label;
  final String category;
  final Object free;
  final Object premium;
}

const List<String> _kCategories = <String>[
  'Vaults',
  'Devices',
  'Security',
  'Automatic Backup',
  'Cloud Storage',
  'Updates',
  'Early access features',
  'Support',
];

const List<_PlanFeature> _kFeatures = <_PlanFeature>[
  _PlanFeature(
    label: 'Vault / Database',
    category: 'Vaults',
    free: '1',
    premium: 'Unlimited',
  ),
  _PlanFeature(
    label: 'Unlimited Items',
    category: 'Vaults',
    free: true,
    premium: true,
  ),
  _PlanFeature(label: 'Passkey', category: 'Vaults', free: true, premium: true),
  _PlanFeature(label: 'TOTP', category: 'Vaults', free: true, premium: true),
  _PlanFeature(
    label: 'Login Item',
    category: 'Vaults',
    free: true,
    premium: true,
  ),
  _PlanFeature(label: 'Note', category: 'Vaults', free: true, premium: true),
  _PlanFeature(
    label: 'SSH Keys',
    category: 'Vaults',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'Secure Notes',
    category: 'Vaults',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'Identity',
    category: 'Vaults',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'Bank Account',
    category: 'Vaults',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'Credit Cards',
    category: 'Vaults',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'Categories',
    category: 'Vaults',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'SSH Agent',
    category: 'Vaults',
    free: false,
    premium: true,
  ),

  _PlanFeature(label: 'macOS', category: 'Devices', free: true, premium: true),
  _PlanFeature(
    label: 'Windows',
    category: 'Devices',
    free: true,
    premium: true,
  ),
  _PlanFeature(label: 'Linux', category: 'Devices', free: true, premium: true),
  _PlanFeature(label: 'iOS', category: 'Devices', free: true, premium: true),
  _PlanFeature(
    label: 'Android',
    category: 'Devices',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'Browser Extension',
    category: 'Devices',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'Firefox',
    category: 'Devices',
    free: true,
    premium: true,
  ),
  _PlanFeature(label: 'Edge', category: 'Devices', free: true, premium: true),
  _PlanFeature(label: 'Safari', category: 'Devices', free: true, premium: true),

  _PlanFeature(
    label: 'Master Password Unlock',
    category: 'Security',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'PIN Unlock',
    category: 'Security',
    free: false,
    premium: true,
  ),
  _PlanFeature(
    label: 'Biometric Unlock',
    category: 'Security',
    free: false,
    premium: true,
  ),

  _PlanFeature(
    label: 'Automatic Backup',
    category: 'Automatic Backup',
    free: true,
    premium: true,
  ),

  _PlanFeature(
    label: 'Local Database',
    category: 'Cloud Storage',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'GoogleDrive',
    category: 'Cloud Storage',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'Dropbox',
    category: 'Cloud Storage',
    free: true,
    premium: true,
  ),
  _PlanFeature(
    label: 'OneDrive',
    category: 'Cloud Storage',
    free: false,
    premium: true,
  ),
  _PlanFeature(
    label: 'WebDav',
    category: 'Cloud Storage',
    free: false,
    premium: true,
  ),
  _PlanFeature(
    label: 'SFTP',
    category: 'Cloud Storage',
    free: false,
    premium: true,
  ),
  _PlanFeature(
    label: 'S3 Storage / Compatibility',
    category: 'Cloud Storage',
    free: false,
    premium: true,
  ),

  _PlanFeature(
    label: 'Update to newer version/build',
    category: 'Updates',
    free: true,
    premium: true,
  ),

  _PlanFeature(
    label: 'New feature development in the future',
    category: 'Early access features',
    free: false,
    premium: true,
  ),

  _PlanFeature(
    label: 'Get support by the staff',
    category: 'Support',
    free: false,
    premium: true,
  ),
];

class _PlanFeaturesDialog extends StatelessWidget {
  const _PlanFeaturesDialog();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width < 520 ? media.size.width - 24 : 500.0;
    final maxHeight = media.size.height * 0.85;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  const Icon(
                    TablerIcons.list_details,
                    size: 20,
                    color: _kAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Plans & Features',
                      style: const TextStyle(
                        color: _kInk,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: _kMuted,
                    ),
                    tooltip: 'Close',
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _kBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Feature',
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  _ColumnHeader(label: 'Free', color: _kMuted),
                  const SizedBox(width: 4),
                  _PremiumColumnHeader(),
                ],
              ),
            ),
            const Divider(height: 1, color: _kBorder),
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 16),
                itemCount: _kCategories.length,
                itemBuilder: (context, index) {
                  final cat = _kCategories[index];
                  final features = _kFeatures
                      .where((f) => f.category == cat)
                      .toList();
                  return _CategorySection(category: cat, features: features);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kPlanColumnWidth,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.category, required this.features});
  final String category;
  final List<_PlanFeature> features;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            category.toUpperCase(),
            style: const TextStyle(
              color: _kMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        ...features.map((f) => _FeatureRow(feature: f)),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature});
  final _PlanFeature feature;

  bool get _isPremiumOnly => feature.free == false || feature.free == '0';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      constraints: const BoxConstraints(minHeight: 38),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: _isPremiumOnly ? 6 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    feature.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_isPremiumOnly) ...[
                    const SizedBox(height: 3),
                    const _PremiumTag(),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(
            width: _kPlanColumnWidth,
            child: _ValueCell(value: feature.free, isPremiumColumn: false),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: _kPlanColumnWidth,
            child: _ValueCell(value: feature.premium, isPremiumColumn: true),
          ),
        ],
      ),
    );
  }
}

class _PremiumColumnHeader extends StatelessWidget {
  const _PremiumColumnHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kPlanColumnWidth,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: _kOrangeBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded, size: 10, color: _kOrange),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              'Premium',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _kOrange,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumTag extends StatelessWidget {
  const _PremiumTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _kOrangeBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'PREMIUM',
        style: TextStyle(
          color: _kOrange,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  const _ValueCell({required this.value, this.isPremiumColumn = false});
  final Object value;
  final bool isPremiumColumn;

  @override
  Widget build(BuildContext context) {
    if (value is bool) {
      if (value == true) {
        return Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: isPremiumColumn ? _kOrange : _kGreen,
        );
      }
      return const Icon(
        Icons.remove_rounded,
        size: 18,
        color: Color(0xFFCBD5DA),
      );
    }
    return Text(
      value.toString(),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: _kInk, fontSize: 12, fontWeight: FontWeight.w600),
    );
  }
}
