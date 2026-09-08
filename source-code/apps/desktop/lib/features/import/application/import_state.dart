import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/import_parsed_item.dart';
import '../domain/import_provider.dart';
import 'import_executor.dart';

enum ImportStep { providerSelection, preview, confirmation, clearing, progress }

enum ImportPreviewTab { ready, errors }

class ImportState {
  const ImportState({
    this.step = ImportStep.providerSelection,
    this.selectedProvider,
    this.filePath,
    this.fileName,
    this.parsedItems = const <ImportParsedItem>[],
    this.previewTab = ImportPreviewTab.ready,
    this.isParsing = false,
    this.parseError,
    this.importMode = ImportMode.append,
    this.targetGroupUuid,
    this.totalCount = 0,
    this.readyCount = 0,
    this.errorCount = 0,
  });

  final ImportStep step;
  final ImportProviderDefinition? selectedProvider;
  final String? filePath;
  final String? fileName;
  final List<ImportParsedItem> parsedItems;
  final ImportPreviewTab previewTab;
  final bool isParsing;
  final String? parseError;
  final ImportMode importMode;

  /// The UUID of the group (category) the user chose to import items into.
  /// When `null`, items are imported into the root group (Uncategorized).
  final String? targetGroupUuid;

  final int totalCount;
  final int readyCount;
  final int errorCount;

  ImportState copyWith({
    ImportStep? step,
    ImportProviderDefinition? selectedProvider,
    String? filePath,
    String? fileName,
    List<ImportParsedItem>? parsedItems,
    ImportPreviewTab? previewTab,
    bool? isParsing,
    String? parseError,
    ImportMode? importMode,
    String? targetGroupUuid,
    int? totalCount,
    int? readyCount,
    int? errorCount,
    bool clearProvider = false,
    bool clearFile = false,
    bool clearParseError = false,
    bool clearTargetGroup = false,
  }) {
    return ImportState(
      step: step ?? this.step,
      selectedProvider:
          clearProvider ? null : (selectedProvider ?? this.selectedProvider),
      filePath: clearFile ? null : (filePath ?? this.filePath),
      fileName: clearFile ? null : (fileName ?? this.fileName),
      parsedItems: parsedItems ?? this.parsedItems,
      previewTab: previewTab ?? this.previewTab,
      isParsing: isParsing ?? this.isParsing,
      parseError: clearParseError ? null : (parseError ?? this.parseError),
      importMode: importMode ?? this.importMode,
      targetGroupUuid:
          clearTargetGroup ? null : (targetGroupUuid ?? this.targetGroupUuid),
      totalCount: totalCount ?? this.totalCount,
      readyCount: readyCount ?? this.readyCount,
      errorCount: errorCount ?? this.errorCount,
    );
  }

  // ignore: unused_element
  ImportState _clearParseError() {
    return copyWith(clearParseError: true);
  }
}

class ImportStateNotifier extends StateNotifier<ImportState> {
  ImportStateNotifier() : super(const ImportState());

  void selectProvider(ImportProviderDefinition provider) {
    state = state.copyWith(
      selectedProvider: provider,
    );
  }

  void selectFile(String filePath, String fileName) {
    state = state.copyWith(
      filePath: filePath,
      fileName: fileName,
    );
  }

  void startParsing() {
    state = state.copyWith(isParsing: true, clearParseError: true);
  }

  void setParsedItems(List<ImportParsedItem> items) {
    final readyItems = items.where((item) => item.isReady).length;
    final errorItems = items.where((item) => item.hasErrors).length;

    state = state.copyWith(
      parsedItems: items,
      totalCount: items.length,
      readyCount: readyItems,
      errorCount: errorItems,
      isParsing: false,
      step: ImportStep.preview,
    );
  }

  void setParseError(String error) {
    state = state.copyWith(
      parseError: error,
      isParsing: false,
    );
  }

  void clearParseError() {
    state = state.copyWith(clearParseError: true);
  }

  void setPreviewTab(ImportPreviewTab tab) {
    state = state.copyWith(previewTab: tab);
  }

  void updateItem(int index, ImportParsedItem updated) {
    final items = List<ImportParsedItem>.from(state.parsedItems);
    if (index >= 0 && index < items.length) {
      items[index] = updated;
    }

    final readyItems = items.where((item) => item.isReady).length;
    final errorItems = items.where((item) => item.hasErrors).length;

    state = state.copyWith(
      parsedItems: items,
      readyCount: readyItems,
      errorCount: errorItems,
    );
  }

  void fixItem(int index, ImportParsedItem corrected) {
    corrected.validate();
    updateItem(index, corrected);
  }

  void forceAllItems() {
    final items = List<ImportParsedItem>.from(state.parsedItems);
    for (int i = 0; i < items.length; i++) {
      if (items[i].hasErrors) {
        items[i] = items[i].copyWith(isForced: true);
      }
    }

    final readyItems = items.where((item) => item.isReady).length;
    final errorItems = items.where((item) => item.hasErrors).length;

    state = state.copyWith(
      parsedItems: items,
      readyCount: readyItems,
      errorCount: errorItems,
    );
  }

  void setImportMode(ImportMode mode) {
    state = state.copyWith(importMode: mode);
  }

  void setTargetGroup(String? groupUuid) {
    state = state.copyWith(
      targetGroupUuid: groupUuid,
      clearTargetGroup: groupUuid == null,
    );
  }

  void goToConfirmation() {
    state = state.copyWith(step: ImportStep.confirmation);
  }

  void goToClearing() {
    state = state.copyWith(step: ImportStep.clearing);
  }

  void goToProgress() {
    state = state.copyWith(step: ImportStep.progress);
  }

  void goBackToPreview() {
    state = state.copyWith(step: ImportStep.preview);
  }

  void goBackToProviderSelection() {
    state = state.copyWith(step: ImportStep.providerSelection);
  }

  void reset() {
    state = const ImportState();
  }
}

final importStateProvider =
    StateNotifierProvider<ImportStateNotifier, ImportState>(
        (ref) => ImportStateNotifier());
