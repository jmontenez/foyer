# Installation sur le Mac Intel — Cloudflare Tunnel

Ce guide remplace le parcours Tailscale initial pour l’accès à Foyer. Le web et l’APK utiliseront **https://foyer.jmops.fr**. Tailscale peut rester en place pour Orca ou l’administration, indépendamment de Foyer.

**Déjà fait** : dépôt GitHub privé et CI, APK release signé, projet Firebase `foyer-d02dc`, application Android `fr.foyer.foyer`, domaine chez IONOS et délégation DNS Cloudflare. **Reste à faire** : installation sur le Mac Intel, tunnel, OAuth, FCM serveur, adaptations pour exposition publique et recette. La création de la route publique intervient seulement à l’étape 6.

## 1. Préparer le serveur

Utiliser un compte macOS dédié, FileVault, les mises à jour et une destination de sauvegarde distincte. Garder le Mac sur secteur avec la veille système désactivée lorsqu’il est branché ; fermer le capot peut le mettre en veille. Tester le fonctionnement capot ouvert, puis un redémarrage. Avec FileVault, un redémarrage peut exiger un déverrouillage local : ne pas promettre de démarrage totalement autonome.

Installer Git, Docker Desktop pour Intel **ou** Colima + Docker + Compose, Python 3.12+ et `age`. Si Colima est retenu : profil dédié, 2 CPU et 4 Go de RAM comme point de départ, disque VM adapté aux photos/sauvegardes. La machine de développement utilise un profil `foyer` ; ce profil n’a pas été installé sur le Mac serveur à distance.

Installer Flutter **3.47.5** et .NET SDK **10.0.401** pour compiler sur place, ou transférer le code et le build web depuis le poste de développement. Un build serveur effectué sur Intel produira son image amd64 ; ne pas copier aveuglément l’image arm64 du M5.

Pour récupérer le dépôt privé sur le Mac serveur, installer GitHub CLI puis s’authentifier avec son compte personnel :

```sh
gh auth login --hostname github.com --web
gh repo clone jmontenez/foyer
cd foyer
```

La CI compile le web et teste le serveur, mais **aucune image Docker serveur prête à télécharger n’est encore publiée**. Le Compose actuel construit donc l’image sur le Mac Intel. Les commandes de compilation ci-dessous supposent Flutter et .NET accessibles dans le PATH ; le build Docker utilise aussi le SDK .NET dans son image de compilation.

## 2. Domaine et Cloudflare Tunnel

### Domaine déjà préparé

`jmops.fr` reste enregistré et renouvelé chez IONOS. Cloudflare gère le DNS ; la délégation vers `elisa.ns.cloudflare.com` et `watson.ns.cloudflare.com` a été vérifiée auprès du registre `.fr` le 2026-09-24. Ne pas modifier `pourclemence.fr`.

Origine retenue pour le web **et** l’API Android : **https://foyer.jmops.fr**. Aucun client Tailscale n’est nécessaire aux utilisateurs avec ce mode d’accès. Ne pas ajouter d’enregistrement A vers l’IP de la box et ne pas ouvrir de port entrant sur celle-ci. Le sous-domaine sera associé au tunnel à l’étape 6.

Pour vérifier une délégation ultérieure :

```sh
dig @d.nic.fr jmops.fr NS +norecurse +noall +authority
dig @1.1.1.1 jmops.fr NS +short
```

La présence des NS ne crée pas automatiquement le sous-domaine. Une zone neuve sans A/MX peut être normale. Si DNSSEC était utilisé avant un changement de fournisseur DNS, suivre la [procédure de bascule Cloudflare](https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/) ; ne pas conserver un DS de l’ancien fournisseur.

### Connecter le Mac Intel, sans publier Foyer pour l’instant

1. Dans le compte Cloudflare qui héberge `jmops.fr`, ouvrir **Networking → Tunnels → Create Tunnel** (selon l’interface, la rubrique peut se trouver dans Cloudflare One / Networks).
2. Nommer le tunnel `foyer-mac`.
3. Choisir **macOS / Intel (amd64)** et exécuter les commandes **Install and Run** affichées, **sur l’ancien Mac serveur**, pas sur le Mac M5 de développement. Le connecteur `cloudflared` est installé directement sur macOS dans ce guide, pas dans Docker.
4. Configurer son exécution en service avec la commande fournie par le tableau de bord. Le token de tunnel est un secret : conserver la commande localement, ne pas l’envoyer dans une conversation ni dans Git.
5. Vérifier l’état **Healthy** dans Cloudflare, puis le retrouver après redémarrage/déverrouillage du Mac.
6. **Ne pas encore ajouter de route publique.** Un tunnel Healthy confirme la connexion du Mac à Cloudflare, pas l’installation ni la sécurité de Foyer.

[Guide officiel du tunnel](https://developers.cloudflare.com/tunnel/get-started/). Si le réseau filtre les sorties, vérifier les prérequis réseau du connecteur, notamment le port 7844.

Architecture cible : navigateur/APK → HTTPS Cloudflare → tunnel chiffré → `cloudflared` macOS → `http://127.0.0.1:5080` → API + interface web. Le HTTP final reste sur la boucle locale du Mac. Cloudflare termine le HTTPS public et devient un intermédiaire de confiance pour ce trafic.

## 3. Google et Firebase

Projet personnel indiqué par l’utilisateur le 2026-09-24 : `foyer-d02dc`. Création déclarée, accès console non vérifié par l’agent. Application Android `fr.foyer.foyer` enregistrée : configuration cliente fournie depuis Downloads et intégrée le 2026-09-24 dans les deux fichiers locaux ignorés par Git (`client/android/app/google-services.json`, `client/.config/android.json`). Aucun client OAuth présent dans le fichier reçu. Google OAuth et FCM serveur restent à configurer ; l’origine publique retenue est désormais `https://foyer.jmops.fr`.

Réutiliser le projet personnel **foyer-d02dc** ; ne pas recréer de projet. Configurer l’écran de consentement externe pour les deux comptes (utilisateurs de test si nécessaire), scopes de base identité/profil/email.

Créer un client OAuth **Web** : origine autorisée `https://foyer.jmops.fr`, redirection autorisée exacte `https://foyer.jmops.fr/signin-google`. Son client ID est utilisé à la fois par le navigateur et comme `serverClientId` Android. Son secret reste uniquement sur le serveur.

Créer le client OAuth **Android** : package `fr.foyer.foyer`, empreinte SHA-1 de la clé dédiée des APK GitHub Releases :

```text
BE:96:95:49:E4:F6:FD:2D:2D:EE:C8:05:19:F0:D1:40:D7:C0:18:6C
```

Cette empreinte publique a été vérifiée sur l’APK signé de la Release `ci-2`. L’ajouter aussi dans les paramètres de l’application Android Firebase. Le certificat debug et le certificat personnel sont différents ; déclarer seulement ceux réellement utilisés. Sans cette association, la connexion native peut échouer même si le navigateur fonctionne. Le code passe explicitement le client Web ID. Télécharger `google-services.json` depuis Firebase et le placer dans `client/android/app/` (ignoré par Git) : le plugin Google Services est appliqué lorsqu’il est présent et configure aussi le démarrage natif des notifications avant Flutter. [Configuration du plugin officiel](https://github.com/flutter/packages/blob/main/packages/google_sign_in/google_sign_in_android/README.md).

L’application Android Firebase est déjà enregistrée. Vérifier/activer l’API Cloud Messaging HTTP v1 et créer une identité serveur limitée à l’envoi FCM. Fournir un fichier de credentials serveur hors dépôt. Les valeurs de configuration cliente `apiKey`, `appId`, `messagingSenderId`, `projectId` proviennent des réglages de cette application. **Aucune clé privée/service account ne doit être intégrée à l’APK.** Aucun Firestore/Storage Firebase ni Firebase Authentication n’est utilisé : l’authentification Google est validée par notre API.

## 4. Configuration du serveur

Copier `.env.example` en `.env`, puis renseigner localement les valeurs suivantes :

| Variable | Valeur |
|---|---|
| `PUBLIC_ORIGIN` | `https://foyer.jmops.fr` |
| `FIREBASE_PROJECT_ID` | `foyer-d02dc` |
| `ALLOWED_EMAILS` | Les deux adresses Google autorisées, séparées par une virgule |
| `GOOGLE_CLIENT_ID` | Identifiant du client OAuth Web créé à l’étape 3 |
| `CLIENT_IP_HEADER` | `CF-Connecting-IP` — adresse visiteur transmise par Cloudflare, utilisée pour la limitation de requêtes. Ne le renseigner que si l’API reste liée à la boucle locale derrière le connecteur ; laisser vide en accès direct sans proxy |
| `FOYER_SECRETS_DIR` | Chemin absolu du répertoire privé de secrets sur le Mac serveur |
| `WORKERS_ENABLED` | `false` pendant la première validation |

Les fichiers sont exclus de Git ; ne pas les coller dans une conversation.

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

Vérifier le démarrage sans route publique :

```sh
docker compose ps
curl --fail http://127.0.0.1:5080/health
```

Conserver le binding `127.0.0.1:5080:8080` du Compose. Ne pas publier PostgreSQL sur un port hôte. Le service doit tourner en **Production**, sans `DemoMode`. Laisser `WORKERS_ENABLED=false` jusqu’à la recette de l’étape 7. Une réponse `/health` valide la santé locale, pas le parcours de connexion Google.

`docker compose ps` doit montrer les services sains. `restart: unless-stopped` redémarre les conteneurs lorsque le moteur redémarre ; configurer séparément le démarrage du moteur macOS. Tester le reboot et documenter le besoin de connexion/déverrouillage de session.

## 5. Installer l’APK signé

Ouvrir les [Releases privées de Foyer](https://github.com/jmontenez/foyer/releases), connecté à GitHub, puis télécharger `foyer-arm64.apk` d’une exécution réussie. Les builds sont signés avec une clé dédiée persistante et intègrent la configuration Firebase cliente.

Désinstaller une seule fois l’ancienne version **debug** si elle est encore présente : sa signature est différente. Les versions CI signées suivantes s’installent en mise à jour. La clé dédiée existe déjà : **ne pas en créer une nouvelle**. Gestion des secrets, sauvegarde de clé et builds locaux : [guide CI](ci.md).

Après mise en service du serveur, choisir **Configurer le serveur** et saisir `https://foyer.jmops.fr`. La variable GitHub Actions `FOYER_API_URL` peut intégrer cette adresse aux futurs builds ; elle n’est pas présumée configurée par cette documentation. Changer l’adresse dans l’application efface la session locale et impose une reconnexion.

### Mises à jour depuis l’application

Les releases GitHub étant privées, le serveur distribue lui-même la dernière version aux seuls membres connectés (`/api/v1/app/android`, `/api/v1/app/android.apk`). Publier une release CI sur le Mac serveur, depuis un compte authentifié par `gh`, puis déposer ses fichiers dans le répertoire `FOYER_UPDATES_DIR` du compte de service :

```sh
gh release download ci-N -R jmontenez/foyer -p foyer-arm64.apk -p foyer-android.json -p SHA256SUMS -D /tmp/foyer-ci-N
python3 scripts/android_update.py /tmp/foyer-ci-N "$FOYER_UPDATES_DIR"
```

Le script vérifie taille et SHA-256 contre le manifeste et `SHA256SUMS`, refuse une version plus ancienne (`--allow-downgrade` pour republier volontairement) et remplace les fichiers sans exposer de copie partielle. Aucun redémarrage n’est nécessaire : l’API lit le répertoire, monté en lecture seule, à chaque demande. Sans fichier publié, l’application ne propose rien.

L’application vérifie au démarrage et au retour au premier plan, au plus toutes les 6 heures, ou via **Réglages → Rechercher une mise à jour**. Une bannière propose l’installation : téléchargement avec la session, contrôle de la taille, du SHA-256, du paquet et du numéro de version, puis écran de confirmation d’Android, qui vérifie aussi la signature. La première fois, Android demande d’autoriser Foyer à installer des applications ; conserver cette autorisation pour Foyer seulement, ou la réactiver à chaque mise à jour. Les releases antérieures à `foyer-android.json` ne peuvent pas être publiées ainsi.

Si la configuration Android Firebase est retéléchargée après création des clients OAuth, actualiser la variable Actions `FIREBASE_ANDROID_JSON` avec la configuration **cliente**, jamais avec une clé de compte de service. Cette configuration est distincte des credentials FCM du serveur.

## 6. Avant de publier la route Internet

**État au 2026-09-24 (mis à jour) : les adaptations code pour l’exposition publique sont implémentées et couvertes par les tests automatisés.** La limitation de requêtes partitionne par adresse visiteur `CF-Connecting-IP` quand `CLIENT_IP_HEADER` est configuré (fiable uniquement parce que le port API n’est joignable que depuis la boucle locale du Mac, par le connecteur) ; les routes d’authentification (`/auth/*`, `/signin-google`) ont un budget dédié plus strict et toutes les réponses privées portent `Cache-Control: no-store`. Un en-tête usurpé sans proxy configuré est ignoré ; une valeur non parsable retombe sur le pair réseau ; le mode démo reste refusé hors boucle locale et n’existe qu’en Development.

Garder la route publique désactivée jusqu’à validation de ces points restants, qui exigent les services réels :

- Configuration réelle des clients Google OAuth (web + Android) et du serveur (`.env`, secrets), avec `CLIENT_IP_HEADER=CF-Connecting-IP`.
- Recette du parcours public avec les vrais comptes : refus anonyme, refus d’un troisième compte, cookies, sessions, révocation, uploads et images privées (étape 7).
- Vérifier après publication qu’aucune règle de cache Cloudflare ne surcharge le `no-store` applicatif et que l’offre/règles Cloudflare configurées n’interceptent pas l’API de l’APK. Les protections Cloudflare ne remplacent pas l’autorisation côté Foyer.

Une fois ces adaptations livrées et les contrôles préparatoires validés, publier pour la recette réelle, avant toute donnée familiale :

1. Dans le tunnel `foyer-mac`, choisir **Routes → Add route → Published application**.
2. Sous-domaine : `foyer` ; domaine : `jmops.fr` ; chemin : vide.
3. **Service URL : `http://127.0.0.1:5080`**. Cette adresse convient au connecteur installé **directement sur le même Mac**. Dans un conteneur cloudflared, `127.0.0.1` désignerait ce conteneur et ne conviendrait pas.
4. Enregistrer et vérifier dans le DNS Cloudflare le CNAME `foyer` vers `<ID-du-tunnel>.cfargotunnel.com`, avec proxy activé. L’assistant peut créer cet enregistrement ; vérifier avant d’en ajouter un deuxième.
5. Vérifier le certificat HTTPS public puis ouvrir **https://foyer.jmops.fr** depuis un navigateur sans Tailscale.

[Publication d’une application par Tunnel](https://developers.cloudflare.com/tunnel/get-started/#publish-an-application). Ne pas placer sans adaptation une page de connexion Cloudflare Access ou un challenge navigateur devant toute l’API : l’APK natif doit pouvoir s’authentifier via son parcours prévu. Ne jamais intégrer un token de service Access à l’APK. La protection d’accès prévue ici repose sur Google et l’allowlist de Foyer.

En cas d’anomalie pendant la recette publique, retirer/désactiver **la route Foyer** dans le tunnel, puis vérifier que l’accès externe a cessé. Ne pas supprimer la zone DNS ou le tunnel d’autres applications. Conserver les volumes et sauvegardes pour diagnostic.

## 7. Recette avant données familiales

- Depuis un navigateur Windows/Mac et l’APK, sans Tailscale : connexion de chacun des deux comptes et refus d’un troisième compte.
- Appels API/images sans session refusés, création et modification partagées, commentaires, tags, checklist, réalisation/clôture et historique.
- Révocation de session, mauvaise URL serveur, réseau coupé et reconnexion, parcours clavier/Retour Android.
- Après contrôle FCM serveur, passer `WORKERS_ENABLED=true` et recréer l’API avec `docker compose up -d api`. Tester commentaire à l’autre personne seulement, résumé à chaque horaire, app fermée/verrouillée et ouverture du bon écran.
- Vérifier le retour du moteur Docker, de Foyer et du tunnel après reboot/déverrouillage du Mac. Les notifications peuvent être retardées par Android ou la connectivité.
- Sauvegarde chiffrée hors Mac, puis restauration isolée depuis cette destination. Le DS216j peut recevoir des sauvegardes ; il n’est pas l’hôte de cette stack.

Voir [validation](validation.md) et [migration](migration.md) pour les contrôles détaillés. Les tests CI ne remplacent pas cette recette sur les vrais comptes, appareils et réseau public.
