// Correspondance matchs ↔ programmes d'un guide TV (XMLTV).
// Utilisé par bin/build_tv_guide.dart.
import 'countries.dart';

/// Un programme du guide TV.
class TvProgramme {
  const TvProgramme({
    required this.channel,
    required this.startUtc,
    required this.title,
    this.subTitle = '',
    this.description = '',
  });

  final String channel;
  final DateTime startUtc;
  final String title;
  final String subTitle;
  final String description;
}

/// Un match à rechercher dans le guide.
class FixtureRef {
  const FixtureRef({
    required this.id,
    required this.kickoffUtc,
    required this.home,
    required this.away,
    this.league = '',
    this.homeLogo,
    this.awayLogo,
    this.venue,
    this.city,
  });

  final String id;
  final DateTime kickoffUtc;

  /// Noms ESPN bruts (anglais) : l'app les traduit elle-même.
  final String home;
  final String away;

  /// Détails publiés dans `matches` (secours de l'app si ESPN tombe).
  final String league;
  final String? homeLogo;
  final String? awayLogo;
  final String? venue;
  final String? city;

  Map<String, Object?> toJson() => {
        'league': league,
        'start': kickoffUtc.toUtc().toIso8601String(),
        'home': home,
        'away': away,
        'homeLogo': homeLogo,
        'awayLogo': awayLogo,
        'venue': venue,
        'city': city,
      };
}

/// Chaînes de sport retenues (on ignore les chaînes thématiques non sportives).
/// Testée sur le nom de chaîne *normalisé* (sans accents ni ponctuation :
/// « La chaîne L'Équipe » → « la chaine l equipe », « Canal+ Foot » →
/// « canal foot »). Chaînes belges, suisses… volontairement exclues.
final _sportChannel = RegExp(
  r"bein|^canal( (foot|sport|live|premier|ligue))?|ligue 1|dazn|eurosport|"
  r"\bl ?equipe\b|^m6$|^w9$|^tf1$|^tmc$|^france [2-4]\b|rmc sport|prime video|amazon",
);

/// Noms ESPN (souvent anglais) → noms utilisés par les guides TV français.
const _aliases = <String, List<String>>{
  'napoli': ['naples'],
  'barcelona': ['barcelone'],
  'freiburg': ['fribourg'],
  'sevilla': ['seville'],
  'mallorca': ['majorque'],
  'mainz': ['mayence'],
  'monchengladbach': ['gladbach'],
  'gladbach': ['gladbach'],
  'inter milan': ['inter'],
  'internazionale': ['inter'],
  'ac milan': ['milan'],
  'roma': ['rome'],
  'atletico': ['atletico madrid', 'atletico'],
  'athletic club': ['bilbao'],
  'man utd': ['manchester united', 'manchester utd'],
  'man united': ['manchester united'],
  'man city': ['manchester city'],
  'c palace': ['crystal palace'],
  'spurs': ['tottenham'],
  'wolves': ['wolverhampton'],
  'nottm forest': ['nottingham'],
  'psg': ['paris sg', 'paris saint germain', 'psg'],
  'paris saint germain': ['paris sg', 'psg'],
  'bayern munich': ['bayern'],
  'cologne': ['cologne'],
  'le havre ac': ['le havre'],
};

/// Mots trop courants pour identifier une équipe.
const _stopWords = {
  'fc',
  'ac',
  'as',
  'sc',
  'cf',
  'rc',
  'afc',
  'ssc',
  'club',
  'de',
  'du',
  'la',
  'le',
  'les',
  'real',
  'stade',
  'olympique',
  'united',
  'city',
  'sporting',
  'athletic',
  'racing',
  'football',
  'calcio',
  'vfb',
  'vfl',
  'tsg',
  'fsv',
  'sv',
  'borussia',
  'hotspur',
  'albion',
  'town',
  'and',
};

String normalize(String s) {
  const accents = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'ã': 'a',
    'å': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'õ': 'o',
    'ø': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
    'ß': 'ss',
  };
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(accents[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Expressions qui désignent une équipe : alias (gardés en entier, ils
/// sont choisis à la main) + nom d'origine sans les mots trop courants.
List<List<String>> _teamPhrases(String team) {
  final n = normalize(team);
  final aliases = <String>{...?_aliases[n]};
  // Sélections : nom français du pays (« Italy » → « italie »,
  // « Congo DR » → « rd congo »).
  for (final entry in allCountryNamesFr.entries) {
    if (normalize(entry.key) == n) aliases.add(normalize(entry.value));
  }
  for (final entry in _aliases.entries) {
    if (n.contains(entry.key)) aliases.addAll(entry.value);
  }
  List<String> words(String p, {required bool strict}) => p
      .split(' ')
      .where((w) => w.length >= 3 && (!strict || !_stopWords.contains(w)))
      .toList();
  return [
    words(n, strict: true),
    for (final alias in aliases) words(alias, strict: false),
  ].where((w) => w.isNotEmpty).toList();
}

bool _mentions(List<String> textWords, List<List<String>> phrases) {
  bool wordHit(String w) {
    final stem = w.length > 6 ? w.substring(0, 6) : w;
    return textWords.any((t) => t.startsWith(stem));
  }

  return phrases.any((words) => words.every(wordHit));
}

/// Pour chaque match, les chaînes qui le diffusent en direct d'après le
/// guide (chaîne dédiée d'abord, multiplex ensuite). Les matchs introuvables
/// sont absents du résultat : l'app utilise alors la table des droits.
Map<String, List<String>> matchFixturesToChannels(
  List<FixtureRef> fixtures,
  List<TvProgramme> programmes, {
  Duration before = const Duration(minutes: 50),
  Duration after = const Duration(minutes: 20),
  int maxChannels = 3,
}) {
  final candidates = programmes
      .where((p) => _sportChannel.hasMatch(normalize(p.channel)))
      .toList();
  final phrases = {
    for (final f in fixtures)
      f.id: (home: _teamPhrases(f.home), away: _teamPhrases(f.away)),
  };

  // Pour chaque programme : les matchs qu'il mentionne (plusieurs = multiplex).
  final hits = <TvProgramme, List<({FixtureRef fixture, bool inTitle})>>{};
  for (final p in candidates) {
    final titleWords = normalize('${p.title} ${p.subTitle}').split(' ');
    final allWords = [...titleWords, ...normalize(p.description).split(' ')];
    for (final f in fixtures) {
      final diff = p.startUtc.difference(f.kickoffUtc);
      if (diff < -before || diff > after) continue;
      final ph = phrases[f.id]!;
      final inTitle =
          _mentions(titleWords, ph.home) && _mentions(titleWords, ph.away);
      if (inTitle ||
          (_mentions(allWords, ph.home) && _mentions(allWords, ph.away))) {
        hits.putIfAbsent(p, () => []).add((fixture: f, inTitle: inTitle));
      }
    }
  }

  final scored = <String, List<({String channel, int score, int gap})>>{};
  hits.forEach((p, list) {
    final multiplex = list.length > 1;
    for (final h in list) {
      final score = (h.inTitle ? 2 : 1) - (multiplex ? 2 : 0);
      final gap = p.startUtc.difference(h.fixture.kickoffUtc).inMinutes.abs();
      scored
          .putIfAbsent(h.fixture.id, () => [])
          .add((channel: p.channel, score: score, gap: gap));
    }
  });

  return {
    for (final entry in scored.entries)
      entry.key: (entry.value
            ..sort((a, b) =>
                a.score != b.score ? b.score - a.score : a.gap - b.gap))
          .map((c) => c.channel)
          .toSet()
          .take(maxChannels)
          .toList(),
  };
}
