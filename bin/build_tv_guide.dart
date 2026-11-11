// Construit tv_guide.json : pour chaque match de foot des prochains jours,
// les chaînes françaises qui le diffusent, d'après le guide TV gratuit
// xmltvfr.fr (téléchargé une seule fois). Lancé chaque nuit par GitHub
// Actions (.github/workflows/update.yml) ; l'app ne lit que le résultat.
//
//   dart run bin/build_tv_guide.dart [--out public/tv_guide.json]
import 'dart:convert';
import 'dart:io';

import 'package:eventsport_tvguide/fixtures.dart';
import 'package:eventsport_tvguide/matcher.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml_events.dart';

const guideUrl = 'https://xmltvfr.fr/xmltv/xmltv_fr.xml.gz';

Future<void> main(List<String> args) async {
  final outIndex = args.indexOf('--out');
  final out = outIndex >= 0 ? args[outIndex + 1] : 'public/tv_guide.json';
  final now = DateTime.now().toUtc();

  stdout.writeln('1/3 Matchs (ESPN)…');
  final List<FixtureRef> fixtures;
  try {
    fixtures = await fetchFixtures(now.subtract(const Duration(days: 1)),
        now.add(const Duration(days: 6)));
  } on EspnUnavailableException catch (e) {
    // Échec volontaire : le workflow ne déploie pas, l'ancien guide reste.
    stderr.writeln('$e → tv_guide.json non modifié');
    exit(1);
  }
  stdout.writeln('    ${fixtures.length} matchs');

  stdout.writeln('2/3 Guide TV ($guideUrl)…');
  final res = await http
      .get(Uri.parse(guideUrl), headers: {'User-Agent': 'EventSport/1.0'});
  if (res.statusCode != 200) {
    stderr.writeln('Guide TV indisponible (HTTP ${res.statusCode})');
    exit(1);
  }
  final xmlText = utf8.decode(gzip.decode(res.bodyBytes), allowMalformed: true);
  final programmes =
      _parseProgrammes(xmlText, from: now.subtract(const Duration(days: 1)));
  stdout.writeln('    ${programmes.length} programmes de sport retenus');

  stdout.writeln('3/3 Correspondances…');
  final channels = matchFixturesToChannels(fixtures, programmes);
  final json = {
    'generatedAt': now.toIso8601String(),
    'source': 'xmltvfr.fr',
    'channels': channels,
    // Détails des matchs diffusés : secours de l'app si ESPN ne répond plus.
    'matches': buildMatches(fixtures, channels),
  };
  File(out)
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent(' ').convert(json));
  stdout.writeln(
      '    ${channels.length}/${fixtures.length} matchs avec leur chaîne → $out '
      '(${File(out).lengthSync()} octets)');
}

/// Lecture en flux du XMLTV : on ne garde que le titre, le sous-titre et
/// le début de la description des programmes des chaînes de sport.
List<TvProgramme> _parseProgrammes(String xmlText, {required DateTime from}) {
  final sport = RegExp(
      r'bein|canal|ligue 1|dazn|eurosport|quipe|m6|w9|tf1|tmc|france [2-4]|rmc|prime|amazon', // « quipe » : L'Équipe (É accentué)
      caseSensitive: false);
  final channelNames = <String, String>{};
  final programmes = <TvProgramme>[];

  String? element, channelId, progChannel, progStart;
  final text = <String, StringBuffer>{};

  for (final event in parseEvents(xmlText)) {
    if (event is XmlStartElementEvent) {
      element = event.name;
      String? attr(String name) => event.attributes
          .where((a) => a.name == name)
          .map((a) => a.value)
          .firstOrNull;
      if (event.name == 'channel') channelId = attr('id');
      if (event.name == 'programme') {
        progChannel = attr('channel');
        progStart = attr('start');
        text.clear();
      }
    } else if (event is XmlTextEvent || event is XmlCDATAEvent) {
      final value =
          event is XmlTextEvent ? event.value : (event as XmlCDATAEvent).value;
      if (element == 'display-name' && channelId != null) {
        channelNames.putIfAbsent(channelId, () => value.trim());
      } else if (progChannel != null &&
          (element == 'title' || element == 'sub-title' || element == 'desc')) {
        text.putIfAbsent(element!, StringBuffer.new).write(value);
      }
    } else if (event is XmlEndElementEvent) {
      if (event.name == 'channel') channelId = null;
      if (event.name == 'programme') {
        final name = channelNames[progChannel] ?? '';
        final start = _parseXmltvDate(progStart ?? '');
        if (start != null && !start.isBefore(from) && sport.hasMatch(name)) {
          final desc = text['desc']?.toString() ?? '';
          programmes.add(TvProgramme(
            channel: name,
            startUtc: start,
            title: text['title']?.toString() ?? '',
            subTitle: text['sub-title']?.toString() ?? '',
            description: desc.length > 300 ? desc.substring(0, 300) : desc,
          ));
        }
        progChannel = null;
      }
      element = null;
    }
  }
  return programmes;
}

/// « 20261108143000 +0100 » → instant UTC.
DateTime? _parseXmltvDate(String s) {
  final m =
      RegExp(r'^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)?\s*([+-])(\d\d)(\d\d)')
          .firstMatch(s);
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i) ?? '0');
  final local = DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
  final offset = Duration(hours: g(8), minutes: g(9));
  return m.group(7) == '+' ? local.subtract(offset) : local.add(offset);
}
