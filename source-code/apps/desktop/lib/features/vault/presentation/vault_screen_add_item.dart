part of 'vault_screen.dart';

const Set<String> _hiddenAddItemTypeIds = <String>{
  'document',
  'api-credential',
  'server',
  'wifi-password',
  'passport',
};

class _AddNewItemOverlay extends ConsumerStatefulWidget {
  const _AddNewItemOverlay({
    required this.onClose,
    required this.onShowToast,
    required this.onItemCreated,
  });

  final VoidCallback onClose;
  final ValueChanged<String> onShowToast;
  final ValueChanged<String> onItemCreated;

  @override
  ConsumerState<_AddNewItemOverlay> createState() => _AddNewItemOverlayState();
}

enum _AddItemModalView {
  picker,
  login,
  secureNote,
  creditCard,
  bankAccount,
  identity,
  sshKey,
}

enum _CreditCardSectionKind {
  primary,
  contact,
  additional,
}

class _AddNewItemOverlayState extends ConsumerState<_AddNewItemOverlay> {
  _AddItemModalView _view = _AddItemModalView.picker;
  String _selectedTypeId = _allNewItemTypes.first.id;

  void _returnToPicker() {
    setState(() {
      _view = _AddItemModalView.picker;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      autofocus: true,
      child: FocusTraversalGroup(
        child: GestureDetector(
          onTap: widget.onClose,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: const Color(0x52000000),
                alignment: Alignment.center,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: GestureDetector(
                  onTap: () {},
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      switch (_view) {
                        case _AddItemModalView.picker:
                          return _buildTypePickerModal(constraints);
                        case _AddItemModalView.login:
                          return _AddLoginItemModal(
                            onClose: widget.onClose,
                            onShowToast: widget.onShowToast,
                            onItemSaved: widget.onItemCreated,
                            onReturnToPicker: _returnToPicker,
                          );
                        case _AddItemModalView.secureNote:
                          return _AddSecureNoteItemModal(
                            onClose: widget.onClose,
                            onShowToast: widget.onShowToast,
                            onItemSaved: widget.onItemCreated,
                            onReturnToPicker: _returnToPicker,
                          );
                        case _AddItemModalView.creditCard:
                          return _AddCreditCardItemModal(
                            onClose: widget.onClose,
                            onShowToast: widget.onShowToast,
                            onItemSaved: widget.onItemCreated,
                            onReturnToPicker: _returnToPicker,
                          );
                        case _AddItemModalView.bankAccount:
                          return _AddBankAccountItemModal(
                            onClose: widget.onClose,
                            onShowToast: widget.onShowToast,
                            onItemSaved: widget.onItemCreated,
                            onReturnToPicker: _returnToPicker,
                          );
                        case _AddItemModalView.identity:
                          return _AddIdentityItemModal(
                            onClose: widget.onClose,
                            onShowToast: widget.onShowToast,
                            onItemSaved: widget.onItemCreated,
                            onReturnToPicker: _returnToPicker,
                          );
                        case _AddItemModalView.sshKey:
                          return _AddSshKeyItemModal(
                            onClose: widget.onClose,
                            onShowToast: widget.onShowToast,
                            onItemSaved: widget.onItemCreated,
                            onReturnToPicker: _returnToPicker,
                          );
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSelectType(_NewItemType option) {
    setState(() {
      _selectedTypeId = option.id;
      if (option.id == 'login') {
        _view = _AddItemModalView.login;
      } else if (option.id == 'secure-note') {
        _view = _AddItemModalView.secureNote;
      } else if (option.id == 'credit-card') {
        _view = _AddItemModalView.creditCard;
      } else if (option.id == 'bank-account') {
        _view = _AddItemModalView.bankAccount;
      } else if (option.id == 'identity') {
        _view = _AddItemModalView.identity;
      } else if (option.id == 'ssh-key') {
        _view = _AddItemModalView.sshKey;
      }
    });

    if (option.id != 'login' &&
        option.id != 'secure-note' &&
        option.id != 'credit-card' &&
        option.id != 'bank-account' &&
        option.id != 'identity' &&
        option.id != 'ssh-key') {
      widget.onShowToast('${option.label} editor is not implemented yet');
    }
  }

  Widget _buildTypePickerModal(BoxConstraints constraints) {
    final modalWidth = math.min(680.0, constraints.maxWidth);
    final modalHeight = math.min(772.0, constraints.maxHeight);
    final visibleNewItemTypes = _allNewItemTypes
        .where((item) => !_hiddenAddItemTypeIds.contains(item.id))
        .toList(growable: false);

    return Container(
      width: modalWidth,
      constraints: BoxConstraints(maxHeight: modalHeight),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDADFE8)),
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
              const SizedBox(width: 24, height: 24),
              Expanded(
                child: Text(
                  'What would you like to add?',
                  textAlign: TextAlign.center,
                  style: _text(
                    18,
                    const Color(0xFF2E3138),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(
                    TablerIcons.x,
                    size: 18,
                    color: Color(0xFF6E7687),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'All item types',
                    style: _text(
                      10,
                      const Color(0xFF5F6878),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: visibleNewItemTypes
                        .map(
                          (option) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _NewItemTypeRow(
                              option: option,
                              selected: option.id == _selectedTypeId,
                              onTap: () => _handleSelectType(option),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 1,
                    color: const Color(0xFFE2E6EE),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFE1E7F0),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            TablerIcons.info_circle,
                            size: 16,
                            color: Color(0xFF6B7A90),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Choose the item type that best matches what you want to store, so your vault stays organized and easier to search later.',
                            style: _text(
                              11,
                              const Color(0xFF667085),
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
