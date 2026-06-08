class DockIconOption {
  const DockIconOption({
    required this.label,
    required this.assetPath,
    this.caption,
  });

  final String label;
  final String assetPath;
  final String? caption;
}

const String dockIconPreferenceKey = 'appearance.dockIconAsset';
const String dockIconDefaultAsset = 'assets/images/tray_icon.png';

const List<DockIconOption> dockIconOptions = <DockIconOption>[
  DockIconOption(
    label: 'Default',
    assetPath: dockIconDefaultAsset,
    caption: 'Current white icon',
  ),
  DockIconOption(
    label: 'Lock 1',
    assetPath: 'assets/images/lock_icons/lock-64.png',
  ),
  DockIconOption(
    label: 'Lock 2',
    assetPath: 'assets/images/lock_icons/lock-64-2.png',
  ),
  DockIconOption(
    label: 'Lock 3',
    assetPath: 'assets/images/lock_icons/lock-64-3.png',
  ),
  DockIconOption(
    label: 'Lock 4',
    assetPath: 'assets/images/lock_icons/lock-64-4.png',
  ),
  DockIconOption(
    label: 'Lock 5',
    assetPath: 'assets/images/lock_icons/lock-64-5.png',
  ),
  DockIconOption(
    label: 'Lock 6',
    assetPath: 'assets/images/lock_icons/lock-64-6.png',
  ),
];
