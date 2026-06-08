import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lumenpass_core/lumenpass_core.dart';

import '../../../core/services/favicon_persistence_service.dart';
import '../../../core/services/vault_preferences.dart';

/// List avatar aligned with desktop `_FaviconTile` (favicon, card brand, type badges).
///
/// Mobile-optimized for long scroll lists:
///   * uses [KdbxEntry.faviconPngBase64] as the primary source so the
///     network is only hit once per website, ever, across sessions;
///   * wraps the bitmap in a [RepaintBoundary] and caps raster decode via
///     `cacheWidth`/`cacheHeight` to avoid full-resolution decodes;
///   * persists the fetched bytes onto the owning entry (debounced save)
///     via [FaviconPersistenceService] after a successful network load.
class VaultEntryAvatar extends ConsumerStatefulWidget {
  const VaultEntryAvatar({
    super.key,
    required this.entry,
    required this.size,
    this.itemType,
  });

  final KdbxEntry entry;
  final double size;

  /// Optional pre-computed classification. When supplied (e.g. by the parent
  /// list tile) we skip the expensive [classifyVaultItemType] call — a win
  /// for long lists where every row already classifies the entry once.
  final VaultItemType? itemType;

  @override
  ConsumerState<VaultEntryAvatar> createState() => _VaultEntryAvatarState();
}

class _VaultEntryAvatarState extends ConsumerState<VaultEntryAvatar> {
  bool _cacheUpdatePending = false;
  bool _persistQueued = false;

  /// Cached decoded favicon bytes + the payload string they were derived
  /// from. Keeping the payload lets us detect changes (new cache, failure)
  /// without re-running base64 decode on every rebuild.
  String? _cachedFaviconPayload;
  Uint8List? _cachedFaviconBytes;

  Uint8List? _decodeCachedFavicon() {
    final payload = widget.entry.faviconPngBase64;
    if (payload == null || payload.isEmpty) {
      _cachedFaviconPayload = null;
      _cachedFaviconBytes = null;
      return null;
    }
    if (payload == AppKdbxFieldKeys.faviconFailedSentinel) {
      _cachedFaviconPayload = payload;
      _cachedFaviconBytes = null;
      return null;
    }
    if (payload == _cachedFaviconPayload && _cachedFaviconBytes != null) {
      return _cachedFaviconBytes;
    }
    try {
      final bytes = base64Decode(payload);
      _cachedFaviconPayload = payload;
      _cachedFaviconBytes = bytes;
      return bytes;
    } catch (_) {
      _cachedFaviconPayload = payload;
      _cachedFaviconBytes = null;
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant VaultEntryAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The list viewport reuses widget slots as the user scrolls. When a
    // different entry lands in this slot, reset the one-shot persist guard
    // so the new entry can still schedule its favicon fetch exactly once.
    if (oldWidget.entry.uuid != widget.entry.uuid) {
      _persistQueued = false;
      _cacheUpdatePending = false;
    }
  }

  /// Records the in-session fetch outcome for [url] into
  /// [faviconFetchResultProvider] — mirrors the desktop behavior so a URL
  /// that already succeeded stays rendered even if the user turns the
  /// auto-fetch toggle off mid-session, and a URL that failed in-session
  /// doesn't cascade-retry on every tile rebuild.
  void _scheduleCacheUpdate(String url, bool succeeded) {
    if (_cacheUpdatePending) return;
    _cacheUpdatePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cacheUpdatePending = false;
      if (!mounted) return;
      ref.read(faviconFetchResultProvider.notifier).update((s) {
        if (s[url] == succeeded) return s;
        return {...s, url: succeeded};
      });
    });
  }

  /// Persist a fetched favicon (or failure) onto the entry exactly once
  /// per widget lifetime. Guards repeated loadingBuilder ticks.
  void _schedulePersist(String url, bool succeeded) {
    if (_persistQueued) return;
    _persistQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final service = ref.read(faviconPersistenceServiceProvider);
      if (succeeded) {
        service.enqueue(entryUuid: widget.entry.uuid, faviconUrl: url);
      } else {
        service.recordFailure(entryUuid: widget.entry.uuid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemType =
        widget.itemType ?? classifyVaultItemType(widget.entry);
    final colors = vaultListTileArgbForEntry(widget.entry);
    final bg = Color(colors.backgroundArgb);
    final fg = Color(colors.foregroundArgb);

    if (itemType == VaultItemType.creditCard) {
      final brand =
          detectVaultCardBrand(extractCreditCardNumberFromEntry(widget.entry));
      if (brand != null) {
        return _CardBrandBadge(brand: brand, size: widget.size);
      }
      return _InitialsTile(
        size: widget.size,
        background: bg,
        foreground: fg,
        initials: vaultEntryListInitials(widget.entry),
      );
    }

    if (itemType == VaultItemType.login) {
      final initialsWidget = _InitialsTile(
        size: widget.size,
        background: bg,
        foreground: fg,
        initials: vaultEntryListInitials(widget.entry),
      );

      final cachedPayload = widget.entry.faviconPngBase64;
      final hasFailedPersist =
          cachedPayload == AppKdbxFieldKeys.faviconFailedSentinel;
      final cachedBytes = _decodeCachedFavicon();
      final int decodePx = (widget.size * 2).ceil();

      // Fast path: favicon already saved to the entry → render from
      // memory, never touch the network. Matches desktop `_FaviconTile`.
      if (cachedBytes != null) {
        return RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              cachedBytes,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              cacheWidth: decodePx,
              cacheHeight: decodePx,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) => initialsWidget,
            ),
          ),
        );
      }

      // Previous fetch permanently failed — skip the network entirely
      // for good. Matches desktop `_FaviconTile`.
      if (hasFailedPersist) return initialsWidget;

      final faviconUrl = faviconUrlForWebsite(widget.entry.url ?? '');
      if (faviconUrl == null) {
        return initialsWidget;
      }

      // Scoped subscription: only rebuild this tile when THIS url's
      // result flips, not when any other tile updates the map.
      final fetchResultForUrl = ref.watch(
        faviconFetchResultProvider.select((s) => s[faviconUrl]),
      );
      final autoFetchIcon = ref.watch(vaultAutoFetchItemIconProvider);

      final hasBeenAttempted = fetchResultForUrl != null;
      final wasFetchSuccessful =
          hasBeenAttempted && fetchResultForUrl == true;

      // Mirror of desktop behavior:
      //   • previously fetched successfully this session → keep showing
      //     even if the toggle is now off.
      //   • toggle on AND URL has not been attempted yet → attempt now.
      //   • a URL that failed this session is not retried until a cold
      //     start (when the persisted failure sentinel would already
      //     short-circuit above).
      final shouldShowFavicon =
          wasFetchSuccessful || (!hasBeenAttempted && autoFetchIcon);

      if (!shouldShowFavicon) return initialsWidget;

      final needsCacheUpdate = !hasBeenAttempted;

      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            faviconUrl,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            cacheWidth: decodePx,
            cacheHeight: decodePx,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              if (needsCacheUpdate) _scheduleCacheUpdate(faviconUrl, false);
              _schedulePersist(faviconUrl, false);
              return initialsWidget;
            },
            loadingBuilder: (_, child, progress) {
              if (progress == null) {
                if (needsCacheUpdate) _scheduleCacheUpdate(faviconUrl, true);
                _schedulePersist(faviconUrl, true);
                return child;
              }
              return initialsWidget;
            },
          ),
        ),
      );
    }

    if (itemType == VaultItemType.sshKey) {
      return _TypeBadge(
        size: widget.size,
        background: const Color(0xFF1D6570).withValues(alpha: 0.18),
        icon: Icons.terminal_rounded,
        iconColor: const Color(0xFF5D6F88),
      );
    }

    if (itemType == VaultItemType.bankAccount) {
      return _TypeBadge(
        size: widget.size,
        background: const Color(0xFF1F9A76).withValues(alpha: 0.18),
        icon: Icons.account_balance_rounded,
        iconColor: const Color(0xFF1F9A76),
      );
    }

    if (itemType == VaultItemType.identity) {
      return _TypeBadge(
        size: widget.size,
        background: const Color(0xFF56B676).withValues(alpha: 0.18),
        icon: Icons.badge_outlined,
        iconColor: const Color(0xFF56B676),
      );
    }

    if (itemType == VaultItemType.secureNote) {
      return _TypeBadge(
        size: widget.size,
        background: const Color(0xFFE0A433).withValues(alpha: 0.18),
        icon: Icons.sticky_note_2_outlined,
        iconColor: const Color(0xFFB45309),
      );
    }

    if (itemType == VaultItemType.apiCredential) {
      return _TypeBadge(
        size: widget.size,
        background: const Color(0xFF8C57D9).withValues(alpha: 0.18),
        icon: Icons.vpn_key_rounded,
        iconColor: const Color(0xFF8C57D9),
      );
    }

    return _TypeBadge(
      size: widget.size,
      background: const Color(0xFF4F97F1).withValues(alpha: 0.18),
      icon: Icons.description_outlined,
      iconColor: const Color(0xFF4F97F1),
    );
  }
}

class _InitialsTile extends StatelessWidget {
  const _InitialsTile({
    required this.size,
    required this.background,
    required this.foreground,
    required this.initials,
  });

  final double size;
  final Color background;
  final Color foreground;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({
    required this.size,
    required this.background,
    required this.icon,
    required this.iconColor,
  });

  final double size;
  final Color background;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.58, color: iconColor),
    );
  }
}

class _CardBrandBadge extends StatelessWidget {
  const _CardBrandBadge({required this.brand, required this.size});

  final VaultCardBrand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (brand) {
      case VaultCardBrand.visa:
        return _BrandTextTile(
          size: size,
          gradient: const LinearGradient(
            colors: [Color(0xFF1F63D6), Color(0xFF1349AF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          label: 'VISA',
          fontSize: size * 0.27,
        );
      case VaultCardBrand.mastercard:
        return _BrandMastercardTile(size: size);
      case VaultCardBrand.amex:
        return _BrandTextTile(
          size: size,
          gradient: const LinearGradient(
            colors: [Color(0xFF4CC4F0), Color(0xFF1596D1)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          label: 'AMEX',
          fontSize: size * 0.22,
        );
      case VaultCardBrand.discover:
        return _BrandTextTile(
          size: size,
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8C42), Color(0xFFE85D04)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          label: 'DISC',
          fontSize: size * 0.2,
        );
      case VaultCardBrand.diners:
        return _BrandTextTile(
          size: size,
          gradient: const LinearGradient(
            colors: [Color(0xFF1B75BC), Color(0xFF0C4C7F)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          label: 'DIN',
          fontSize: size * 0.2,
        );
      case VaultCardBrand.jcb:
        return _BrandTextTile(
          size: size,
          gradient: const LinearGradient(
            colors: [Color(0xFF0B4EA2), Color(0xFF063057)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          label: 'JCB',
          fontSize: size * 0.24,
        );
      case VaultCardBrand.unionPay:
        return _BrandTextTile(
          size: size,
          gradient: const LinearGradient(
            colors: [Color(0xFFE53935), Color(0xFF1565C0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          label: 'UP',
          fontSize: size * 0.26,
        );
      case VaultCardBrand.maestro:
        return _BrandTextTile(
          size: size,
          gradient: const LinearGradient(
            colors: [Color(0xFF0099DF), Color(0xFF6C207D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          label: 'M',
          fontSize: size * 0.3,
        );
    }
  }
}

class _BrandTextTile extends StatelessWidget {
  const _BrandTextTile({
    required this.size,
    required this.gradient,
    required this.label,
    required this.fontSize,
  });

  final double size;
  final Gradient gradient;
  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(gradient: gradient),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _BrandMastercardTile extends StatelessWidget {
  const _BrandMastercardTile({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF262626), Color(0xFF1A1A1A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Positioned(
              left: size * 0.12,
              top: size * 0.28,
              child: Container(
                width: size * 0.42,
                height: size * 0.42,
                decoration: const BoxDecoration(
                  color: Color(0xFFEB001B),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: size * 0.12,
              top: size * 0.28,
              child: Container(
                width: size * 0.42,
                height: size * 0.42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF79E1B).withValues(alpha: 0.95),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
