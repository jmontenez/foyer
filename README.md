# Foyer

Application personnelle pour deux personnes : APK Android Flutter natif et interface web, API ASP.NET Core 10 et PostgreSQL 17. Hébergement prévu sur le Mac via Docker Compose et HTTPS Tailscale.

## Ce qui est implémenté

- Aujourd’hui, Cette semaine, tableau avec étapes personnalisables, backlog séparé et historique.
- Attribution multiple, distinction obligation/envie, priorités, dates facultatives, tags colorés, checklist et images privées.
- Commentaires, recherche et historique des modifications ; réalisateurs choisis explicitement à la clôture.
- 11 palettes personnelles avec aperçu, dont bleu ciel/orange et violet/bleu nuit, synchronisées entre appareils.
- Connexion Google limitée à deux adresses, sessions révocables et détection des éditions concurrentes.
- Automatisations serveur : activation à la date de début, résumé quotidien à une heure propre à chacun et notifications Android FCM avec reprises.
- Export chiffré base/images, restauration sur cible vierge et procédure de retour arrière.

Le code est fonctionnel en démonstration locale. **Les parcours Google, la réception FCM sur téléphone, la signature personnelle de l’APK et le déploiement sur le Mac Intel restent à configurer et à valider avec vos comptes et appareils.** Aucun secret de production n’est fourni.

## Essayer sur le poste de développement

Prérequis : Flutter stable (version utilisée : 3.47.5), .NET SDK 10.0.401, Docker actif et Python 3.12+. Les outils peuvent être sélectionnés avec `FLUTTER_BIN` et `DOTNET_BIN`.

```sh
scripts/dev/start-db.sh
scripts/build.sh
scripts/dev/run.sh
```

Ouvrir <http://localhost:5080>, puis choisir Camille ou Alex. Données fictives uniquement : ce mode est limité à l’interface loopback et interdit en production. La base de démonstration utilise le port local 55432. Le script de démarrage de base utilise le contexte `colima-foyer` ; adapter `DOCKER_CONTEXT` selon votre installation.

## Builds privés

Voir [le guide GitHub Actions](docs/ci.md) pour récupérer les APK depuis Actions et les Releases privées.

## Documentation

- [Installation Mac, Google, Firebase et APK](docs/installation.md)
- [Décisions de cadrage conservées](docs/decisions.md)
- [Règles métier et architecture](docs/architecture.md)
- [Sécurité et exploitation](docs/securite.md)
- [Sauvegarde, restauration et migration](docs/migration.md)
- [Validation et limites de la livraison](docs/validation.md)

## Vérification

```sh
dotnet test server/Foyer.Tests
cd client
flutter analyze
flutter test
flutter build apk --debug
```

Les scripts `scripts/tests/integration.py`, `scripts/tests/browser.cjs` et `scripts/tests/migration.py` sont réservés aux instances fictives locales. Voir le guide de validation pour les prérequis et effets.
