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
                color: const Color(0x66000000),
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
    final modalHeight = math.min(540.0, constraints.maxHeight);
    final visibleNewItemTypes = _allNewItemTypes
        .where((item) => !_hiddenAddItemTypeIds.contains(item.id))
        .toList(growable: false);

    return Container(
      width: modalWidth,
      constraints: BoxConstraints(maxHeight: modalHeight),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      decoration: BoxDecoration(
        color: _VaultColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _VaultColors.borderPane),
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
              Expanded(
                child: Text(
                  'Add an item',
                  style: _displayText(21, _VaultColors.title),
                ),
              ),
              _ModalIconAction(
                icon: TablerIcons.x,
                onTap: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: _VaultColors.borderSoft),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'ITEM TYPE',
                    style: _text(
                      10,
                      _VaultColors.headerLabel,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, gridConstraints) {
                      final columns = gridConstraints.maxWidth < 460 ? 1 : 2;
                      return Column(
                        children: <Widget>[
                          for (var index = 0;
                              index < visibleNewItemTypes.length;
                              index += columns) ...<Widget>[
                            Row(
                              children: <Widget>[
                                for (var column = 0;
                                    column < columns;
                                    column++) ...<Widget>[
                                  if (column > 0) const SizedBox(width: 10),
                                  Expanded(
                                    child: index + column <
                                            visibleNewItemTypes.length
                                        ? _NewItemTypeRow(
                                            option: visibleNewItemTypes[
                                                index + column],
                                            onTap: () => _handleSelectType(
                                              visibleNewItemTypes[
                                                  index + column],
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ],
                            ),
                            if (index + columns < visibleNewItemTypes.length)
                              const SizedBox(height: 10),
                          ],
                        ],
                      );
                    },
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
