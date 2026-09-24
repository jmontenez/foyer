# GitHub privé et builds

Dépôt prévu : `jmontenez/foyer`, privé. Travail dans des branches et pull requests ; la branche principale initiale ne contient que le README de création. La première PR apporte le code et la CI, sans fusion automatique.

## Pipeline

Chaque push lance les tests .NET, les requêtes API sur PostgreSQL éphémère, Flutter analyze/test, le build web, puis les recettes Chromium ordinateur/mobile. Le build Android ARM64 ne commence qu’après ces validations. Les versions Flutter (.NET via global.json) et Playwright sont fixées ; les actions sont épinglées à leurs SHA complets. Permissions de lecture par défaut ; le job de Release seul peut publier.

Le workflow est également lançable manuellement depuis Actions une fois présent sur la branche par défaut. Les exécutions précédentes d’une même branche sont annulées si un nouveau push arrive.

Les artefacts privés `foyer-android-N`, `foyer-web-N` et `validation-N` sont conservés 7 jours pour limiter le stockage. Le numéro de build Android est `100 + github.run_number`, auquel Flutter ajoute le préfixe d’architecture. Les relances du même run conservent le même numéro. Le SHA-256 de l’APK accompagne le fichier.

## Télécharger sur téléphone

Se connecter au compte GitHub autorisé, ouvrir **Actions → Tests et builds Foyer → exécution réussie → Artifacts → foyer-android-N**. Extraire le ZIP, puis ouvrir `foyer-arm64.apk`.

Un push de tag `v*` lance la même validation puis crée une préversion dans **Releases**, avec l’APK téléchargeable directement. Le dépôt étant privé, ces fichiers nécessitent aussi un accès au dépôt. Ce workflow ne publie rien sur Google Play et ne déploie pas le serveur.

## Configuration

- Variable Actions `FIREBASE_ANDROID_JSON` : contenu de la configuration **cliente** google-services.json ; jamais un compte de service.
- Variable optionnelle `FOYER_API_URL` : origine HTTPS définitive du serveur. Absente pour le moment ; saisie dans l’application.
- Firebase côté serveur et secret OAuth Web ne sont pas nécessaires aux builds et ne doivent pas être ajoutés aux artefacts.

La version initiale compile un APK debug, destiné aux tests. La clé debug des runners est éphémère : ces APK ne garantissent pas une mise à jour sur l’APK local ou celui d’un autre run. Une clé dédiée durable doit être configurée pour distribuer des mises à jour régulières ; choix en cours avec l’utilisateur. Une signature différente exige une désinstallation initiale.

Les tests restent des tests sur données fictives. La CI ne valide pas à elle seule les parcours Google réels, les notifications sur téléphone, le bouton Retour Android, ni le déploiement Mac. La recette et les limites détaillées sont dans [validation.md](validation.md).
