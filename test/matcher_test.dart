import 'package:eventsport_tvguide/matcher.dart';
import 'package:test/test.dart';

void main() {
  final kickoff = DateTime.utc(2026, 11, 8, 14);
  TvProgramme prog(String channel, String title, String sub,
          {int offsetMin = -30, String desc = ''}) =>
      TvProgramme(
        channel: channel,
        startUtc: kickoff.add(Duration(minutes: offsetMin)),
        title: title,
        subTitle: sub,
        description: desc,
      );

  test('chaîne dédiée trouvée, programmes hors horaire ignorés', () {
    final result = matchFixturesToChannels(
      [
        FixtureRef(id: 'm1', kickoffUtc: kickoff, home: 'Rennes', away: 'Lille')
      ],
      [
        prog('Ligue 1+ 3', "Football : Ligue 1 McDonald's", 'Rennes / Lille'),
        prog('Ligue 1+', 'Rennes / Lille', 'Rediffusion',
            offsetMin: -600), // la nuit
        prog('La chaîne du Père Noël', 'Rennes / Lille',
            ''), // pas une chaîne de sport
      ],
    );
    expect(result['m1'], ['Ligue 1+ 3']);
  });

  test('noms traduits : Napoli → Naples, Barcelona → Barcelone', () {
    final result = matchFixturesToChannels(
      [
        FixtureRef(id: 'n', kickoffUtc: kickoff, home: 'Napoli', away: 'Lazio'),
        FixtureRef(
            id: 'b', kickoffUtc: kickoff, home: 'Atlético', away: 'Barcelona'),
      ],
      [
        prog('DAZN 1', 'Naples / Lazio Rome', 'Football. Serie A 11e journée.'),
        prog('DAZN 2', 'Atlético Madrid / FC Barcelone', 'Football. Liga.'),
      ],
    );
    expect(result['n'], ['DAZN 1']);
    expect(result['b'], ['DAZN 2']);
  });

  test('derby : Man Utd n’est pas confondu avec Man City', () {
    final result = matchFixturesToChannels(
      [
        FixtureRef(
            id: 'd', kickoffUtc: kickoff, home: 'Man Utd', away: 'Aston Villa')
      ],
      [
        prog('Canal+ Foot', 'Football : Premier League',
            'Manchester City / Aston Villa')
      ],
    );
    expect(result.containsKey('d'), isFalse);
  });

  test('la chaîne dédiée passe avant le multiplex', () {
    final fixtures = [
      FixtureRef(
          id: 'a', kickoffUtc: kickoff, home: 'Brighton', away: 'Brentford'),
      FixtureRef(
          id: 'c', kickoffUtc: kickoff, home: 'C Palace', away: 'Liverpool'),
    ];
    final result = matchFixturesToChannels(fixtures, [
      prog('Canal+ Foot', 'Multiplex Premier League', '',
          desc: 'Brighton / Brentford, Crystal Palace / Liverpool'),
      prog(
          'Canal+ Live 5', 'Football : Premier League', 'Brighton / Brentford'),
    ]);
    expect(result['a'], ['Canal+ Live 5', 'Canal+ Foot']);
  });

  test('normalisation des accents', () {
    expect(normalize('Atlético de Madrid / Séville'),
        'atletico de madrid seville');
  });
}
