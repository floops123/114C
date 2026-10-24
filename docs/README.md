# Documentation de C411 Remote

Bienvenue ! Cette documentation est en deux parties : le **guide** pour se
servir de l'application, et les **notes de développement** pour comprendre
et faire évoluer le code.

## Guide d'utilisation

| Page | Pour… |
|---|---|
| [Installation](guide/installation.md) | installer l'application sur Linux ou Android |
| [Configuration](guide/configuration.md) | brancher Transmission, les trackers, TMDB, le FTP, Jellyfin |
| [Films & séries](guide/films-et-series.md) | les tops TMDB et ta liste : lire ce que tu as, télécharger ce qui manque |
| [Trackers](guide/trackers.md) | les sorties de tous les trackers, regroupées par titre |
| [Import en masse](guide/import-en-masse.md) | filtrer, cocher, envoyer d'un coup |
| [Nouveautés](guide/nouveautes.md) | surveiller les trackers et être prévenu des nouvelles sorties |
| [Sur le disque et lecture](guide/sur-le-disque.md) | ta vidéothèque, le lecteur intégré |
| [Transferts](guide/transferts.md) | piloter Transmission |
| [Cross-seed et sans seeder](guide/cross-seed.md) | partager sur plusieurs trackers, relancer les torrents morts |
| [C411 et Salon](guide/notifications.md) | suivre C411 en direct : notifications, compte, salon |
| [Rendement Zen](guide/zen.md) | ce que rapporte chaque torrent, ce qu'il serait rentable d'ajouter |
| [Dépannage](guide/depannage.md) | quand quelque chose ne marche pas |

## Notes de développement

| Page | Contenu |
|---|---|
| [Architecture](dev/architecture.md) | dossiers, couches, état Riverpod, flux de données |
| [Notes sur les API](dev/api.md) | ce qu'on a appris de chaque service (endpoints, pièges) |
| [Interface et performances](dev/interface.md) | thème, composants partagés, fluidité |
| [Compilation personnalisée](dev/build.md) | variante avec réglages préenregistrés via `--dart-define` |
| [Tests](dev/tests.md) | lancer les tests, ce que couvre chaque fichier |

## En un coup d'œil

```
              ┌───────────────── C411 Remote ─────────────────┐
              │  Films & séries · Trackers · Transferts ·     │
              │  C411 · Salon · Réglages     + lecteur (mpv)  │
              └──┬──────────┬──────────┬──────────┬───────┬───┘
                 │          │          │          │       │
          Trackers      Transmission   TMDB     FTP(S)  Jellyfin
   C411 · tr4ker ·      (RPC)         (fiches)  seedbox  (facultatif)
   Nostradamus · Draupnirr · V3X · Astra
```

L'application est entièrement cliente : elle parle à chaque service
directement, avec tes identifiants, depuis ton appareil.
