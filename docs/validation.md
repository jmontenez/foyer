# Validation de la V1 — 2026-09-24

## Exécuté localement

| Contrôle | Résultat |
|---|---|
| .NET compilation et format | Réussite, zéro avertissement/erreur de compilation |
| Tests serveur | 18 tests réussis : dates, semaine, changement d’heure, maintenance, clôture, réalisateurs, concurrence, allowlist, sujet Google stable, session et CSRF |
| API + PostgreSQL réel | 36 requêtes validées : anonyme refusé, CSRF, deux membres, commentaires, concurrence 409, images privées et malformées, préférences, révocation |
| Flutter analyze | Aucune anomalie |
| Test Flutter | 4 tests réussis : création rapide, contrastes des onze palettes et deux parcours du formulaire serveur |
| Navigateur Chromium réel | Connexion démo, création, persistance backlog, ouverture ticket ; captures 1365×900 et 390×844 ; aucune erreur JavaScript détectée |
| Build web release | Réussite, ressources CanvasKit hébergées avec l’application |
| APK Android debug | Builds ARMv7/ARM64/x86-64 réussis ; signature debug ARM64 vérifiée par apksigner |
| APK Android release | Builds réussis, ARM64 ~19,8 Mo ; **non signés** en l’absence de clé personnelle, vérifié explicitement |
| Image Docker | Construction native ARM64 réussie sur M5 ; image destinée au Mac Intel à reconstruire en amd64 |
| Migration | Export chiffré, empreintes et références métier/images, restauration vierge, santé API cible, refus d’écrasement, révocation sessions/appareils, jobs anciens neutralisés, retour à la source, archive altérée refusée |
| Python | Ruff, Black et mypy passent ; Bandit : aucun résultat moyen/haut, 20 résultats bas (subprocess/tests), une exclusion documentée pour HTTP loopback du test |
| Shell | ShellCheck passe |
| NuGet | Aucun package vulnérable signalé pour l’API, transitifs compris, par la source NuGet au moment du contrôle |
| Dart | Dépendances directes à jour selon `flutter pub outdated` ; des mises à jour transitives existent, lock conservé après recette |

Dernier exercice : 6 tickets fictifs restaurés, intégrité des images contrôlée, 0 session/appareil/job ancien actif et 11,05 secondes entre début de gel et retour vérifié de la source. Mesure locale sur M5, non extrapolable au Mac Intel ou à un historique réel.

Le build Android émet un avertissement de compatibilité future du plugin `firebase_core` avec le plugin Kotlin intégré. Il n’empêche pas cette compilation ; refaire la recette avant une mise à jour majeure Flutter/Gradle. Aucun téléphone ni émulateur n’était connecté lors de la livraison.

## Artefacts locaux

- `artifacts/releases/foyer-0.1.0-arm64-debug.apk` : APK installable de test, sans projet Firebase réel intégré.
- `artifacts/releases/SHA256SUMS` : empreinte de cet APK.
- `client/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` : build release non signé, non installable en l’état.
- `artifacts/browser/` : captures du navigateur et dépendances Playwright de test, hors Git.
- `artifacts/migration-*/report.json` : compteurs et durée de l’exercice ; archives et clés **de test** restent locales, hors Git.

## Rejouer

Après démarrage de la démonstration sur <http://localhost:5080> :

```sh
python3 scripts/tests/integration.py
npm install --prefix artifacts/browser playwright --no-audit --no-fund
node artifacts/browser/node_modules/playwright/cli.js install chromium
node scripts/tests/browser.cjs
```

La migration automatisée utilise la base fictive `foyer-test-db`, le contexte Docker `colima-foyer`, l’image locale `foyer:local`, Python 3.12+ et age. Elle crée deux projets Compose horodatés, les arrête à la fin et conserve leurs volumes pour inspection. Ne pas la pointer vers des données familiales.

```sh
docker --context colima-foyer build -t foyer:local -f deploy/Dockerfile .
python3 scripts/tests/migration.py
```

## À valider avant usage réel

- [ ] Configurer les deux comptes Google, l’origine HTTPS et les credentials serveur ; valider navigateur et APK avec identités réelles, troisième compte refusé.
- [ ] Configurer Firebase côté Android/serveur et vérifier commentaire à l’autre personne seulement, résumé aux deux horaires, notification app fermée/verrouillée et ouverture de la bonne vue.
- [ ] Signer personnellement l’APK, déclarer son certificat OAuth et tester installation puis mise à jour sur les deux téléphones.
- [ ] Mise à jour depuis l’application : publier ci-N, installer, publier ci-N+1 avec `scripts/android_update.py`, vérifier bannière, autorisation Android, installation sans perte de session, puis « Foyer est à jour ». Tester aussi un fichier altéré (refus avant installateur).
- [ ] Déployer et vérifier le Mac Intel : tunnel Cloudflare sain (y compris après reboot/déverrouillage), veille, absence de port DB exposé, binding API loopback uniquement.
- [ ] Choisir la destination hors Mac, configurer la sauvegarde quotidienne et tester une restauration depuis cette destination.
- [ ] Recette navigateur Windows/Mac ; seule la session Chromium locale a été automatisée ici.
- [ ] Revue humaine et MR sur un dépôt distant à créer/configurer : branche locale `feat/initial-application`, aucune publication ni fusion effectuée.

Les tests locaux valident le code et les scripts avec des données fictives. Ils ne prouvent pas encore la bonne configuration des services externes ou des appareils personnels.

## Évolution : palettes personnelles

Onze palettes livrées dans Réglages → Couleurs de l’application. Tests supplémentaires : indépendance entre comptes, persistance dans une nouvelle session, préférences de résumé préservées, identifiants invalides refusés et compatibilité des données antérieures. Recette Chromium mobile : choix violet/bleu nuit, rechargement, aperçu ciel/orange, annulation et enregistrement ; captures `artifacts/browser/palettes-violet-mobile.png` et `sky-orange-mobile.png`. APK debug reconstruit avec numéro de build 2 et signature vérifiée.

Deux onglets depuis le 2026-09-24 : **Douces** (les onze palettes d’origine) et **Marquées** (huit palettes aux couleurs appliquées telles quelles, dont cinq thèmes sombres : Braise & nuit, Citron vert & charbon, Rubis & onyx, Violet électrique, Abysses & cyan). Le sélecteur s’ouvre sur l’onglet de la palette choisie. Tests : contraste ≥ 4,5 sur boutons, accents, fond et cartes pour les dix-neuf palettes, couleurs exactes et thème sombre effectif pour les palettes marquées, identifiants acceptés par le serveur ; recette Chromium de l’onglet Marquées (captures `palettes-marquees-mobile.png`, `ember-night-mobile.png`).

Rejouer le parcours visuel : `node scripts/tests/appearance.cjs` sur la démonstration locale. Il laisse le compte fictif Camille sur Ciel & orange.

## Adaptation Cloudflare Tunnel — exposition publique

Changements du 2026-09-24 : résolution de l’adresse visiteur via `CLIENT_IP_HEADER` (`CF-Connecting-IP`), limitation de requêtes par visiteur au lieu du pair réseau, budget dédié 30 req/min sur `/auth/*` et `/signin-google`, `no-store` étendu au callback OAuth.

Tests automatisés ajoutés :

- Unitaires : en-tête usurpé ignoré sans proxy configuré, résolution via l’en-tête configuré, retour au pair réseau si valeur absente/non parsable, dernière valeur retenue en cas d’en-têtes multiples, périmètre des routes d’authentification.
- Intégration : `Cache-Control: no-store` et en-têtes de sécurité sur `/auth/config` et `/api/v1/state`, 429 au 31ᵉ appel d’authentification d’un même visiteur, budgets indépendants entre visiteurs et trafic local, valeur non parsable sans création de partition arbitraire, contrôle « démo locale » insensible à l’en-tête.

Ces tests valident le code sur données fictives ; la recette publique réelle (étape 7 de l’installation) reste à faire avant toute donnée familiale.

## Correctif Android — build 3

Écran rouge signalé sur téléphone après fermeture du formulaire serveur vide. Contrôleur désormais possédé par le widget du dialogue et validation HTTPS avant fermeture. Même libération anticipée supprimée pour les saisies de tags et checklist, dont les champs gèrent maintenant leurs contrôleurs. Deux tests de régression couvrent adresse vide, HTTP invalide, conservation du formulaire, annulation et retour HTTPS valide sans exception. Recette sur appareil réel du correctif encore à confirmer ; les tests widgets ne remplacent pas clavier/Retour Android, permissions et Google/FCM réels.
