# Sécurité et exploitation

## Modèle de confiance

Données familiales privées, potentiellement sensibles (santé, habitudes et photos). Le serveur peut les lire : **pas de chiffrement de bout en bout**. L’hôte macOS, le moteur Docker, les sauvegardes déchiffrées et les deux comptes Google constituent le périmètre de confiance. Aucun compte/service d’entreprise n’est nécessaire.

| Menace | Mesure implémentée | Limite / exploitation |
|---|---|---|
| Accès depuis Internet ou LAN | API liée à loopback, HTTPS public terminé par Cloudflare et acheminé par un tunnel sortant (`cloudflared` local) | Cloudflare voit le trafic en clair et devient un intermédiaire de confiance ; aucun port entrant ouvert sur la box |
| Abus depuis Internet (force brute, déni applicatif) | Limitation par adresse visiteur `CF-Connecting-IP` (180 req/min), budget dédié plus strict sur `/auth/*` et `/signin-google` (30 req/min) | La confiance dans l’en-tête repose sur le binding loopback du port API : si ce binding change, revoir `CLIENT_IP_HEADER`. Les protections DDoS Cloudflare dépendent de l’offre |
| Mise à jour Android piégée | APK servi uniquement aux membres connectés depuis un répertoire en lecture seule ; publication refusée si taille/SHA-256 ne concordent pas avec le manifeste CI ; l’application revérifie taille, SHA-256, paquet et version avant de lancer l’installateur, qui impose la même signature | L’autorisation « installer des applications » accordée à Foyer reste active tant qu’elle n’est pas retirée ; la confiance repose sur la clé de signature dédiée et sur l’accès au Mac serveur |
| Déploiement automatique détourné | Le Mac tire les releases (aucun accès entrant) ; jeton fine-grained en lecture seule limité au dépôt ; release acceptée seulement si publiée par Actions, commit appartenant à `main`, empreintes cohérentes ; exécution sous le compte de service ; rollback automatique si `/health` échoue | Quiconque peut fusionner sur `main` déploie en production : protéger le compte GitHub (MFA/passkey) et la branche ; jeton à renouveler, jamais affiché |
| Troisième compte | Allowlist de deux emails, identité Google validée et sujet stable | Protéger les comptes Google par MFA/passkeys ; changement de compte à traiter explicitement |
| Vol de session | Jeton opaque aléatoire, SHA-256 côté base, expiration 30 jours ; cookie HttpOnly/Secure/SameSite, coffre Android | Session utilisable jusqu’à révocation si appareil déverrouillé compromis |
| Révocation/concurrence | Sessions listées et révocables, revalidation transactionnelle, version des tickets | L’écran distant peut rester affiché jusqu’au prochain polling ; prochaine requête refusée |
| CSRF et fuite interorigines | En-tête obligatoire et origine exacte pour web, pas de CORS ouvert | XSS de même origine resterait critique ; contenu familial affiché comme texte, aucun HTML interprété |
| Fichiers malveillants | Taille/dimensions/nombre limités, décodage + réencodage JPEG, métadonnées retirées, nom généré | Maintenir ImageSharp et limiter l’accès aux comptes autorisés |
| Fuite via images | Route authentifiée, volume hors webroot, réponses sans cache | Les utilisateurs peuvent volontairement enregistrer/capturer une image |
| Fuite par logs | Pas de corps/token dans les logs applicatifs ; logs ASP.NET restreints | Ne pas activer les logs HTTP détaillés en production, notamment sur OAuth |
| Données perdues | PostgreSQL transactionnel, sauvegarde base + images cohérente et chiffrée | Destination hors Mac et rotation à configurer ; RPO correspondant à la dernière sauvegarde réussie |
| Exposition push | Résumé générique, commentaires sans leur contenu | Le sujet est transmis à Google/FCM et peut apparaître sur l’écran verrouillé ; réglage Android masquable |

Le compte DB utilisé est propriétaire de la base domestique dédiée ; PostgreSQL n’est pas publié sur le réseau de production. L’API tourne avec l’utilisateur non root de l’image .NET, capacités supprimées. Les secrets montés et la clé de signature APK ne font pas partie du code ni de l’export de configuration.

## Disponibilité

Le Mac doit rester allumé, connecté et hors veille. Une coupure suspend l’accès et la génération des rappels. Les notifications peuvent être retardées par Android, Internet ou FCM. Aucun engagement de disponibilité commerciale ; santé API `/health`, santé Compose et vérification externe à prévoir selon besoin.

Surveiller espace disque hôte **et VM Docker**, santé des deux services, date de dernière sauvegarde et erreurs de worker. Les logs ne doivent pas accumuler indéfiniment : Compose applique une rotation locale. Les commentaires et images ne disposent pas encore d’une politique automatique de purge : leur conservation fait partie de la mémoire du foyer.

## Entretien

Mensuel : mises à jour macOS/moteur de conteneurs, revue des dépendances, sauvegarde avant mise à jour, tests puis redéploiement. Conserver le même tag/code applicatif et PostgreSQL 17 pour une restauration ; une future montée majeure PostgreSQL demandera une procédure dédiée.

Les packages NuGet et Dart sont verrouillés dans les fichiers lock. Les images de base utilisent des tags majeurs maintenus ; avant une exploitation durable, enregistrer les digests des images validées dans le dossier de livraison et les actualiser après recette.

Tester chaque trimestre une restauration sur un projet Compose distinct, notifications désactivées. Une copie locale seule ne protège pas contre la perte du Mac. Garder la clé `age` et la clé de signature APK dans le gestionnaire de secrets avec récupération indépendante.

## État de validation

Les contrôles locaux automatisés ne constituent pas un audit/pentest indépendant. Voir [validation](validation.md) pour distinguer ce qui a réellement été exécuté des vérifications à faire avec les comptes et téléphones réels.
