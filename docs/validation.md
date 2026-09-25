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
node scripts/tests/appearance.cjs
node scripts/tests/shopping.cjs
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
- [ ] Déploiement automatique : jeton en place, `--check` indique la bonne release, merge sur `main` déployé en ~10 min (journal, `/health`, version servie), puis APK proposé dans l’application. Recette locale : `python3 scripts/tests/auto_update.py` (succès, rien à faire, rollback, empreinte falsifiée, commit hors `main`, auteur non CI, reprise).
- [ ] Notification de mise à jour : publication d’une version → notification sur les seuls téléphones en retard, une fois ; tap → bannière → installation ; deuxième mise à jour sans écran de confirmation (Android 12+), notification « Foyer est à jour ».
- [ ] Mise à jour depuis l’application : publier ci-N, installer, publier ci-N+1 avec `scripts/android_update.py`, vérifier bannière, autorisation Android, installation sans perte de session, puis « Foyer est à jour ». Tester aussi un fichier altéré (refus avant installateur).
- [ ] Déployer et vérifier le Mac Intel : tunnel Cloudflare sain (y compris après reboot/déverrouillage), veille, absence de port DB exposé, binding API loopback uniquement.
- [ ] Choisir la destination hors Mac, configurer la sauvegarde quotidienne et tester une restauration depuis cette destination.
- [ ] Recette navigateur Windows/Mac ; seule la session Chromium locale a été automatisée ici.
- [ ] Revue humaine et MR sur un dépôt distant à créer/configurer : branche locale `feat/initial-application`, aucune publication ni fusion effectuée.

Les tests locaux valident le code et les scripts avec des données fictives. Ils ne prouvent pas encore la bonne configuration des services externes ou des appareils personnels.

## Évolution : palettes personnelles

Onze palettes livrées dans Réglages → Couleurs de l’application. Tests supplémentaires : indépendance entre comptes, persistance dans une nouvelle session, préférences de résumé préservées, identifiants invalides refusés et compatibilité des données antérieures. Recette Chromium mobile : choix violet/bleu nuit, rechargement, aperçu ciel/orange, annulation et enregistrement ; captures `artifacts/browser/palettes-violet-mobile.png` et `sky-orange-mobile.png`. APK debug reconstruit avec numéro de build 2 et signature vérifiée.

Deux onglets depuis le 2026-09-24 : **Douces** (les onze palettes d’origine) et **Marquées** (huit palettes aux couleurs appliquées telles quelles, dont cinq thèmes sombres : Braise & nuit, Citron vert & charbon, Rubis & onyx, Violet électrique, Abysses & cyan). Le sélecteur s’ouvre sur l’onglet de la palette choisie. Tests : contraste ≥ 4,5 sur boutons, accents, fond et cartes pour les dix-neuf palettes, couleurs exactes et thème sombre effectif pour les palettes marquées, identifiants acceptés par le serveur ; recette Chromium de l’onglet Marquées (captures `palettes-marquees-mobile.png`, `ember-night-mobile.png`).

**Jetons de design (2026-09-24)** : l’apparence de chaque membre = palette, police (Système, Grotesk = Space Grotesk + DM Sans, Fraunces = Fraunces + Atkinson Hyperlegible, Manrope), affichage des tâches (cartes/lignes, appliqué avec les nouveaux écrans), densité (aérée/compacte) et angles (doux/marqués). Écran **Réglages → Apparence** : styles prêts à l’emploi Braise, Sauge et Liste, puis réglages fins, aperçu en direct, Enregistrer/Annuler. Polices embarquées (graisses fixes générées depuis les polices variables officielles, licence OFL dans `client/fonts/`, visibles dans les licences de l’application) : aucune requête vers Google Fonts. Anciennes versions de l’application compatibles (palette seule).

**Cadre commun (2026-09-24)** : barre de navigation flottante (onglet actif nommé ; rail latéral conservé sur grand écran), en-tête compact (date ou sous-titre, recherche repliable, profil = réglages), une seule ligne de filtres (Tout le foyer, Moi d’abord, l’autre membre, Sans responsable, Tags), bouton rond de création, tâches en carte ou en ligne selon le jeton d’affichage, dates relatives (Aujourd’hui, Demain, Samedi, Il y a 3 jours…), badges EN RETARD/URGENT/HAUTE, une couleur stable par membre, tirer pour actualiser. Pluriel corrigé (« 1 commentaire »).

**Listes (2026-09-24)** : Aujourd’hui = bandeau (à faire, en retard — touche pour ne voir que les retards —, répartition par personne) puis sections En retard / Aujourd’hui ; Semaine = frise lundi → dimanche (un point par tâche, toucher un jour pour filtrer) puis tâches par jour (retards et « en cours » sans date rattachés à aujourd’hui) ; Backlog = Tout / Obligations / Envies / Avec date, sections Commence bientôt / Un jour ; Historique = 30 jours (par défaut) / 3 mois / Tout / Période…, regroupé par semaine avec qui a réalisé. Apparence : choix Cartes / Lignes.

**Tableau (2026-09-24)** : sur mobile, sélecteur d’étape avec compteurs et une seule colonne ; glisser une carte à gauche ou à droite la déplace vers l’étape voisine (aperçu de la destination, seuil de 90 px ; mêmes déplacements en actions d’accessibilité) ; enregistrement avec contrôle de version. Colonnes côte à côte au-delà de 900 px. Vérifié dans Chromium : carte « À faire » glissée → « En cours », compteurs mis à jour.

**Fiche et création (2026-09-24)** : fiche d’une tâche existante = numéro et étape, titre sans cadre sur plusieurs lignes, actions immédiates C’est fait (choix explicite de qui l’a réalisé), Reporter (demain, dans 3 jours, lundi prochain, date au choix ; échéance, sinon date de début) et Bloqué/Débloquer (étape « en attente » ↔ « en cours »), tuiles Qui / Quand / Étapes / Tags modifiables, puis notes, étapes, images, échanges ; réglages complets repliés dans « Tous les réglages ». Création rapide depuis le bouton + : titre, puces Quand / Qui / Priorité / Tag, Créer ; « Plus de détails » ouvre le formulaire complet prérempli. Cartes lues par les lecteurs d’écran titre d’abord, sans initiales ni pourcentages. Recette Chromium : création rapide, blocage puis clôture avec réalisateur vérifiés via l’API.

**Raccourcis et répétition (2026-09-25)** : raccourcis partagés par le foyer (8 courants pré-chargés une fois), lancés d’un toucher depuis le bouton + (annulation si intacte, anti-doublon) ou préremplis par appui long ; Réglages → Raccourcis. Répétition d’un raccourci : N jours après la dernière fois, certains jours de la semaine (toutes les N semaines), ou chaque mois le jour N (fin de mois ramenée au dernier jour). Une seule occurrence ouverte ; la suivante est créée à la clôture de la précédente, avec sa date de début (Backlog puis « À faire » et notification le jour venu) ; jamais de date passée pour un calendrier fixe ; « Passer cette fois » ; pause. Qui : dernière personne qui l’a fait (« qui le lance »), membre fixe, personne ou à tour de rôle. Répétitions suggérées des raccourcis pré-chargés, jamais activées d’office.

Rejouer le parcours visuel : `node scripts/tests/appearance.cjs` sur la démonstration locale. Il laisse le compte fictif Camille sur Ciel & orange.

## Adaptation Cloudflare Tunnel — exposition publique

Changements du 2026-09-24 : résolution de l’adresse visiteur via `CLIENT_IP_HEADER` (`CF-Connecting-IP`), limitation de requêtes par visiteur au lieu du pair réseau, budget dédié 30 req/min sur `/auth/*` et `/signin-google`, `no-store` étendu au callback OAuth.

Tests automatisés ajoutés :

- Unitaires : en-tête usurpé ignoré sans proxy configuré, résolution via l’en-tête configuré, retour au pair réseau si valeur absente/non parsable, dernière valeur retenue en cas d’en-têtes multiples, périmètre des routes d’authentification.
- Intégration : `Cache-Control: no-store` et en-têtes de sécurité sur `/auth/config` et `/api/v1/state`, 429 au 31ᵉ appel d’authentification d’un même visiteur, budgets indépendants entre visiteurs et trafic local, valeur non parsable sans création de partition arbitraire, contrôle « démo locale » insensible à l’en-tête.

Ces tests valident le code sur données fictives ; la recette publique réelle (étape 7 de l’installation) reste à faire avant toute donnée familiale.

## Correctif Android — build 3

Écran rouge signalé sur téléphone après fermeture du formulaire serveur vide. Contrôleur désormais possédé par le widget du dialogue et validation HTTPS avant fermeture. Même libération anticipée supprimée pour les saisies de tags et checklist, dont les champs gèrent maintenant leurs contrôleurs. Deux tests de régression couvrent adresse vide, HTTP invalide, conservation du formulaire, annulation et retour HTTPS valide sans exception. Recette sur appareil réel du correctif encore à confirmer ; les tests widgets ne remplacent pas clavier/Retour Android, permissions et Google/FCM réels.
