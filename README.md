# Event Sport — guide TV

Fichier `tv_guide.json` utilisé par l'app **Event Sport** : pour chaque match
de football des prochains jours, les chaînes françaises qui le diffusent.

- **Adresse :** https://majramz.github.io/eventsport-tvguide/tv_guide.json
- **Mise à jour :** automatique, chaque nuit (GitHub Actions).
- **Sources :** matchs via l'API publique d'ESPN, programmes TV via
  [XML TV Fr](https://xmltvfr.fr) (guide téléchargé une seule fois par mise à
  jour, par respect pour ce service gratuit).

Format :

```json
{
  "generatedAt": "2026-11-08T14:37:04Z",
  "source": "xmltvfr.fr",
  "channels": { "espn-401876407": ["Ligue 1+ 3"] }
}
```

Lancer à la main : `dart run bin/build_tv_guide.dart`
