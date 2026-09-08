/// Intelligent ranking for vault search results, shared between the
/// title-bar suggestion dropdown and the standalone Quick Search overlay.
///
/// The previous implementation was a flat substring scan that often surfaced
/// title or notes matches above an exact URL hit. This module replaces that
/// with a deterministic, tiered ranking:
///
///   1. URL match           — query appears anywhere in the entry's URL
///   2. Recently used       — entry has been touched within [recentWindow]
///                            and matches anywhere in the searchable text
///   3. Email match         — query appears in an email-shaped field
///                            (e.g. username, "email", "e-mail" custom keys)
///   4. Title match         — query appears in the entry title
///   5. Notes/content match — query appears in notes, tags, OTP url, or any
///                            other non-protected field value
///
/// Within each tier, results are sorted by recency of use (descending), then
/// alphabetically by title for a stable order.
///
/// Matching is case-insensitive and partial. Multi-term queries (whitespace
/// separated) require every term to appear somewhere in the searchable text;
/// the tier is decided by the *strongest* tier any individual term can claim.
library;

import 'dart:math' as math;

/// Default recency window for the "recently used" tier (Tier 2).
const Duration kVaultSearchRecentWindow = Duration(days: 30);

/// Generic, framework-free view of an entry the ranker needs.
///
/// Both [KdbxEntry] (provider layer) and the presentation `_MockEntry`
/// (Quick Search overlay) wrap themselves in one of these structs before
/// handing off to [rankSearchResults] / [searchRankFor], which keeps the
/// algorithm testable in isolation from Flutter and Riverpod.
class SearchableEntryView {
  const SearchableEntryView({
    required this.title,
    required this.url,
    required this.username,
    required this.notes,
    required this.otpAuthUrl,
    required this.tags,
    required this.extraFields,
    required this.lastTouchedAt,
  });

  final String title;
  final String url;
  final String username;
  final String notes;
  final String otpAuthUrl;
  final List<String> tags;

  /// Custom (non-protected) key/value pairs. Keys help us detect
  /// email-shaped fields beyond the standard username slot.
  final List<MapEntry<String, String>> extraFields;

  /// Most recent meaningful timestamp (last modification preferred,
  /// falling back to creation). Used both as the Tier 2 freshness gate
  /// and as the primary intra-tier sort key.
  final DateTime lastTouchedAt;
}

/// Tier identifiers, lower ordinal = higher priority.
enum SearchTier {
  urlMatch,
  recentlyUsed,
  emailMatch,
  titleMatch,
  notesMatch,
  none;

  int get ordinal => index;
}

/// Result of evaluating an entry against a query.
class SearchRanking {
  const SearchRanking({
    required this.tier,
    required this.lastTouchedAt,
  });

  final SearchTier tier;
  final DateTime lastTouchedAt;

  bool get matches => tier != SearchTier.none;
}

/// Lower-cases [value] only when needed; returns `''` for null/empty.
String _norm(String? value) =>
    (value == null || value.isEmpty) ? '' : value.toLowerCase();

/// Splits the raw query into normalized, non-empty terms. All comparisons
/// downstream operate on these terms and pre-lowered haystacks, so the
/// ranking is fully case-insensitive.
List<String> normalizeQueryTerms(String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return const <String>[];
  }
  return trimmed
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList(growable: false);
}

/// Heuristic for detecting fields that *semantically* hold an email
/// address. A field qualifies if its key looks like "email"/"e-mail"/etc.
/// **or** its value contains an `@`-shaped token.
bool _looksLikeEmailKey(String key) {
  final k = key.toLowerCase();
  return k.contains('email') || k.contains('e-mail') || k.contains('mail');
}

bool _looksLikeEmailValue(String value) {
  // Cheap, locale-tolerant check: a non-whitespace local part, an "@",
  // and a non-whitespace domain. We deliberately accept international
  // (IDN) domains rather than locking to ASCII.
  final at = value.indexOf('@');
  if (at <= 0 || at >= value.length - 1) return false;
  final local = value.substring(0, at);
  final domain = value.substring(at + 1);
  if (local.contains(RegExp(r'\s'))) return false;
  if (domain.contains(RegExp(r'\s'))) return false;
  return domain.contains('.');
}

/// Computes the tier and recency for [entry] against [terms].
///
/// Returns [SearchTier.none] if any term is missing from the entry's
/// searchable text — multi-term queries require *every* term to appear
/// somewhere, but the tier is the strongest single-term tier achievable.
SearchRanking searchRankFor(
  SearchableEntryView entry,
  List<String> terms, {
  DateTime? now,
  Duration recentWindow = kVaultSearchRecentWindow,
}) {
  if (terms.isEmpty) {
    return SearchRanking(
      tier: SearchTier.none,
      lastTouchedAt: entry.lastTouchedAt,
    );
  }

  final url = _norm(entry.url);
  final title = _norm(entry.title);
  final username = _norm(entry.username);

  // Lazily-built haystacks. Building the joined email/notes strings allocates
  // per entry, so for a wide match set (e.g. backspacing to a 1–2 char query)
  // this dominates. We only build them when a term isn't already satisfied by
  // the cheap url/title/username checks above.
  String? notesHaystack;
  String? emailHaystack;

  String buildEmailHaystack() {
    final emailParts = <String>[];
    if (username.isNotEmpty &&
        (_looksLikeEmailValue(username) || username.contains('@'))) {
      emailParts.add(username);
    }
    for (final f in entry.extraFields) {
      final v = _norm(f.value);
      if (v.isEmpty) continue;
      if (_looksLikeEmailKey(f.key) || _looksLikeEmailValue(f.value)) {
        emailParts.add(v);
      }
    }
    return emailParts.join('\n');
  }

  String buildNotesHaystack() {
    final notes = _norm(entry.notes);
    final otp = _norm(entry.otpAuthUrl);
    final parts = <String>[
      notes,
      otp,
      if (username.isNotEmpty) username,
      ...entry.tags.map(_norm),
      for (final f in entry.extraFields)
        if (f.value.isNotEmpty) _norm(f.value),
    ];
    return parts.where((s) => s.isNotEmpty).join('\n');
  }

  // Per-term tier evaluation.
  // We require *all* terms to match somewhere; we record the strongest
  // tier achievable across terms (i.e. the minimum ordinal).
  var bestTier = SearchTier.none;
  for (final term in terms) {
    // Evaluate in tier-priority order (url > email > title > notes) and
    // short-circuit: once a stronger tier matches we skip the weaker
    // haystacks, and we only materialize the joined email/notes strings
    // when a cheaper check hasn't already satisfied this term.
    final inUrl = url.contains(term);
    final inEmail =
        !inUrl && (emailHaystack ??= buildEmailHaystack()).contains(term);
    final inTitle = !inUrl && !inEmail && title.contains(term);
    final inNotes = !inUrl &&
        !inEmail &&
        !inTitle &&
        (notesHaystack ??= buildNotesHaystack()).contains(term);
    final matchedAnywhere = inUrl || inEmail || inTitle || inNotes;
    if (!matchedAnywhere) {
      return SearchRanking(
        tier: SearchTier.none,
        lastTouchedAt: entry.lastTouchedAt,
      );
    }

    SearchTier termTier;
    if (inUrl) {
      termTier = SearchTier.urlMatch;
    } else if (inEmail) {
      termTier = SearchTier.emailMatch;
    } else if (inTitle) {
      termTier = SearchTier.titleMatch;
    } else {
      termTier = SearchTier.notesMatch;
    }

    if (termTier.ordinal < bestTier.ordinal || bestTier == SearchTier.none) {
      bestTier = termTier;
    }
  }

  // Tier-2 promotion: anything below URL-match that was touched within
  // the recent window jumps to "recently used". URL matches always win
  // outright — we do not demote them — and notes-only matches still get
  // the bump since "recently used" is purely a recency boost.
  if (bestTier != SearchTier.urlMatch && bestTier != SearchTier.none) {
    final reference = now ?? DateTime.now();
    final touchedRecently =
        reference.difference(entry.lastTouchedAt) <= recentWindow &&
            entry.lastTouchedAt.millisecondsSinceEpoch > 0;
    if (touchedRecently && SearchTier.recentlyUsed.ordinal < bestTier.ordinal) {
      bestTier = SearchTier.recentlyUsed;
    }
  }

  return SearchRanking(
    tier: bestTier,
    lastTouchedAt: entry.lastTouchedAt,
  );
}

/// Filters and ranks [entries] against [query]. Non-matching entries are
/// dropped; the rest are sorted by [SearchTier] then recency.
///
/// [limit] caps the result list; pass `null` for unlimited.
List<T> rankSearchResults<T>({
  required Iterable<T> entries,
  required String query,
  required SearchableEntryView Function(T) viewOf,
  required String Function(T) titleOf,
  int? limit,
  DateTime? now,
  Duration recentWindow = kVaultSearchRecentWindow,
}) {
  final terms = normalizeQueryTerms(query);
  if (terms.isEmpty) {
    return entries.toList(growable: false);
  }

  // Pair each survivor with its precomputed ranking so we never re-evaluate
  // during the sort. The lowercased title is computed exactly once here (not
  // inside the comparator) — previously the tie-break called `toLowerCase()`
  // on every comparison, which allocated tens of thousands of throwaway
  // strings on the UI thread when the match set was large (e.g. backspacing
  // down to a 1–2 character query that matches most of the vault). That
  // allocation storm was the cause of the search freeze on delete.
  final survivors = <_RankedItem<T>>[];
  for (final e in entries) {
    final r =
        searchRankFor(viewOf(e), terms, now: now, recentWindow: recentWindow);
    if (!r.matches) continue;
    survivors.add(
      _RankedItem<T>(
        item: e,
        tierOrdinal: r.tier.ordinal,
        lastTouchedMs: r.lastTouchedAt.millisecondsSinceEpoch,
        titleLower: titleOf(e).toLowerCase(),
      ),
    );
  }

  // When the caller only wants a small number of results (the suggestion
  // dropdown asks for ~6), select the top-K directly instead of fully
  // sorting the entire match set. This turns an O(n log n) sort over
  // thousands of matches into an O(n * k) scan with a tiny constant k,
  // which keeps the dropdown responsive no matter how wide the query is.
  if (limit != null && limit < survivors.length && limit <= 64) {
    return _selectTopK<T>(survivors, limit);
  }

  survivors.sort(_compareRanked);

  final effectiveLimit =
      (limit != null && survivors.length > limit) ? limit : survivors.length;
  final ordered = List<T>.generate(
    effectiveLimit,
    (i) => survivors[i].item,
    growable: false,
  );
  return ordered;
}

/// A survivor of the match filter, carrying precomputed sort keys so the
/// comparator does zero allocation.
class _RankedItem<T> {
  _RankedItem({
    required this.item,
    required this.tierOrdinal,
    required this.lastTouchedMs,
    required this.titleLower,
  });

  final T item;
  final int tierOrdinal;
  final int lastTouchedMs;
  final String titleLower;
}

/// Total order used everywhere ranked results are sorted: tier first
/// (ascending ordinal = stronger match), then recency (descending), then
/// title (ascending) for a stable, deterministic tie-break.
int _compareRanked<T>(_RankedItem<T> a, _RankedItem<T> b) {
  final byTier = a.tierOrdinal.compareTo(b.tierOrdinal);
  if (byTier != 0) return byTier;
  final byDate = b.lastTouchedMs.compareTo(a.lastTouchedMs);
  if (byDate != 0) return byDate;
  return a.titleLower.compareTo(b.titleLower);
}

/// Returns the [k] highest-ranked items in ranked order without sorting the
/// whole list. Maintains a small ordered buffer of the current best [k];
/// each candidate is only inserted when it can beat the current worst, so
/// the common case (candidate worse than the buffer's tail) is a single
/// cheap comparison.
List<T> _selectTopK<T>(List<_RankedItem<T>> survivors, int k) {
  final top = <_RankedItem<T>>[];
  for (final candidate in survivors) {
    if (top.length < k) {
      _insertSorted(top, candidate);
      continue;
    }
    // Buffer is full: skip anything that can't beat the current worst.
    if (_compareRanked(candidate, top[top.length - 1]) >= 0) {
      continue;
    }
    top.removeLast();
    _insertSorted(top, candidate);
  }
  return List<T>.generate(top.length, (i) => top[i].item, growable: false);
}

/// Inserts [candidate] into the already-sorted [buffer] (ascending by
/// [_compareRanked]) using a binary search for the insertion point.
void _insertSorted<T>(List<_RankedItem<T>> buffer, _RankedItem<T> candidate) {
  var lo = 0;
  var hi = buffer.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (_compareRanked(candidate, buffer[mid]) < 0) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  buffer.insert(lo, candidate);
}

/// Convenience: returns just the top-K ranked items, preserving the
/// per-tier recency order. Used by the title-bar dropdown which only
/// shows a small constant number of suggestions.
List<T> topRankedSearchResults<T>({
  required Iterable<T> entries,
  required String query,
  required SearchableEntryView Function(T) viewOf,
  required String Function(T) titleOf,
  required int limit,
  DateTime? now,
  Duration recentWindow = kVaultSearchRecentWindow,
}) {
  return rankSearchResults<T>(
    entries: entries,
    query: query,
    viewOf: viewOf,
    titleOf: titleOf,
    limit: math.max(0, limit),
    now: now,
    recentWindow: recentWindow,
  );
}
