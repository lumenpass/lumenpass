part of 'vault_screen.dart';

const String _categoryIconNotesPrefix = 'lumenpass-category-icon:';
const int _totalCategoryImages = 392;

bool _isCategoryImagePreset(String presetId) => presetId.startsWith('img:');

String? _categoryImagePathFromPresetId(String presetId) {
  if (!_isCategoryImagePreset(presetId)) return null;
  final n = presetId.substring(4);
  return 'assets/images/categories/$n.png';
}

String? _categoryImagePathForNotes(String? notes) {
  final decoded = _decodeCategoryVisual(notes);
  if (decoded == null) return null;
  return _categoryImagePathFromPresetId(decoded.presetId);
}

class _CategoryIconPreset {
  const _CategoryIconPreset({
    required this.id,
    required this.icon,
    required this.label,
  });

  final String id;
  final IconData icon;
  final String label;
}

class _CategoryColorPreset {
  const _CategoryColorPreset({
    required this.id,
    required this.fillColor,
    required this.iconColor,
  });

  final String id;
  final Color fillColor;
  final Color iconColor;
}

const List<_CategoryIconPreset> _categoryIconPresets = <_CategoryIconPreset>[
  _CategoryIconPreset(id: 'plus', icon: TablerIcons.plus, label: 'Add'),
  _CategoryIconPreset(id: 'home', icon: TablerIcons.home, label: 'Home'),
  _CategoryIconPreset(id: 'school', icon: TablerIcons.school, label: 'School'),
  _CategoryIconPreset(
    id: 'camping',
    icon: TablerIcons.tent,
    label: 'Camping',
  ),
  _CategoryIconPreset(
      id: 'shop', icon: Icons.storefront_rounded, label: 'Shop'),
  _CategoryIconPreset(
    id: 'briefcase',
    icon: TablerIcons.briefcase,
    label: 'Work',
  ),
  _CategoryIconPreset(
    id: 'scale',
    icon: TablerIcons.scale,
    label: 'Legal',
  ),
  _CategoryIconPreset(
    id: 'tools',
    icon: TablerIcons.tool,
    label: 'Tools',
  ),
  _CategoryIconPreset(id: 'pen', icon: TablerIcons.pencil, label: 'Writing'),
  _CategoryIconPreset(id: 'notes', icon: TablerIcons.notes, label: 'Notes'),
  _CategoryIconPreset(
    id: 'terminal',
    icon: TablerIcons.terminal_2,
    label: 'Terminal',
  ),
  _CategoryIconPreset(id: 'cards', icon: Icons.style_rounded, label: 'Cards'),
  _CategoryIconPreset(id: 'key', icon: TablerIcons.key, label: 'Keys'),
  _CategoryIconPreset(id: 'crown', icon: TablerIcons.crown, label: 'VIP'),
  _CategoryIconPreset(
    id: 'basket',
    icon: Icons.shopping_bag_outlined,
    label: 'Cart',
  ),
  _CategoryIconPreset(
    id: 'building',
    icon: TablerIcons.building_bank,
    label: 'Finance',
  ),
  _CategoryIconPreset(
    id: 'settings',
    icon: TablerIcons.settings,
    label: 'Settings',
  ),
  _CategoryIconPreset(
      id: 'chat', icon: TablerIcons.message_circle, label: 'Chat'),
  _CategoryIconPreset(
    id: 'quote',
    icon: TablerIcons.quote,
    label: 'Quotes',
  ),
  _CategoryIconPreset(
      id: 'chart', icon: TablerIcons.chart_bar, label: 'Charts'),
  _CategoryIconPreset(id: 'flask', icon: TablerIcons.flask_2, label: 'Labs'),
  _CategoryIconPreset(id: 'chip', icon: TablerIcons.cpu, label: 'Hardware'),
  _CategoryIconPreset(
    id: 'trees',
    icon: TablerIcons.trees,
    label: 'Nature',
  ),
  _CategoryIconPreset(id: 'dna', icon: TablerIcons.dna_2, label: 'Health'),
  _CategoryIconPreset(id: 'coin', icon: TablerIcons.coin, label: 'Money'),
  _CategoryIconPreset(id: 'gift', icon: TablerIcons.gift, label: 'Gifts'),
  _CategoryIconPreset(id: 'inbox', icon: TablerIcons.inbox, label: 'Inbox'),
  _CategoryIconPreset(id: 'music', icon: TablerIcons.music, label: 'Music'),
  _CategoryIconPreset(
    id: 'pulse',
    icon: TablerIcons.activity_heartbeat,
    label: 'Health',
  ),
  _CategoryIconPreset(
      id: 'palette', icon: TablerIcons.palette, label: 'Design'),
  _CategoryIconPreset(id: 'globe', icon: TablerIcons.world, label: 'World'),
  _CategoryIconPreset(id: 'gem', icon: TablerIcons.diamond, label: 'Gem'),
  _CategoryIconPreset(
    id: 'rook',
    icon: TablerIcons.chess_rook,
    label: 'Strategy',
  ),
  _CategoryIconPreset(id: 'scissors', icon: TablerIcons.cut, label: 'Salon'),
  _CategoryIconPreset(id: 'car', icon: TablerIcons.car, label: 'Car'),
  _CategoryIconPreset(id: 'flame', icon: TablerIcons.flame, label: 'Hot'),
  _CategoryIconPreset(id: 'dice', icon: TablerIcons.dice_5, label: 'Games'),
  _CategoryIconPreset(id: 'sofa', icon: TablerIcons.sofa, label: 'Living'),
  _CategoryIconPreset(id: 'plane', icon: TablerIcons.plane, label: 'Travel'),
  _CategoryIconPreset(
      id: 'shield', icon: TablerIcons.shield_check, label: 'Security'),
  _CategoryIconPreset(id: 'paw', icon: TablerIcons.paw, label: 'Pets'),
  _CategoryIconPreset(
    id: 'planet',
    icon: Icons.travel_explore_rounded,
    label: 'Explore',
  ),
  _CategoryIconPreset(
    id: 'plant',
    icon: TablerIcons.plant_2,
    label: 'Garden',
  ),
  _CategoryIconPreset(
    id: 'vault',
    icon: Icons.inventory_2_rounded,
    label: 'Vault',
  ),
  _CategoryIconPreset(id: 'door', icon: TablerIcons.door, label: 'Access'),
  _CategoryIconPreset(id: 'wave', icon: TablerIcons.wave_sine, label: 'Flow'),
  _CategoryIconPreset(id: 'donut', icon: TablerIcons.cookie, label: 'Treats'),
];

const List<_CategoryColorPreset> _categoryColorPresets = <_CategoryColorPreset>[
  _CategoryColorPreset(
    id: 'blue',
    fillColor: Color(0xFFE1EDFF),
    iconColor: Color(0xFF2B7FFF),
  ),
  _CategoryColorPreset(
    id: 'purple',
    fillColor: Color(0xFFEEDDFB),
    iconColor: Color(0xFF8D57B0),
  ),
  _CategoryColorPreset(
    id: 'teal',
    fillColor: Color(0xFFD8F3F4),
    iconColor: Color(0xFF1D9AAF),
  ),
  _CategoryColorPreset(
    id: 'gold',
    fillColor: Color(0xFFFFE7B8),
    iconColor: Color(0xFFDB8A11),
  ),
  _CategoryColorPreset(
    id: 'pink',
    fillColor: Color(0xFFF9D6E8),
    iconColor: Color(0xFFE0539A),
  ),
];

const Color _createCategoryButtonColor = Color(0xFF1D9AAF);

_CategoryIconPreset _categoryPresetById(String id) {
  return _categoryIconPresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => _categoryIconPresets[0],
  );
}

_CategoryColorPreset _categoryColorById(String id) {
  return _categoryColorPresets.firstWhere(
    (color) => color.id == id,
    orElse: () => _categoryColorPresets[0],
  );
}

({String presetId, String colorId})? _decodeCategoryVisual(String? notes) {
  final raw = notes?.trim() ?? '';
  if (!raw.startsWith(_categoryIconNotesPrefix)) {
    return null;
  }

  final payload = raw.substring(_categoryIconNotesPrefix.length);
  final parts = payload.split('|');
  if (parts.length != 2 || parts.any((part) => part.trim().isEmpty)) {
    return null;
  }

  return (presetId: parts[0], colorId: parts[1]);
}

String _encodeCategoryVisual({
  required String presetId,
  required String colorId,
}) {
  return '$_categoryIconNotesPrefix$presetId|$colorId';
}

({IconData icon, Color iconColor, Color badgeColor}) _categoryVisualForNotes(
  String? notes,
) {
  final decoded = _decodeCategoryVisual(notes);
  if (decoded == null) {
    return (
      icon: TablerIcons.folder,
      iconColor: const Color(0xFF5A78C5),
      badgeColor: const Color(0xFFE8EEF9),
    );
  }

  if (_isCategoryImagePreset(decoded.presetId)) {
    return (
      icon: TablerIcons.folder,
      iconColor: const Color(0xFF5A78C5),
      badgeColor: const Color(0xFFE8EEF9),
    );
  }

  final preset = _categoryPresetById(decoded.presetId);
  final color = _categoryColorById(decoded.colorId);
  return (
    icon: preset.icon,
    iconColor: color.iconColor,
    badgeColor: color.fillColor,
  );
}

class _AddCategoryOverlay extends ConsumerStatefulWidget {
  const _AddCategoryOverlay({
    required this.onClose,
    required this.onShowToast,
    required this.onCategoryCreated,
  });

  final VoidCallback onClose;
  final ValueChanged<String> onShowToast;
  final Future<void> Function(String groupUuid) onCategoryCreated;

  @override
  ConsumerState<_AddCategoryOverlay> createState() =>
      _AddCategoryOverlayState();
}

class _AddCategoryOverlayState extends ConsumerState<_AddCategoryOverlay> {
  late final TextEditingController _nameController;
  String _selectedPresetId = 'img:1';
  String _selectedColorId = 'teal';
  String? _errorText;
  bool _isSaving = false;
  bool _showIconPicker = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = _categoryImagePathFromPresetId(_selectedPresetId);
    final showImage = imagePath != null;
    final preset = showImage
        ? _categoryPresetById('briefcase')
        : _categoryPresetById(_selectedPresetId);
    final color = _categoryColorById(_selectedColorId);

    return GestureDetector(
      onTap: _isSaving ? null : widget.onClose,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: const Color(0x52000000),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final modalWidth = math.min(720.0, constraints.maxWidth);
                final modalMaxHeight = math.min(620.0, constraints.maxHeight);

                return Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: Stack(
                      children: <Widget>[
                        Container(
                          constraints: BoxConstraints(
                            maxWidth: modalWidth,
                            maxHeight: modalMaxHeight,
                          ),
                          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDFDFE),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFFD9E1EB)),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x1C172033),
                                blurRadius: 44,
                                offset: Offset(0, 20),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  const SizedBox(width: 30, height: 30),
                                  Expanded(
                                    child: Text(
                                      'Add Category',
                                      textAlign: TextAlign.center,
                                      style: _text(
                                        22,
                                        const Color(0xFF243247),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  _ModalIconAction(
                                    icon: TablerIcons.x,
                                    onTap: _isSaving ? () {} : widget.onClose,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Flexible(
                                fit: FlexFit.loose,
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Container(
                                        width: 148,
                                        height: 148,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: <Widget>[
                                            Align(
                                              alignment: Alignment.center,
                                              child: showImage
                                                  ? ClipOval(
                                                      child: Image.asset(
                                                        imagePath,
                                                        width: 124,
                                                        height: 124,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    )
                                                  : Container(
                                                      width: 124,
                                                      height: 124,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        gradient:
                                                            LinearGradient(
                                                          begin:
                                                              Alignment.topLeft,
                                                          end: Alignment
                                                              .bottomRight,
                                                          colors: <Color>[
                                                            color.fillColor,
                                                            color.fillColor
                                                                .withValues(
                                                              alpha: 0.88,
                                                            ),
                                                          ],
                                                        ),
                                                        boxShadow: <BoxShadow>[
                                                          BoxShadow(
                                                            color: color
                                                                .fillColor
                                                                .withValues(
                                                              alpha: 0.9,
                                                            ),
                                                            blurRadius: 28,
                                                            offset:
                                                                const Offset(
                                                              0,
                                                              14,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      alignment:
                                                          Alignment.center,
                                                      child: Icon(
                                                        preset.icon,
                                                        size: 52,
                                                        color: color.iconColor,
                                                      ),
                                                    ),
                                            ),
                                            Positioned(
                                              right: 10,
                                              bottom: 6,
                                              child: InkWell(
                                                onTap: _isSaving
                                                    ? null
                                                    : () {
                                                        setState(() {
                                                          _showIconPicker =
                                                              !_showIconPicker;
                                                        });
                                                      },
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                child: Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFFD9E2EF,
                                                      ),
                                                    ),
                                                    boxShadow: const <BoxShadow>[
                                                      BoxShadow(
                                                        color:
                                                            Color(0x18172033),
                                                        blurRadius: 18,
                                                        offset: Offset(
                                                          0,
                                                          8,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Icon(
                                                    _showIconPicker
                                                        ? TablerIcons.chevron_up
                                                        : TablerIcons
                                                            .chevron_down,
                                                    size: 18,
                                                    color: const Color(
                                                      0xFF5F6F84,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          14,
                                          16,
                                          16,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          border: Border.all(
                                            color: const Color(0xFFE0E7F1),
                                          ),
                                        ),
                                        child: Column(
                                          children: <Widget>[
                                            _CategoryNameField(
                                              controller: _nameController,
                                              errorText: _errorText,
                                              enabled: !_isSaving,
                                              accentColor: color.iconColor,
                                              onSubmitted: (_) =>
                                                  _saveCategory(),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: <Widget>[
                                  _LoginFooterButton(
                                    label: 'Cancel',
                                    backgroundColor: const Color(0xFFF4F6FA),
                                    textColor: const Color(0xFF374151),
                                    onTap: _isSaving ? null : widget.onClose,
                                  ),
                                  const SizedBox(width: 10),
                                  _LoginFooterButton(
                                    label: _isSaving
                                        ? 'Creating...'
                                        : 'Create Category',
                                    backgroundColor: _createCategoryButtonColor,
                                    textColor: Colors.white,
                                    onTap: _isSaving ? null : _saveCategory,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (_showIconPicker)
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: _closeIconPicker,
                              child: Container(
                                color: const Color(0x260F172A),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(20),
                                child: GestureDetector(
                                  onTap: () {},
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: math.min(
                                        620.0,
                                        math.max(320.0, modalWidth - 32),
                                      ),
                                      maxHeight: math.min(
                                        520.0,
                                        math.max(360.0, modalMaxHeight - 56),
                                      ),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: _CategoryIconPickerMenu(
                                        selectedPresetId: _selectedPresetId,
                                        enabled: !_isSaving,
                                        onPresetSelected: (presetId) {
                                          setState(() {
                                            _selectedPresetId = presetId;
                                          });
                                        },
                                        onClose: _closeIconPicker,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _closeIconPicker() {
    if (!_showIconPicker) {
      return;
    }
    setState(() {
      _showIconPicker = false;
    });
  }

  Future<void> _saveCategory() async {
    final name = _nameController.text.trim();
    final existingCategories = ref.read(vaultSidebarCategoriesProvider);
    final duplicateExists = existingCategories.any(
      (category) => category.name.toLowerCase() == name.toLowerCase(),
    );

    if (name.isEmpty) {
      setState(() {
        _errorText = 'Category name is required.';
      });
      return;
    }

    if (duplicateExists) {
      setState(() {
        _errorText = 'That category already exists.';
      });
      return;
    }

    final repository = ref.read(kdbxRepositoryProvider);
    final rootGroupUuid = repository.rootGroupUuid;
    if (rootGroupUuid == null) {
      widget.onShowToast('Open a vault before adding categories');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
      _showIconPicker = false;
    });

    try {
      final groupUuid = await repository.createGroup(
        parentGroupUuid: rootGroupUuid,
        name: name,
        notes: _encodeCategoryVisual(
          presetId: _selectedPresetId,
          colorId: _selectedColorId,
        ),
      );
      final database = await saveAndSyncDatabase(
          repository, ref.read(databaseRegistryProvider));
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultSidebarCategoriesProvider);
      widget.onShowToast('$name category created');
      await widget.onCategoryCreated(groupUuid);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      widget.onShowToast('Unable to create category: $error');
    }
  }
}

class _EditCategoryOverlay extends ConsumerStatefulWidget {
  const _EditCategoryOverlay({
    required this.category,
    required this.onClose,
    required this.onShowToast,
    required this.onCategoryUpdated,
  });

  final ({String uuid, String name, String notes, int count}) category;
  final VoidCallback onClose;
  final ValueChanged<String> onShowToast;
  final Future<void> Function(String groupUuid) onCategoryUpdated;

  @override
  ConsumerState<_EditCategoryOverlay> createState() =>
      _EditCategoryOverlayState();
}

class _EditCategoryOverlayState extends ConsumerState<_EditCategoryOverlay> {
  late final TextEditingController _nameController;
  late String _selectedPresetId;
  late String _selectedColorId;
  String? _errorText;
  bool _isSaving = false;
  bool _showIconPicker = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    final decoded = _decodeCategoryVisual(widget.category.notes);
    _selectedPresetId = decoded?.presetId ?? 'img:1';
    _selectedColorId = decoded?.colorId ?? 'teal';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = _categoryImagePathFromPresetId(_selectedPresetId);
    final showImage = imagePath != null;
    final preset = showImage
        ? _categoryPresetById('briefcase')
        : _categoryPresetById(_selectedPresetId);
    final color = _categoryColorById(_selectedColorId);

    return GestureDetector(
      onTap: _isSaving ? null : widget.onClose,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            color: const Color(0x52000000),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final modalWidth = math.min(720.0, constraints.maxWidth);
                final modalMaxHeight = math.min(620.0, constraints.maxHeight);

                return Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: Stack(
                      children: <Widget>[
                        Container(
                          constraints: BoxConstraints(
                            maxWidth: modalWidth,
                            maxHeight: modalMaxHeight,
                          ),
                          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDFDFE),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFFD9E1EB)),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x1C172033),
                                blurRadius: 44,
                                offset: Offset(0, 20),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  const SizedBox(width: 30, height: 30),
                                  Expanded(
                                    child: Text(
                                      'Edit Category',
                                      textAlign: TextAlign.center,
                                      style: _text(
                                        22,
                                        const Color(0xFF243247),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  _ModalIconAction(
                                    icon: TablerIcons.x,
                                    onTap: _isSaving ? () {} : widget.onClose,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Flexible(
                                fit: FlexFit.loose,
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      SizedBox(
                                        width: 148,
                                        height: 148,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: <Widget>[
                                            Align(
                                              alignment: Alignment.center,
                                              child: showImage
                                                  ? ClipOval(
                                                      child: Image.asset(
                                                        imagePath,
                                                        width: 124,
                                                        height: 124,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    )
                                                  : Container(
                                                      width: 124,
                                                      height: 124,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        gradient:
                                                            LinearGradient(
                                                          begin:
                                                              Alignment.topLeft,
                                                          end: Alignment
                                                              .bottomRight,
                                                          colors: <Color>[
                                                            color.fillColor,
                                                            color.fillColor
                                                                .withValues(
                                                              alpha: 0.88,
                                                            ),
                                                          ],
                                                        ),
                                                        boxShadow: <BoxShadow>[
                                                          BoxShadow(
                                                            color: color
                                                                .fillColor
                                                                .withValues(
                                                              alpha: 0.9,
                                                            ),
                                                            blurRadius: 28,
                                                            offset:
                                                                const Offset(
                                                              0,
                                                              14,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      alignment:
                                                          Alignment.center,
                                                      child: Icon(
                                                        preset.icon,
                                                        size: 52,
                                                        color: color.iconColor,
                                                      ),
                                                    ),
                                            ),
                                            Positioned(
                                              right: 10,
                                              bottom: 6,
                                              child: InkWell(
                                                onTap: _isSaving
                                                    ? null
                                                    : () {
                                                        setState(() {
                                                          _showIconPicker =
                                                              !_showIconPicker;
                                                        });
                                                      },
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                child: Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFFD9E2EF,
                                                      ),
                                                    ),
                                                    boxShadow: const <BoxShadow>[
                                                      BoxShadow(
                                                        color:
                                                            Color(0x18172033),
                                                        blurRadius: 18,
                                                        offset: Offset(0, 8),
                                                      ),
                                                    ],
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Icon(
                                                    _showIconPicker
                                                        ? TablerIcons.chevron_up
                                                        : TablerIcons
                                                            .chevron_down,
                                                    size: 18,
                                                    color:
                                                        const Color(0xFF5F6F84),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 14, 16, 16),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          border: Border.all(
                                            color: const Color(0xFFE0E7F1),
                                          ),
                                        ),
                                        child: _CategoryNameField(
                                          controller: _nameController,
                                          errorText: _errorText,
                                          enabled: !_isSaving,
                                          accentColor: color.iconColor,
                                          onSubmitted: (_) => _saveCategory(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: <Widget>[
                                  _LoginFooterButton(
                                    label: 'Cancel',
                                    backgroundColor: const Color(0xFFF4F6FA),
                                    textColor: const Color(0xFF374151),
                                    onTap: _isSaving ? null : widget.onClose,
                                  ),
                                  const SizedBox(width: 10),
                                  _LoginFooterButton(
                                    label: _isSaving
                                        ? 'Saving...'
                                        : 'Save Changes',
                                    backgroundColor: _createCategoryButtonColor,
                                    textColor: Colors.white,
                                    onTap: _isSaving ? null : _saveCategory,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (_showIconPicker)
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: _closeIconPicker,
                              child: Container(
                                color: const Color(0x260F172A),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.all(20),
                                child: GestureDetector(
                                  onTap: () {},
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: math.min(
                                        620.0,
                                        math.max(320.0, modalWidth - 32),
                                      ),
                                      maxHeight: math.min(
                                        520.0,
                                        math.max(360.0, modalMaxHeight - 56),
                                      ),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: _CategoryIconPickerMenu(
                                        selectedPresetId: _selectedPresetId,
                                        enabled: !_isSaving,
                                        onPresetSelected: (presetId) {
                                          setState(() {
                                            _selectedPresetId = presetId;
                                          });
                                        },
                                        onClose: _closeIconPicker,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _closeIconPicker() {
    if (!_showIconPicker) return;
    setState(() => _showIconPicker = false);
  }

  Future<void> _saveCategory() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _errorText = 'Category name is required.';
      });
      return;
    }

    final existingCategories = ref.read(vaultSidebarCategoriesProvider);
    final duplicateExists = existingCategories.any(
      (category) =>
          category.uuid != widget.category.uuid &&
          category.name.toLowerCase() == name.toLowerCase(),
    );

    if (duplicateExists) {
      setState(() {
        _errorText = 'That category already exists.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
      _showIconPicker = false;
    });

    try {
      final repository = ref.read(kdbxRepositoryProvider);
      await repository.updateGroup(
        groupUuid: widget.category.uuid,
        name: name,
        notes: _encodeCategoryVisual(
          presetId: _selectedPresetId,
          colorId: _selectedColorId,
        ),
      );
      final database = await saveAndSyncDatabase(
          repository, ref.read(databaseRegistryProvider));
      ref.read(activeDatabaseProvider.notifier).state = database;
      ref.invalidate(vaultSidebarCategoriesProvider);
      widget.onShowToast('$name category updated');
      await widget.onCategoryUpdated(widget.category.uuid);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      widget.onShowToast('Unable to update category: $error');
    }
  }
}

class _CategoryIconPickerMenu extends StatelessWidget {
  const _CategoryIconPickerMenu({
    required this.selectedPresetId,
    required this.enabled,
    required this.onPresetSelected,
    required this.onClose,
  });

  final String selectedPresetId;
  final bool enabled;
  final ValueChanged<String> onPresetSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 520),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE5F0)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x24172033),
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Choose icon',
                  style: _text(
                    14,
                    const Color(0xFF243247),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _ModalIconAction(
                icon: TablerIcons.x,
                onTap: onClose,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 9,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
              ),
              itemCount: _totalCategoryImages,
              itemBuilder: (context, index) {
                final n = index + 1;
                final presetId = 'img:$n';
                return _CategoryImageTile(
                  imagePath: 'assets/images/categories/$n.png',
                  presetId: presetId,
                  selected: presetId == selectedPresetId,
                  enabled: enabled,
                  onTap: () => onPresetSelected(presetId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryImageTile extends StatefulWidget {
  const _CategoryImageTile({
    required this.imagePath,
    required this.presetId,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String imagePath;
  final String presetId;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_CategoryImageTile> createState() => _CategoryImageTileState();
}

class _CategoryImageTileState extends State<_CategoryImageTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selected;
    final isHovered = _hovered && widget.enabled;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x402B7FFF),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ]
                : isHovered
                    ? const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : const <BoxShadow>[],
          ),
          child: Stack(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  widget.imagePath,
                  fit: BoxFit.cover,
                ),
              ),
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF2B7FFF),
                      width: 2.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryNameField extends StatelessWidget {
  const _CategoryNameField({
    required this.controller,
    required this.errorText,
    required this.enabled,
    required this.accentColor,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool enabled;
  final Color accentColor;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Category name',
          style: _text(
            12,
            const Color(0xFF475467),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: errorText != null
                  ? const Color(0xFFE5484D)
                  : accentColor.withValues(alpha: 0.45),
              width: errorText != null ? 1.4 : 2.4,
            ),
          ),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: controller,
            enabled: enabled,
            onSubmitted: onSubmitted,
            style: _text(
              16,
              const Color(0xFF101828),
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Personal, Work, Travel...',
              hintStyle: _text(
                15,
                const Color(0xFF98A2B3),
                fontWeight: FontWeight.w500,
              ),
              filled: false,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (errorText != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            errorText!,
            style: _text(
              12,
              const Color(0xFFE5484D),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryPresetTile extends StatefulWidget {
  const _CategoryPresetTile({
    required this.preset,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _CategoryIconPreset preset;
  final _CategoryColorPreset color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_CategoryPresetTile> createState() => _CategoryPresetTileState();
}

class _CategoryPresetTileState extends State<_CategoryPresetTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isInteractive = widget.enabled;
    final isSelected = widget.selected;
    final isHovered = _hovered && isInteractive;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: isInteractive ? widget.onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.fillColor,
            border: Border.all(
              color: isSelected
                  ? widget.color.iconColor
                  : isHovered
                      ? widget.color.iconColor.withValues(alpha: 0.45)
                      : Colors.transparent,
              width: isSelected ? 3 : 2,
            ),
            boxShadow: isSelected
                ? <BoxShadow>[
                    BoxShadow(
                      color: widget.color.fillColor.withValues(alpha: 0.95),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.preset.icon,
            size: 28,
            color: widget.color.iconColor,
          ),
        ),
      ),
    );
  }
}

class _CategoryColorSwatch extends StatefulWidget {
  const _CategoryColorSwatch({
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _CategoryColorPreset color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_CategoryColorSwatch> createState() => _CategoryColorSwatchState();
}

class _CategoryColorSwatchState extends State<_CategoryColorSwatch> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isHovered = _hovered && widget.enabled;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.enabled ? widget.onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.fillColor,
            border: Border.all(
              color: widget.selected
                  ? widget.color.iconColor
                  : isHovered
                      ? widget.color.iconColor.withValues(alpha: 0.4)
                      : Colors.transparent,
              width: widget.selected ? 3 : 2,
            ),
          ),
          child: widget.selected
              ? Icon(
                  TablerIcons.check,
                  size: 20,
                  color: widget.color.iconColor,
                )
              : null,
        ),
      ),
    );
  }
}
