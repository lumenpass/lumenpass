import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/vault/application/vault_search_ranking.dart';

/// Convenience builder so individual tests stay readable.
SearchableEntryView _entry({
  required String title,
  String url = '',
  String username = '',
  String notes = '',
  String otpAuthUrl = '',
  List<String> tags = const <String>[],
  List<MapEntry<String, String>> extras = const <MapEntry<String, String>>[],
  DateTime? lastTouchedAt,
}) {
  return SearchableEntryView(
    title: title,
    url: url,
    username: username,
    notes: notes,
    otpAuthUrl: otpAuthUrl,
    tags: tags,
    extraFields: extras,
    lastTouchedAt: lastTouchedAt ?? DateTime(2026, 1, 1),
  );
}

void main() {
  // Anchor "now" so the recency window is deterministic across tests.
  final now = DateTime(2026, 5, 1);

  group('normalizeQueryTerms', () {
    test('splits on whitespace and lower-cases', () {
      expect(normalizeQueryTerms('  iCloud   COM '), ['icloud', 'com']);
    });

    test('returns empty list for blank input', () {
      expect(normalizeQueryTerms(''), isEmpty);
      expect(normalizeQueryTerms('   '), isEmpty);
    });
  });

  group('searchRankFor — tier ordering', () {
    test('URL match outranks email match (the icloud regression)', () {
      final urlMatch = _entry(
        title: 'iCloud.com',
        url: 'https://icloud.com',
        username: 'techie@asme.org.sg',
      );
      final emailMatch = _entry(
        title: 'x.com',
        url: 'https://x.com',
        username: 'empathy-gesture.4i@icloud.com',
      );

      final terms = normalizeQueryTerms('icloud');
      final urlRank = searchRankFor(urlMatch, terms, now: now);
      final emailRank = searchRankFor(emailMatch, terms, now: now);

      expect(urlRank.tier, SearchTier.urlMatch);
      expect(emailRank.tier, SearchTier.emailMatch);
      expect(urlRank.tier.ordinal, lessThan(emailRank.tier.ordinal));
    });

    test('title-only match lands in titleMatch tier', () {
      final v = _entry(title: 'My Banking Notes');
      expect(
        searchRankFor(v, normalizeQueryTerms('banking'), now: now).tier,
        SearchTier.titleMatch,
      );
    });

    test('notes-only match lands in notesMatch tier', () {
      final v = _entry(title: 'Random', notes: 'recovery codes for foo');
      expect(
        searchRankFor(v, normalizeQueryTerms('recovery'), now: now).tier,
        SearchTier.notesMatch,
      );
    });

    test('non-match returns SearchTier.none', () {
      final v = _entry(title: 'Hello', url: 'https://hello.com');
      final r = searchRankFor(v, normalizeQueryTerms('zzz'), now: now);
      expect(r.tier, SearchTier.none);
      expect(r.matches, isFalse);
    });
  });

  group('recently used promotion', () {
    test('promotes title-tier match to recentlyUsed when within window', () {
      final v = _entry(
        title: 'Banking',
        // 5 days before "now" → inside the default 30-day window.
        lastTouchedAt: now.subtract(const Duration(days: 5)),
      );
      final r = searchRankFor(v, normalizeQueryTerms('banking'), now: now);
      expect(r.tier, SearchTier.recentlyUsed);
    });

    test('does not promote when outside the recency window', () {
      final v = _entry(
        title: 'Banking',
        lastTouchedAt: now.subtract(const Duration(days: 90)),
      );
      final r = searchRankFor(v, normalizeQueryTerms('banking'), now: now);
      expect(r.tier, SearchTier.titleMatch);
    });

    test('never demotes a URL match', () {
      final v = _entry(
        title: 'Banking',
        url: 'https://banking.com',
        // Even very recent — URL must remain Tier 1.
        lastTouchedAt: now.subtract(const Duration(hours: 1)),
      );
      final r = searchRankFor(v, normalizeQueryTerms('banking'), now: now);
      expect(r.tier, SearchTier.urlMatch);
    });

    test('zero-epoch lastTouched never qualifies as recent', () {
      final v = _entry(
        title: 'Banking',
        lastTouchedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final r = searchRankFor(v, normalizeQueryTerms('banking'), now: now);
      expect(r.tier, SearchTier.titleMatch);
    });
  });

  group('email detection', () {
    test('matches via username that looks like an email', () {
      final v = _entry(
        title: 'Some Site',
        username: 'tranit1209@icloud.com',
      );
      final r = searchRankFor(v, normalizeQueryTerms('icloud'), now: now);
      expect(r.tier, SearchTier.emailMatch);
    });

    test('matches via custom field whose key contains "email"', () {
      final v = _entry(
        title: 'Some Site',
        extras: const [MapEntry('Recovery Email', 'foo@icloud.com')],
      );
      final r = searchRankFor(v, normalizeQueryTerms('icloud'), now: now);
      expect(r.tier, SearchTier.emailMatch);
    });

    test('non-email username is treated as notes content', () {
      final v = _entry(
        title: 'Some Site',
        username: 'plain_username_no_at',
      );
      final r = searchRankFor(
        v,
        normalizeQueryTerms('plain'),
        now: now,
      );
      // Username without `@` should not promote to email tier.
      expect(r.tier, SearchTier.notesMatch);
    });
  });

  group('rankSearchResults — full ordering', () {
    test('icloud query: URL > recently-used email > stale email > notes', () {
      final entries = <SearchableEntryView>[
        _entry(
          title: 'x.com',
          url: 'https://x.com',
          username: 'empathy-gesture.4i@icloud.com',
          lastTouchedAt: now.subtract(const Duration(days: 1)), // recent
        ),
        _entry(
          title: 'iCloud.com',
          url: 'https://icloud.com',
          username: 'techie@asme.org.sg',
          lastTouchedAt: now.subtract(const Duration(days: 200)), // old
        ),
        _entry(
          title: 'my-team.setapp.com',
          url: 'https://my-team.setapp.com',
          username: 'tranit1209@icloud.com',
          lastTouchedAt: now.subtract(const Duration(days: 365)),
        ),
        _entry(
          title: 'Random Notes',
          notes: 'icloud backup steps',
          lastTouchedAt: now.subtract(const Duration(days: 2)),
        ),
      ];

      final ranked = rankSearchResults<SearchableEntryView>(
        entries: entries,
        query: 'icloud',
        viewOf: (e) => e,
        titleOf: (e) => e.title,
        now: now,
      );

      expect(ranked.length, 4);
      // 1st: URL match (iCloud.com) — wins despite being old.
      expect(ranked[0].title, 'iCloud.com');
      // 2nd: x.com — email match recently used → recentlyUsed tier.
      expect(ranked[1].title, 'x.com');
      // 3rd: notes match recently used → recentlyUsed tier (after email by recency).
      // x.com touched 1d ago vs notes 2d ago → x.com first.
      expect(ranked[2].title, 'Random Notes');
      // 4th: setapp — stale email match.
      expect(ranked[3].title, 'my-team.setapp.com');
    });

    test('within tier, more recently used appears first', () {
      final entries = <SearchableEntryView>[
        _entry(
          title: 'A',
          url: 'https://example.com/a',
          lastTouchedAt: DateTime(2026, 4, 10),
        ),
        _entry(
          title: 'B',
          url: 'https://example.com/b',
          lastTouchedAt: DateTime(2026, 4, 25),
        ),
        _entry(
          title: 'C',
          url: 'https://example.com/c',
          lastTouchedAt: DateTime(2026, 4, 1),
        ),
      ];
      final ranked = rankSearchResults<SearchableEntryView>(
        entries: entries,
        query: 'example',
        viewOf: (e) => e,
        titleOf: (e) => e.title,
        now: now,
      );
      expect(ranked.map((e) => e.title), ['B', 'A', 'C']);
    });

    test('limit caps the result set', () {
      final entries = List<SearchableEntryView>.generate(
        50,
        (i) => _entry(
          title: 'Item $i',
          url: 'https://example$i.com',
          lastTouchedAt: now.subtract(Duration(days: i)),
        ),
      );
      final ranked = rankSearchResults<SearchableEntryView>(
        entries: entries,
        query: 'example',
        viewOf: (e) => e,
        titleOf: (e) => e.title,
        limit: 6,
        now: now,
      );
      expect(ranked, hasLength(6));
    });

    test('empty query returns input untouched', () {
      final entries = [_entry(title: 'A'), _entry(title: 'B')];
      final ranked = rankSearchResults<SearchableEntryView>(
        entries: entries,
        query: '   ',
        viewOf: (e) => e,
        titleOf: (e) => e.title,
        now: now,
      );
      expect(ranked.map((e) => e.title), ['A', 'B']);
    });
  });

  group('multi-term and case-insensitive matching', () {
    test('all terms must appear somewhere', () {
      final v = _entry(
        title: 'Acme Banking',
        url: 'https://acme.com',
      );
      expect(
        searchRankFor(v, normalizeQueryTerms('acme banking'), now: now).matches,
        isTrue,
      );
      expect(
        searchRankFor(v, normalizeQueryTerms('acme nope'), now: now).matches,
        isFalse,
      );
    });

    test('different terms in different fields → strongest tier wins', () {
      // "icloud" matches URL (Tier 1), "banking" matches title (Tier 4).
      // The strongest single-term tier any term hits is Tier 1 → urlMatch.
      final v = _entry(
        title: 'My Banking',
        url: 'https://login.icloud.com',
      );
      final r = searchRankFor(
        v,
        normalizeQueryTerms('icloud banking'),
        now: now,
      );
      expect(r.tier, SearchTier.urlMatch);
    });

    test('case-insensitive across all fields', () {
      final v = _entry(
        title: 'ACME',
        url: 'HTTPS://EXAMPLE.COM',
        username: 'USER@EXAMPLE.COM',
      );
      expect(
        searchRankFor(v, normalizeQueryTerms('acme'), now: now).tier,
        SearchTier.titleMatch,
      );
      expect(
        searchRankFor(v, normalizeQueryTerms('example'), now: now).tier,
        SearchTier.urlMatch,
      );
    });
  });

  group('special characters and international domains', () {
    test('matches URL with port and path', () {
      final v = _entry(
        title: 'Local Dev',
        url: 'http://localhost:8080/admin',
      );
      expect(
        searchRankFor(v, normalizeQueryTerms('localhost'), now: now).tier,
        SearchTier.urlMatch,
      );
      expect(
        searchRankFor(v, normalizeQueryTerms(':8080'), now: now).tier,
        SearchTier.urlMatch,
      );
    });

    test('matches IDN / unicode domain', () {
      final v = _entry(
        title: 'Bücher',
        url: 'https://bücher.example',
      );
      expect(
        searchRankFor(v, normalizeQueryTerms('bücher'), now: now).tier,
        SearchTier.urlMatch,
      );
    });

    test('matches punycode form', () {
      final v = _entry(
        title: 'Punycode',
        url: 'https://xn--bcher-kva.example',
      );
      expect(
        searchRankFor(v, normalizeQueryTerms('xn--bcher'), now: now).tier,
        SearchTier.urlMatch,
      );
    });

    test('matches scheme-less and trailing-slash URLs', () {
      final a = _entry(title: 'A', url: 'icloud.com');
      final b = _entry(title: 'B', url: 'https://icloud.com/');
      expect(
        searchRankFor(a, normalizeQueryTerms('icloud'), now: now).tier,
        SearchTier.urlMatch,
      );
      expect(
        searchRankFor(b, normalizeQueryTerms('icloud'), now: now).tier,
        SearchTier.urlMatch,
      );
    });

    test('special characters in query are treated literally', () {
      final v = _entry(title: 'C++ Notes', url: 'https://c-plus.dev');
      // No regex semantics — `+` should be a literal character.
      expect(
        searchRankFor(v, normalizeQueryTerms('c++'), now: now).tier,
        SearchTier.titleMatch,
      );
    });
  });

  group('performance smoke', () {
    test('large dataset stays well under a budget per query', () {
      final entries = List<SearchableEntryView>.generate(
        5000,
        (i) => _entry(
          title: 'Entry $i',
          url: i % 7 == 0 ? 'https://icloud.com/$i' : 'https://example$i.com',
          username: i % 5 == 0 ? 'user$i@icloud.com' : 'user$i@example.com',
          notes: i % 11 == 0 ? 'icloud backup notes' : 'random notes',
          lastTouchedAt:
              DateTime(2026, 1, 1).add(Duration(minutes: i)),
        ),
      );

      final sw = Stopwatch()..start();
      final ranked = rankSearchResults<SearchableEntryView>(
        entries: entries,
        query: 'icloud',
        viewOf: (e) => e,
        titleOf: (e) => e.title,
        now: now,
      );
      sw.stop();

      expect(ranked, isNotEmpty);
      // Top hit must be a URL-match.
      expect(ranked.first.url.contains('icloud.com'), isTrue);
      // Generous CI-friendly budget; locally this is a few ms.
      expect(
        sw.elapsedMilliseconds,
        lessThan(500),
        reason: 'ranking 5k entries should be fast',
      );
    });
  });
}
