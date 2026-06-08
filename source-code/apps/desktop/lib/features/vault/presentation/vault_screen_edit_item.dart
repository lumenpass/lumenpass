part of 'vault_screen.dart';

class _EditItemOverlay extends ConsumerWidget {
  const _EditItemOverlay({
    required this.entry,
    required this.onClose,
    required this.onShowToast,
    required this.onItemUpdated,
  });

  final _MockEntry entry;
  final VoidCallback onClose;
  final ValueChanged<String> onShowToast;
  final ValueChanged<String> onItemUpdated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FocusScope(
      autofocus: true,
      child: FocusTraversalGroup(
        child: GestureDetector(
          onTap: onClose,
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
                      switch (entry.itemType) {
                        case VaultItemType.secureNote:
                          return _AddSecureNoteItemModal(
                            onClose: onClose,
                            onShowToast: onShowToast,
                            onItemSaved: onItemUpdated,
                            editingEntry: entry,
                          );
                        case VaultItemType.creditCard:
                          return _AddCreditCardItemModal(
                            onClose: onClose,
                            onShowToast: onShowToast,
                            onItemSaved: onItemUpdated,
                            editingEntry: entry,
                          );
                        case VaultItemType.bankAccount:
                          return _AddBankAccountItemModal(
                            onClose: onClose,
                            onShowToast: onShowToast,
                            onItemSaved: onItemUpdated,
                            editingEntry: entry,
                          );
                        case VaultItemType.identity:
                          return _AddIdentityItemModal(
                            onClose: onClose,
                            onShowToast: onShowToast,
                            onItemSaved: onItemUpdated,
                            editingEntry: entry,
                          );
                        case VaultItemType.sshKey:
                          return _AddSshKeyItemModal(
                            onClose: onClose,
                            onShowToast: onShowToast,
                            onItemSaved: onItemUpdated,
                            editingEntry: entry,
                          );
                        default:
                          return _AddLoginItemModal(
                            onClose: onClose,
                            onShowToast: onShowToast,
                            onItemSaved: onItemUpdated,
                            editingEntry: entry,
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
}
