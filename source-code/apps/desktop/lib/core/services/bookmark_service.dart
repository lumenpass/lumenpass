import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Dart wrapper around the macOS security-scoped bookmark MethodChannel.
///
/// Security-scoped bookmarks allow a sandboxed macOS app to persist file-
/// system access across restarts without repeatedly asking the user to
/// re-pick the same files.
class BookmarkService {
  BookmarkService._();

  static final BookmarkService instance = BookmarkService._();

  static const MethodChannel _channel = MethodChannel('lumenpass/window');

  /// Paths that are currently being security-scope accessed this session.
  final Set<String> _activePaths = {};

  // ── Pickers ────────────────────────────────────────────────────────────────

  /// Opens a native NSOpenPanel for .kdbx files.
  /// Returns `{path, bookmark}` or null if cancelled.
  Future<({String path, String bookmark})?> pickFileWithBookmark() async {
    if (!Platform.isMacOS) {
      try {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: 'Open KeePass Database',
          lockParentWindow: true,
          type: FileType.custom,
          allowedExtensions: const <String>['kdbx', 'kdb'],
          withData: false,
        );
        final path = result?.files.single.path;
        if (path == null || path.isEmpty) {
          return null;
        }
        return (path: path, bookmark: path);
      } on MissingPluginException catch (e) {
        _log('pickFileWithBookmark failed: ${e.message}');
        return null;
      } catch (e) {
        _log('pickFileWithBookmark failed: $e');
        return null;
      }
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'pickFileWithBookmark',
      );
      if (result == null) return null;
      final path = result['path'] as String? ?? '';
      final bookmark = result['bookmark'] as String? ?? '';
      if (path.isEmpty) return null;
      if (bookmark.isNotEmpty) _activePaths.add(path);
      return (path: path, bookmark: bookmark);
    } on PlatformException catch (e) {
      _log('pickFileWithBookmark failed: ${e.message}');
      return null;
    }
  }

  /// Opens a native NSOpenPanel for directory selection.
  /// Returns `{path, bookmark}` or null if cancelled.
  Future<({String path, String bookmark})?> pickDirectoryWithBookmark() async {
    if (!Platform.isMacOS) {
      try {
        final path = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Choose save location',
          lockParentWindow: true,
        );
        if (path == null || path.isEmpty) {
          return null;
        }
        return (path: path, bookmark: path);
      } on MissingPluginException catch (e) {
        _log('pickDirectoryWithBookmark failed: ${e.message}');
        return null;
      } catch (e) {
        _log('pickDirectoryWithBookmark failed: $e');
        return null;
      }
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'pickDirectoryWithBookmark',
      );
      if (result == null) return null;
      final path = result['path'] as String? ?? '';
      final bookmark = result['bookmark'] as String? ?? '';
      if (path.isEmpty) return null;
      if (bookmark.isNotEmpty) _activePaths.add(path);
      return (path: path, bookmark: bookmark);
    } on PlatformException catch (e) {
      _log('pickDirectoryWithBookmark failed: ${e.message}');
      return null;
    }
  }

  // ── Bookmark lifecycle ─────────────────────────────────────────────────────

  /// Creates a security-scoped bookmark for [path].
  /// The path must already be accessible (e.g. just written to disk or picked).
  Future<String> createBookmarkForPath(String path) async {
    if (!Platform.isMacOS) return '';
    try {
      final b = await _channel.invokeMethod<String>(
        'createBookmarkForPath',
        path,
      );
      return b ?? '';
    } on PlatformException catch (e) {
      _log('createBookmarkForPath failed for $path: ${e.message}');
      return '';
    }
  }

  /// Resolves a previously created bookmark and starts security-scoped access.
  /// Returns the resolved path, or null on failure.
  Future<String?> resolveAndStartAccessing(String bookmark) async {
    if (!Platform.isMacOS || bookmark.isEmpty) return null;
    try {
      final path = await _channel.invokeMethod<String>(
        'resolveBookmark',
        bookmark,
      );
      if (path != null && path.isNotEmpty) {
        _activePaths.add(path);
        _log('resolved bookmark → $path');
      }
      return path;
    } on PlatformException catch (e) {
      _log('resolveBookmark failed: ${e.message}');
      return null;
    }
  }

  /// Stops security-scoped access for [path].
  Future<void> stopAccessing(String path) async {
    if (!Platform.isMacOS) return;
    if (!_activePaths.contains(path)) return;
    try {
      await _channel.invokeMethod<void>('stopAccessingBookmark', path);
      _activePaths.remove(path);
    } catch (_) {}
  }

  /// Stops security-scoped access for all currently accessed paths.
  Future<void> stopAll() async {
    for (final path in List<String>.from(_activePaths)) {
      await stopAccessing(path);
    }
  }

  void _log(String msg) {
    // ignore: avoid_print
    print('[BookmarkService] $msg');
  }
}
