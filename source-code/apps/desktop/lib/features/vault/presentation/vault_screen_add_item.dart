part of 'vault_screen.dart';

/// Light surfaces used only by add/edit-item dialogs, not the vault workspace.
abstract final class _ItemModalColors {
  static const Color surface = DcColors.lightSurface;
  static const Color surfaceMuted = DcColors.lightInset;
  static const Color peach = DcColors.sidebarHover;
  static const Color peachSoft = DcColors.lightSelectionFill;
  static const Color title = DcColors.sidebarText;
  static const Color headerLabel = DcColors.sidebarMuted;
  static const Color icon = DcColors.sidebarMuted;
  static const Color borderSoft = DcColors.sidebarLine;
  static const Color borderPane = DcColors.lightLineStrong;
}

const Set<String> _hiddenAddItemTypeIds = <String>{
  'document',
  'api-credential',
  'server',
  'wifi-password',
  'passport',
};

class AddNewItemOverlay extends ConsumerStatefulWidget {
  const AddNewItemOverlay({
    required this.onClose,
    required this.onShowToast,
    required this.onItemCreated,
  });

  final VoidCallback onClose;
  final ValueChanged<String> onShowToast;
  final ValueChanged<String> onItemCreated;

  @override
  ConsumerState<AddNewItemOverlay> createState() => _AddNewItemOverlayState();
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

class _AddNewItemOverlayState extends ConsumerState<AddNewItemOverlay> {
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
                color: DcColors.scrim,
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
    final modalWidth = math.min(560.0, constraints.maxWidth);
    final modalHeight = math.min(440.0, constraints.maxHeight);
    final visibleNewItemTypes = _allNewItemTypes
        .where((item) => !_hiddenAddItemTypeIds.contains(item.id))
        .toList(growable: false);

    return Container(
      width: modalWidth,
      constraints: BoxConstraints(maxHeight: modalHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _ItemModalColors.surface,
        borderRadius: BorderRadius.circular(DcMetrics.panelRadius),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: DcColors.shadow,
            blurRadius: 44,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DcDialogTitleBar(title: 'Add an item', onClose: widget.onClose),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'ITEM TYPE',
                    style: _text(
                      10,
                      _ItemModalColors.headerLabel,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                                  if (column > 0) const SizedBox(width: 8),
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
                              const SizedBox(height: 8),
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
