# Installation sur le Mac Intel

## 1. Préparer le serveur

Utiliser un compte macOS dédié, FileVault, les mises à jour et une destination de sauvegarde distincte. Garder le Mac sur secteur avec la veille système désactivée lorsqu’il est branché ; fermer le capot peut le mettre en veille. Tester le fonctionnement capot ouvert, puis un redémarrage. Avec FileVault, un redémarrage peut exiger un déverrouillage local : ne pas promettre de démarrage totalement autonome.

Installer Git, Docker Desktop pour Intel **ou** Colima + Docker + Compose, Python 3.12+ et `age`. Si Colima est retenu : profil dédié, 2 CPU et 4 Go de RAM comme point de départ, disque VM adapté aux photos/sauvegardes. La machine de développement utilise un profil `foyer` ; ce profil n’a pas été installé sur le Mac serveur à distance.

Installer Flutter stable et .NET SDK 10.0.401 pour compiler sur place, ou transférer le code et le build web depuis le poste de développement. Un build serveur effectué sur Intel produira son image amd64 ; ne pas copier aveuglément l’image arm64 du M5.

## 2. Origine HTTPS privée

Connecter le Mac à Tailscale. Conserver le téléphone dans son réseau actuel si le partage ciblé du Mac depuis le réseau personnel permet les accès voulus ; les règles des deux réseaux doivent l’autoriser. Vérifier les accès des deux personnes, limiter au port HTTPS du Mac et ne pas activer Funnel.

```sh
tailscale serve --bg http://127.0.0.1:5080
tailscale serve status
```

Retenir l’origine exacte `https://nom-du-mac.nom-du-reseau.ts.net`, sans chemin. Le serveur n’expose son port Docker que sur 127.0.0.1. Tailscale fournit le HTTPS et relaie vers cette boucle locale. [Documentation officielle Serve](https://tailscale.com/docs/reference/tailscale-cli/serve).

## 3. Google et Firebase

Projet personnel indiqué par l’utilisateur le 2026-09-24 : `foyer-d02dc`. Création déclarée, accès console non vérifié par l’agent. Application Android `fr.foyer.foyer` enregistrée : configuration cliente fournie depuis Downloads et intégrée le 2026-09-24 dans les deux fichiers locaux ignorés par Git (`client/android/app/google-services.json`, `client/.config/android.json`). Aucun client OAuth présent dans le fichier reçu. Google OAuth, FCM serveur et origine HTTPS finale restent à configurer.

Créer un projet personnel Google Cloud/Firebase, distinct de l’entreprise. Configurer l’écran de consentement externe pour les deux comptes (utilisateurs de test si nécessaire), scopes de base identité/profil/email.

Créer un client OAuth **Web** : origine HTTPS retenue, redirection autorisée exacte `https://…/signin-google`. Son client ID est utilisé à la fois par le navigateur et comme `serverClientId` Android. Son secret reste uniquement sur le serveur.

Créer le client OAuth **Android** : package `fr.foyer.foyer`, empreinte SHA-1 du certificat utilisé pour signer l’APK. Le certificat debug et le certificat personnel sont différents ; déclarer seulement ceux réellement utilisés. Sans cette association, la connexion native peut échouer même si le navigateur fonctionne. Le code passe explicitement le client Web ID. Télécharger `google-services.json` depuis Firebase et le placer dans `client/android/app/` (ignoré par Git) : le plugin Google Services est appliqué lorsqu’il est présent et configure aussi le démarrage natif des notifications avant Flutter. [Configuration du plugin officiel](https://github.com/flutter/packages/blob/main/packages/google_sign_in/google_sign_in_android/README.md).

Dans Firebase, enregistrer l’application Android, activer l’API Cloud Messaging HTTP v1 et créer une identité serveur limitée à l’envoi FCM. Fournir un fichier de credentials serveur hors dépôt. Les valeurs de configuration cliente `apiKey`, `appId`, `messagingSenderId`, `projectId` proviennent des réglages de cette application. **Aucune clé privée/service account ne doit être intégrée à l’APK.** Aucun Firestore/Storage Firebase ni Firebase Authentication n’est utilisé : l’authentification Google est validée par notre API.

## 4. Configuration du serveur

Copier `.env.example` en `.env`, puis renseigner localement : origine, deux adresses Google séparées par une virgule, client ID Web, projet Firebase et répertoire de secrets. Les fichiers sont exclus de Git ; ne pas les coller dans une conversation.

Dans le répertoire privé de secrets (droits 700), créer :

| Fichier | Contenu |
|---|---|
| `database-password` | Mot de passe aléatoire PostgreSQL |
| `google-client-secret` | Secret du client OAuth Web |
| `firebase-service-account.json` | Credentials FCM limités au projet |

Le répertoire parent reste privé (700). Pour les secrets montés par Compose local, rendre les fichiers lisibles par le processus du conteneur : `0444` dans ce répertoire privé, ou des ACL/UID explicitement adaptés. Un fichier hôte `0600` appartenant à un autre UID peut être illisible par l’API non root ; les options UID/mode des secrets Compose ne corrigent pas toujours les bind mounts locaux. Compose les monte en lecture seule. Les secrets Compose locaux sont des fichiers, pas un coffre : FileVault, contrôle du compte hôte et sauvegardes chiffrées restent nécessaires. Les valeurs ne sont pas imprimées par les scripts.

```sh
scripts/build.sh
python3 scripts/migration/foyer.py preflight
docker compose up -d --build
```

Laisser `WORKERS_ENABLED=false` pendant la première vérification. Ouvrir l’origine Tailscale, se connecter avec chacun des deux comptes. Vérifier qu’un troisième compte est refusé. Après validation, passer `WORKERS_ENABLED=true` et recréer l’API : `docker compose up -d api`.

`docker compose ps` doit montrer les services sains. `restart: unless-stopped` redémarre les conteneurs lorsque le moteur redémarre ; configurer séparément le démarrage du moteur macOS. Tester le reboot et documenter le besoin de connexion/déverrouillage de session.

## 5. Construire et installer l’APK

Installer Java 17 et le SDK Android sur le poste de compilation. Un APK de test peut être construit avec `flutter build apk --debug`. Celui livré initialement est **signé debug**, sans projet Firebase configuré ; ce n’est pas la version finale signée personnellement.

Créer et conserver hors dépôt une clé de signature Android personnelle, avec sauvegarde indépendante. La même clé sera nécessaire pour toutes les mises à jour. Charger localement via gestionnaire de secrets les variables `FOYER_KEYSTORE`, `FOYER_STORE_PASSWORD`, `FOYER_KEY_ALIAS`, `FOYER_KEY_PASSWORD` (ne pas les afficher).

Créer un fichier local ignoré `client/.config/android.json` contenant uniquement la configuration cliente :

```json
{
  "API_URL": "https://nom-du-mac.nom-du-reseau.ts.net",
  "FIREBASE_ENABLED": true,
  "FIREBASE_API_KEY": "configuration-cliente-firebase",
  "FIREBASE_APP_ID": "identifiant-application-android",
  "FIREBASE_SENDER_ID": "numero-projet",
  "FIREBASE_PROJECT_ID": "identifiant-projet"
}
```

```sh
cd client
flutter build apk --release --dart-define-from-file=.config/android.json
```

Sans configuration de signature personnelle, le build release reste non signé ; il ne reprend jamais la clé debug automatiquement. Vérifier avec `apksigner verify --print-certs` avant distribution. Installer l’APK sur les deux téléphones via USB ou transfert privé, autoriser cette source d’installation, puis désactiver cette autorisation après installation. Une installation debug existante peut devoir être désinstallée avant la version signée personnellement ; les données métier restent sur le serveur.

Au premier lancement : adresse HTTPS du serveur si non intégrée, connexion Google, autorisation notifications. L’adresse reste modifiable dans les réglages ; la changer efface la session locale. Tester commentaire croisé, résumé, app fermée et téléphone verrouillé. Les réglages de batterie et la connectivité peuvent retarder un push.

## 6. Recette avant données familiales

Voir [validation](validation.md). Une installation réussie ne remplace pas le test d’une restauration complète et le contrôle des accès Tailscale. La sauvegarde hors Mac reste à choisir et configurer. Le DS216j n’est pas la cible de cette stack ; un partage NAS peut recevoir ses archives chiffrées.
