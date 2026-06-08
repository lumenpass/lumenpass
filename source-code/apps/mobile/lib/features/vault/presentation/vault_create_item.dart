import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import 'vault_create_item_bank_account.dart';
import 'vault_create_item_credit_card.dart';
import 'vault_create_item_identity.dart';
import 'vault_create_item_login.dart';
import 'vault_create_item_models.dart';
import 'vault_create_item_secure_note.dart';
import 'vault_create_item_shared.dart';
import 'vault_create_item_ssh_key.dart';
import 'vault_toast.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

/// Push the [AddNewItemOverlay] as a transparent route on the navigator stack.
void showAddNewItemOverlay(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (ctx, animation, secondaryAnimation) {
        // Guard so the route is only popped once. The create modals call
        // onItemSaved (which pops) and then onClose (which would pop again) in
        // the same synchronous frame; without this guard the second pop hits an
        // empty navigator stack and throws `_history.isNotEmpty`.
        var popped = false;
        void popOnce() {
          if (popped) return;
          popped = true;
          Navigator.of(ctx).pop();
        }

        return AddNewItemOverlay(
          onClose: popOnce,
          onItemCreated: (_) => popOnce(),
          onShowToast: (msg) => showVaultFloatingToast(ctx, msg),
        );
      },
    ),
  );
}

/// Push an edit overlay for [entry]. The correct form is chosen automatically
/// based on the entry's item type. [onItemSaved] is called with the updated
/// entry uuid once saved; pass `null` to ignore it.
void showEditItemModal(
  BuildContext context, {
  required KdbxEntry entry,
  ValueChanged<String>? onItemSaved,
}) {
  final itemType = classifyVaultItemType(entry);
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (ctx, animation, secondaryAnimation) {
        void close() => Navigator.of(ctx).pop();
        void showToast(String msg) => showVaultFloatingToast(ctx, msg);
        void saved(String uuid) {
          onItemSaved?.call(uuid);
        }

        Widget modal;
        switch (itemType) {
          case VaultItemType.secureNote:
            modal = AddSecureNoteItemModal(
              onClose: close,
              onShowToast: showToast,
              onItemSaved: saved,
              editingEntry: entry,
            );
            break;
          case VaultItemType.creditCard:
            modal = AddCreditCardItemModal(
              onClose: close,
              onShowToast: showToast,
              onItemSaved: saved,
              editingEntry: entry,
            );
            break;
          case VaultItemType.bankAccount:
            modal = AddBankAccountItemModal(
              onClose: close,
              onShowToast: showToast,
              onItemSaved: saved,
              editingEntry: entry,
            );
            break;
          case VaultItemType.identity:
            modal = AddIdentityItemModal(
              onClose: close,
              onShowToast: showToast,
              onItemSaved: saved,
              editingEntry: entry,
            );
            break;
          case VaultItemType.sshKey:
            modal = AddSshKeyItemModal(
              onClose: close,
              onShowToast: showToast,
              onItemSaved: saved,
              editingEntry: entry,
            );
            break;
          default:
            modal = AddLoginItemModal(
              onClose: close,
              onShowToast: showToast,
              onItemSaved: saved,
              editingEntry: entry,
            );
        }

        return Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            onTap: close,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: const Color(0x52000000),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 28),
                  child: GestureDetector(
                    onTap: () {},
                    child: modal,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

// ── View enum ─────────────────────────────────────────────────────────────────

enum _AddItemModalView {
  picker,
  login,
  secureNote,
  creditCard,
  bankAccount,
  identity,
  sshKey,
}

// ── Overlay widget ────────────────────────────────────────────────────────────

class AddNewItemOverlay extends ConsumerStatefulWidget {
  const AddNewItemOverlay({
    super.key,
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

class _AddNewItemOverlayState extends ConsumerState<AddNewItemOverlay> {
  _AddItemModalView _view = _AddItemModalView.picker;
  String _selectedTypeId = kAllNewItemTypes.first.id;

  void _returnToPicker() {
    setState(() => _view = _AddItemModalView.picker);
  }

  void _handleSelectType(MobileNewItemType option) {
    setState(() {
      _selectedTypeId = option.id;
      switch (option.id) {
        case 'login':
          _view = _AddItemModalView.login;
          break;
        case 'secure-note':
          _view = _AddItemModalView.secureNote;
          break;
        case 'credit-card':
          _view = _AddItemModalView.creditCard;
          break;
        case 'bank-account':
          _view = _AddItemModalView.bankAccount;
          break;
        case 'identity':
          _view = _AddItemModalView.identity;
          break;
        case 'ssh-key':
          _view = _AddItemModalView.sshKey;
          break;
        default:
          widget.onShowToast('${option.label} editor is not available yet');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: widget.onClose,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              color: const Color(0x52000000),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
              child: GestureDetector(
                onTap: () {},
                child: _buildCurrentView(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_view) {
      case _AddItemModalView.picker:
        return _TypePickerModal(
          selectedTypeId: _selectedTypeId,
          onClose: widget.onClose,
          onSelectType: _handleSelectType,
        );
      case _AddItemModalView.login:
        return AddLoginItemModal(
          onClose: widget.onClose,
          onShowToast: widget.onShowToast,
          onItemSaved: widget.onItemCreated,
          onReturnToPicker: _returnToPicker,
        );
      case _AddItemModalView.secureNote:
        return AddSecureNoteItemModal(
          onClose: widget.onClose,
          onShowToast: widget.onShowToast,
          onItemSaved: widget.onItemCreated,
          onReturnToPicker: _returnToPicker,
        );
      case _AddItemModalView.creditCard:
        return AddCreditCardItemModal(
          onClose: widget.onClose,
          onShowToast: widget.onShowToast,
          onItemSaved: widget.onItemCreated,
          onReturnToPicker: _returnToPicker,
        );
      case _AddItemModalView.bankAccount:
        return AddBankAccountItemModal(
          onClose: widget.onClose,
          onShowToast: widget.onShowToast,
          onItemSaved: widget.onItemCreated,
          onReturnToPicker: _returnToPicker,
        );
      case _AddItemModalView.identity:
        return AddIdentityItemModal(
          onClose: widget.onClose,
          onShowToast: widget.onShowToast,
          onItemSaved: widget.onItemCreated,
          onReturnToPicker: _returnToPicker,
        );
      case _AddItemModalView.sshKey:
        return AddSshKeyItemModal(
          onClose: widget.onClose,
          onShowToast: widget.onShowToast,
          onItemSaved: widget.onItemCreated,
          onReturnToPicker: _returnToPicker,
        );
    }
  }
}

// ── Type picker modal ─────────────────────────────────────────────────────────

class _TypePickerModal extends StatelessWidget {
  const _TypePickerModal({
    required this.selectedTypeId,
    required this.onClose,
    required this.onSelectType,
  });

  final String selectedTypeId;
  final VoidCallback onClose;
  final ValueChanged<MobileNewItemType> onSelectType;

  @override
  Widget build(BuildContext context) {
    final visibleTypes = kAllNewItemTypes
        .where((t) => !kHiddenAddItemTypeIds.contains(t.id))
        .toList(growable: false);

    return Container(
      width: double.infinity,
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
        children: [
          Row(
            children: [
              const SizedBox(width: 24, height: 24),
              Expanded(
                child: Text(
                  'What would you like to add?',
                  textAlign: TextAlign.center,
                  style: itemText(18, const Color(0xFF2E3138),
                      fontWeight: FontWeight.w700),
                ),
              ),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(TablerIcons.x,
                      size: 18, color: Color(0xFF6E7687)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('All item types',
                  style: itemText(10, const Color(0xFF5F6878),
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final option in visibleTypes) ...[
                _NewItemTypeRow(
                  option: option,
                  selected: option.id == selectedTypeId,
                  onTap: () => onSelectType(option),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              Container(height: 1, color: const Color(0xFFE2E6EE)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE1E7F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(TablerIcons.info_circle,
                          size: 16, color: Color(0xFF6B7A90)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Choose the item type that best matches what you want to store, so your vault stays organized and easier to search later.',
                        style: itemText(11, const Color(0xFF667085),
                            fontWeight: FontWeight.w500, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewItemTypeRow extends StatelessWidget {
  const _NewItemTypeRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final MobileNewItemType option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF1F6FF) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFFCFE0FF)
                : const Color(0xFFD8DEE9),
          ),
        ),
        child: Row(
          children: [
            if (option.imagePath != null)
              Image.asset(
                option.imagePath!,
                width: 18,
                height: 18,
                errorBuilder: (context, error, stackTrace) => Icon(
                  option.icon ?? TablerIcons.file_description,
                  size: 16,
                  color: option.iconColor,
                ),
              )
            else if (option.icon != null)
              Icon(option.icon, size: 16, color: option.iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.label,
                style: itemText(13, const Color(0xFF2E3138),
                    fontWeight: FontWeight.w500),
              ),
            ),
            const Icon(TablerIcons.chevron_right,
                size: 14, color: Color(0xFFAFBCCE)),
          ],
        ),
      ),
    );
  }
}
