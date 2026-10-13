/// Copy for an empty vault selection. The unfiltered vault is the only case
/// that should invite the user to add a first item.
({String title, String description, bool showSuggestions}) vaultEmptyStateCopy({
  required int totalItemCount,
  String? groupId,
  String? itemTypeId,
  String? tag,
  String searchQuery = '',
  String? passwordAuditIssue,
}) {
  if (searchQuery.trim().isNotEmpty) {
    return (
      title: 'No matching items',
      description: 'Try another search or clear the search to see all items.',
      showSuggestions: false,
    );
  }
  if (passwordAuditIssue != null) {
    final title = switch (passwordAuditIssue) {
      'duplicated' => 'No duplicate items',
      'weak' => 'No weak passwords',
      'stale' => 'No stale passwords',
      _ => 'No audit results',
    };
    return (
      title: title,
      description: 'No items match this password audit filter.',
      showSuggestions: false,
    );
  }
  if (groupId == 'group_trash') {
    return (
      title: 'Trash is empty',
      description: 'Deleted items will appear here.',
      showSuggestions: false,
    );
  }
  if (groupId == 'category_uncategorized') {
    return (
      title: 'No uncategorized items',
      description: 'Items without a category will appear here.',
      showSuggestions: false,
    );
  }
  if (groupId != null && groupId != 'category_all') {
    return (
      title: 'No items in this category',
      description: 'Items assigned to this category will appear here.',
      showSuggestions: false,
    );
  }
  if (tag != null) {
    return (
      title: 'No items with this tag',
      description: 'Items tagged "$tag" will appear here.',
      showSuggestions: false,
    );
  }
  if (itemTypeId != null) {
    final title = switch (itemTypeId) {
      'quick_passkeys' => 'No passkeys',
      'quick_totp' => 'No TOTP codes',
      'quick_password_audits' => 'No audit results',
      _ => 'No items of this type',
    };
    return (
      title: title,
      description: 'Items in this view will appear here.',
      showSuggestions: false,
    );
  }
  if (totalItemCount > 0) {
    return (
      title: 'No items in this view',
      description: 'Select All Items to see everything in your vault.',
      showSuggestions: false,
    );
  }
  return (
    title: 'Your vault is empty',
    description: 'Add your first item using the "+ New Item" button above.',
    showSuggestions: true,
  );
}
