import 'dart:convert';

import 'package:http/http.dart' as http;

import 'matcher.dart';

/// Championnats suivis (identifiants ESPN). Doit rester aligné avec
/// `SourcesConfig.footballLeagues` dans l'app Event Sport.
const leagues = ['fra.1', 'uefa.champions', 'eng.1', 'esp.1', 'ita.1', 'ger.1'];

/// Matchs entre [from] et [to] (API publique ESPN, sans clé) : une requête
/// par championnat et par mois. Les identifiants sont ceux de l'app
/// (« espn-<id> »).
Future<List<FixtureRef>> fetchFixtures(DateTime from, DateTime to,
    {http.Client? client}) async {
  final c = client ?? http.Client();
  final months = <String>{
    for (var d = DateTime.utc(from.year, from.month);
        !d.isAfter(to);
        d = DateTime.utc(d.year, d.month + 1))
      '${d.year}${d.month.toString().padLeft(2, '0')}',
  };
  final fixtures = <FixtureRef>[];
  for (final league in leagues) {
    for (final month in months) {
      final uri = Uri.https('site.api.espn.com',
          '/apis/site/v2/sports/soccer/$league/scoreboard', {'dates': month});
      final res = await c.get(uri);
      if (res.statusCode != 200) {
        throw Exception('ESPN $league $month : HTTP ${res.statusCode}');
      }
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      for (final e in (body['events'] as List? ?? const [])) {
        final f = _toFixture(e as Map<String, dynamic>);
        if (f != null &&
            !f.kickoffUtc.isBefore(from) &&
            f.kickoffUtc.isBefore(to)) {
          fixtures.add(f);
        }
      }
    }
  }
  return fixtures;
}

FixtureRef? _toFixture(Map<String, dynamic> json) {
  try {
    final comp = (json['competitions'] as List).first as Map<String, dynamic>;
    final teams = (comp['competitors'] as List).cast<Map<String, dynamic>>();
    String name(String side) {
      final t = teams.firstWhere((c) => c['homeAway'] == side)['team'] as Map;
      return (t['shortDisplayName'] ?? t['displayName']) as String;
    }

    return FixtureRef(
      id: 'espn-${json['id']}',
      kickoffUtc: DateTime.parse(json['date'] as String).toUtc(),
      home: name('home'),
      away: name('away'),
    );
  } catch (_) {
    return null;
  }
}
