# GitHub privé et builds

Dépôt : `jmontenez/foyer`, privé. Travail dans des branches et pull requests ; la PR initiale #1 a été fusionnée à la demande de l’utilisateur. `main` contient le code et la CI.

## Pipeline

Chaque push lance les tests .NET, les requêtes API sur PostgreSQL éphémère, Flutter analyze/test, le build web, puis les recettes Chromium ordinateur/mobile. Le build Android ARM64 ne commence qu’après ces validations. Les versions Flutter (.NET via global.json) et Playwright sont fixées ; les actions sont épinglées à leurs SHA complets. Permissions de lecture par défaut ; le job de Release seul peut publier.

Le workflow est également lançable manuellement depuis Actions une fois présent sur la branche par défaut. Les exécutions précédentes d’une même branche sont annulées si un nouveau push arrive.

Les artefacts privés `foyer-android-N`, `foyer-web-N` et `validation-N` sont conservés 7 jours pour limiter le stockage. Le numéro de build Android est `100 + github.run_number`, auquel Flutter ajoute le préfixe d’architecture. Les relances du même run conservent le même numéro. Le SHA-256 de l’APK accompagne le fichier.

## Télécharger sur téléphone

Se connecter au compte GitHub autorisé, ouvrir **Actions → Tests et builds Foyer → exécution réussie → Artifacts → foyer-android-N**. Extraire le ZIP, puis ouvrir `foyer-arm64.apk`.

Un push sur `main`, sur la branche initiale `feat/initial-application`, ou un tag `v*` lance la même validation puis crée une préversion dans **Releases**, avec l’APK téléchargeable directement. Le dépôt étant privé, ces fichiers nécessitent aussi un accès au dépôt. Ce workflow ne publie rien sur Google Play et ne déploie pas le serveur.

## Configuration

- Variable Actions `FIREBASE_ANDROID_JSON` : contenu de la configuration **cliente** google-services.json ; jamais un compte de service.
- Variable optionnelle `FOYER_API_URL` : origine HTTPS définitive du serveur. Absente pour le moment ; saisie dans l’application.
- Firebase côté serveur et secret OAuth Web ne sont pas nécessaires aux builds et ne doivent pas être ajoutés aux artefacts.

Les APK release utilisent une clé RSA dédiée persistante via les secrets Actions `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD` et `ANDROID_KEY_ALIAS`. Seul le job Android reçoit ces secrets ; copie de clé temporaire effacée même après échec. La signature est vérifiée avant publication.

Clé de secours locale : `~/.local/share/foyer-signing/foyer-release.p12` (répertoire 700, fichier 600). Mot de passe dans le Trousseau macOS, service `fr.foyer.android.signing`, compte `foyer`. Ne jamais coller ces secrets dans une conversation. Prévoir une sauvegarde personnelle indépendante avant usage durable ; ne pas remplacer cette clé sous peine de casser les mises à jour.

La migration depuis l’APK debug local nécessite une désinstallation unique. Les APK CI signés suivants s’installent en mise à jour. Déclarer l’empreinte SHA-1 indiquée dans le [guide d’installation](installation.md#3-google-et-firebase) dans le client OAuth Android et les réglages Firebase avant la connexion Google réelle. Les préversions automatiques portent le tag `ci-N` et restent privées.

Les tests restent des tests sur données fictives. La CI ne valide pas à elle seule les parcours Google réels, les notifications sur téléphone, le bouton Retour Android, ni le déploiement Mac. La recette et les limites détaillées sont dans [validation.md](validation.md).
