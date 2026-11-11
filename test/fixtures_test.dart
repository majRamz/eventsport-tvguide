import 'dart:convert';

import 'package:eventsport_tvguide/countries.dart';
import 'package:eventsport_tvguide/fixtures.dart';
import 'package:eventsport_tvguide/matcher.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final kickoff = DateTime.utc(2026, 11, 14, 19);
  FixtureRef f(String home, String away) =>
      FixtureRef(id: 'x', kickoffUtc: kickoff, home: home, away: away);

  test('noms des pays : africains traduits, inconnus inchangés', () {
    expect(countryFr('Congo DR'), 'RD Congo');
    expect(countryFr('Cape Verde'), 'Cap-Vert');
    expect(countryFr('Italy'), 'Italie');
    expect(countryFr('Atlantis'), 'Atlantis');
  });

  test('amicaux : grandes sélections et toute l’Afrique gardées', () {
    expect(friendlyNations, containsAll(majorNations));
    expect(friendlyNations, containsAll(africanNationsFr.keys));
    expect(keepFixture('fifa.friendly', f('France', 'Andorra')), isTrue);
    expect(keepFixture('fifa.friendly', f('Benin', 'Togo')), isTrue);
    expect(keepFixture('fifa.friendly', f('Andorra', 'Malta')), isFalse);
    // Les autres compétitions ne sont pas filtrées.
    expect(keepFixture('uefa.nations', f('Andorra', 'Malta')), isTrue);
  });

  test('nouvelles compétitions suivies, alignées avec l’app', () {
    expect(
        leagues,
        containsAll([
          'uefa.europa',
          'uefa.europa.conf',
          'caf.champions',
          'caf.confed',
          'caf.nations',
          'caf.nations_qual',
        ]));
  });

  test('championnat inconnu d’ESPN ignoré, les autres gardés', () async {
    final event = {
      'id': '42',
      'date': kickoff.toIso8601String(),
      'competitions': [
        {
          'competitors': [
            {
              'homeAway': 'home',
              'team': {'displayName': 'Morocco'}
            },
            {
              'homeAway': 'away',
              'team': {'displayName': 'Congo DR'}
            },
          ]
        }
      ],
    };
    final client = MockClient((req) async {
      if (req.url.path.contains('/caf.nations/')) {
        return http.Response(
            jsonEncode({
              'events': [event]
            }),
            200);
      }
      return http.Response('not found', 404);
    });
    final warnings = <String>[];
    final fixtures = await fetchFixtures(
      kickoff.subtract(const Duration(days: 1)),
      kickoff.add(const Duration(days: 1)),
      client: client,
      onWarning: warnings.add,
    );
    expect(fixtures.map((x) => x.id), ['espn-42']);
    expect(fixtures.single.away, 'Congo DR');
    expect(warnings, hasLength(leagues.length - 1));
  });
}
