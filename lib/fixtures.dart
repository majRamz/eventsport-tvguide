import 'dart:convert';

import 'package:http/http.dart' as http;

import 'countries.dart';
import 'matcher.dart';

/// Championnats suivis (identifiants ESPN). Doit rester aligné avec
/// `SourcesConfig.footballLeagues` dans l'app Event Sport.
const leagues = [
  'fra.1', 'uefa.champions', 'eng.1', 'esp.1', 'ita.1', 'ger.1',
  'uefa.europa', 'uefa.europa.conf',
  // Clubs africains
  'caf.champions', 'caf.confed',
  // Sélections nationales
  'uefa.nations', 'caf.nations', 'caf.nations_qual', 'fifa.friendly',
];

/// Compétitions filtrées comme dans l'app (`SourcesConfig.majorNationsOnly`) :
/// seuls les matchs d'une sélection de [friendlyNations] sont gardés.
const majorNationsOnly = {'fifa.friendly'};

/// Garde-t-on ce match de [league] ? (amicaux : au moins une sélection suivie).
bool keepFixture(String league, FixtureRef f) =>
    !majorNationsOnly.contains(league) ||
    friendlyNations.contains(f.home) ||
    friendlyNations.contains(f.away);

/// Matchs entre [from] et [to] (API publique ESPN, sans clé) : une requête
/// par championnat et par mois. Les identifiants sont ceux de l'app
/// (« espn-<id> »). Un championnat en erreur (identifiant inconnu d'ESPN,
/// panne passagère) est signalé et ignoré : les autres restent calculés.
Future<List<FixtureRef>> fetchFixtures(DateTime from, DateTime to,
    {http.Client? client, void Function(String)? onWarning}) async {
  final warn = onWarning ?? print;
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
      Map<String, dynamic>? body;
      try {
        final res = await c.get(uri);
        if (res.statusCode == 200) {
          body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        } else {
          warn('    ⚠ ESPN $league $month : HTTP ${res.statusCode}, ignoré');
        }
      } catch (e) {
        warn('    ⚠ ESPN $league $month : $e, ignoré');
      }
      if (body == null) continue;
      for (final e in (body['events'] as List? ?? const [])) {
        final f = _toFixture(e as Map<String, dynamic>);
        if (f != null &&
            !f.kickoffUtc.isBefore(from) &&
            f.kickoffUtc.isBefore(to) &&
            keepFixture(league, f)) {
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
      // Nom complet : plus fiable pour les sélections (« Northern Ireland »).
      return (t['displayName'] ?? t['shortDisplayName']) as String;
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
