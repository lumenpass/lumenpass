import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/floating_glass_search_bar.dart';
import '../application/vault_entries_providers.dart';

/// Floating glass search toolbar wired to the shared vault search state, paired
/// with an "add" button. Used on the Home and Items tabs so they match the
/// vault picker's floating search treatment.
class VaultSearchFloatingToolbar extends ConsumerStatefulWidget {
  const VaultSearchFloatingToolbar({
    super.key,
    required this.hintText,
    required this.onAdd,
    required this.addSemanticLabel,
    this.searchKey,
    this.addKey,
  });

  final String hintText;
  final VoidCallback onAdd;
  final String addSemanticLabel;
  final GlobalKey? searchKey;
  final GlobalKey? addKey;

  @override
  ConsumerState<VaultSearchFloatingToolbar> createState() =>
      _VaultSearchFloatingToolbarState();
}

class _VaultSearchFloatingToolbarState
    extends ConsumerState<VaultSearchFloatingToolbar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    ref.read(vaultSearchUiStateProvider.notifier).setDraft(value);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(vaultSearchDraftProvider);
    final isLoading = ref.watch(vaultSearchLoadingProvider);

    if (_controller.text != draft) {
      _controller.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }

    return FloatingGlassSearchToolbar(
      controller: _controller,
      hintText: widget.hintText,
      onChanged: _onChanged,
      onAdd: widget.onAdd,
      isLoading: isLoading,
      searchKey: widget.searchKey,
      addKey: widget.addKey,
      addSemanticLabel: widget.addSemanticLabel,
    );
  }
}
