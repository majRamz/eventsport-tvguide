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
/// Si *aucune* requête n'aboutit : [EspnUnavailableException].
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
  var answered = 0; // requêtes ESPN réussies
  for (final league in leagues) {
    for (final month in months) {
      // `limit` : sans lui, ESPN renvoie au plus 100 matchs (un mois
      // d'amicaux en compte davantage). Même valeur que dans l'app.
      final uri = Uri.https(
          'site.api.espn.com',
          '/apis/site/v2/sports/soccer/$league/scoreboard',
          {'dates': month, 'limit': '500'});
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
      answered++;
      for (final e in (body['events'] as List? ?? const [])) {
        final f = _toFixture(e as Map<String, dynamic>, league);
        if (f != null &&
            !f.kickoffUtc.isBefore(from) &&
            f.kickoffUtc.isBefore(to) &&
            keepFixture(league, f)) {
          fixtures.add(f);
        }
      }
    }
  }
  // ESPN en panne partout : on échoue plutôt que de publier un guide vide
  // (le workflow s'arrête, le tv_guide.json précédent reste en ligne).
  if (answered == 0) {
    throw EspnUnavailableException('aucune réponse ESPN sur '
        '${leagues.length} championnats × ${months.length} mois');
  }
  return fixtures;
}

/// Clé `matches` de tv_guide.json : détails des seuls matchs présents dans
/// [channels] (ceux qu'une chaîne française diffuse).
Map<String, Map<String, Object?>> buildMatches(
        List<FixtureRef> fixtures, Map<String, List<String>> channels) =>
    {
      for (final f in fixtures)
        if (channels.containsKey(f.id)) f.id: f.toJson(),
    };

/// Aucune requête ESPN n'a abouti pendant un calcul.
class EspnUnavailableException implements Exception {
  EspnUnavailableException(this.message);
  final String message;
  @override
  String toString() => 'ESPN indisponible : $message';
}

FixtureRef? _toFixture(Map<String, dynamic> json, String league) {
  try {
    final comp = (json['competitions'] as List).first as Map<String, dynamic>;
    final teams = (comp['competitors'] as List).cast<Map<String, dynamic>>();
    Map team(String side) =>
        teams.firstWhere((c) => c['homeAway'] == side)['team'] as Map;
    // Nom complet : plus fiable pour les sélections (« Northern Ireland »).
    String name(String side) =>
        (team(side)['displayName'] ?? team(side)['shortDisplayName']) as String;
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    final venue = comp['venue'] as Map?;

    return FixtureRef(
      id: 'espn-${json['id']}',
      kickoffUtc: DateTime.parse(json['date'] as String).toUtc(),
      home: name('home'),
      away: name('away'),
      league: league,
      homeLogo: text(team('home')['logo']),
      awayLogo: text(team('away')['logo']),
      venue: text(venue?['fullName']),
      city: text((venue?['address'] as Map?)?['city']),
    );
  } catch (_) {
    return null;
  }
}
