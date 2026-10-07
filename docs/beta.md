# Canal beta

Le canal beta sert à valider une évolution majeure du client (refonte graphique, navigation) sur téléphone, à deux, **avant** tout merge sur `main`. C'est une application distincte, installée à côté de l'app principale.

## Fonctionnement

- Tout push sur la branche **`redesign`** construit un APK **« Foyer β »** (`fr.foyer.foyer.beta`, même clé de signature) et publie une prerelease GitHub **`beta-N`** avec l'APK `foyer-beta-arm64.apk`.
- La beta pointe sur **l'instance de validation** définie par la variable Actions `FOYER_BETA_API_URL` (la démo publique) : connexion par les comptes démo, données fictives réinitialisées chaque nuit, images et notifications push désactivées.
- Les classes Kotlin restent dans le namespace `fr.foyer.foyer` : receivers relatifs du manifeste et `qualifiedAndroidName` des widgets restent valides avec le suffixe de package.
- **Jamais déployée** : le déploiement automatique du serveur ne retient que les tags `ci-N` (`scripts/deploy/auto_update.py`), et la beta n'interroge pas le serveur pour ses mises à jour (`appChannel` dans `client/lib/update.dart`) — l'APK du serveur a de toute façon un autre package, l'installation serait refusée par le natif.

## Installer / mettre à jour

1. Sur le téléphone, ouvrir la release `beta-N` la plus récente (repo privé : session GitHub requise) et télécharger `foyer-beta-arm64.apk` — ou se faire transférer le fichier.
2. Installer (autorisation « installer des applications inconnues » à accorder une fois pour la source utilisée). L'app principale n'est pas touchée.
3. Se connecter avec un compte démo. Réglages → « Canal beta » affiche le build installé et la **taille logique de l'écran** (à relever ouvert et fermé sur chaque appareil : ces mesures règlent le seuil deux-volets).
4. Mise à jour : télécharger la `beta-N` suivante et installer par-dessus (même package, versionCode croissant).

## Limites connues

- Pas de push ni de Firebase dans la beta (pas de `google-services.json`) ; les widgets se rafraîchissent à l'ouverture de l'app et par la fenêtre de 30 minutes.
- Les photos d'ingrédients et de tickets sont désactivées sur l'instance démo : à valider sur la prod après merge.
- Un build `workflow_dispatch` depuis une autre branche reste sur le canal stable (package principal, API de prod) — seul `redesign` produit des betas.
