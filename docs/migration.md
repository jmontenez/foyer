# Sauvegarde et migration

Les scripts fonctionnent sur Mac ou serveur Linux capable de faire tourner Docker Compose et PostgreSQL 17. **Le DS216j n’est pas une cible applicative compatible avec cette livraison.** Il peut éventuellement recevoir des archives chiffrées. Aucune migration réelle du foyer n’a été effectuée.

## Contrat

Python 3.12+, Docker Compose et `age` requis. L’export suspend les écritures, arrête l’API et le worker, puis prend un dump PostgreSQL et les images privées. Il produit une archive chiffrée age avec manifeste, version du schéma/application/PostgreSQL et SHA-256 de chaque fichier. Cette fenêtre implique une interruption d’accès. Prévoir l’espace pour le dump et les images en clair dans un répertoire temporaire privé : utiliser un disque hôte chiffré, ne pas désigner un répertoire temporaire partagé.

Préservés : membres/identités, tickets, états, affectations, réalisateurs, tags, checklists, commentaires, historique, préférences et images. Le journal des notifications est conservé, mais les jobs restaurés sont marqués terminés pour éviter des pushes anciens ou doubles. Les sessions et appareils sont invalidés : reconnexion des deux personnes requise, puis nouveaux jetons FCM. Le prochain résumé est programmé selon la date et l’heure enregistrées ; pas de renvoi automatique du résumé déjà marqué généré ce jour-là.

Les credentials OAuth/FCM/DB, clés Data Protection et signature APK ne sont pas exportés. Les reprovisionner séparément depuis le coffre. La clé privée age ne voyage pas avec l’archive.

## Sauvegarde quotidienne

Créer votre clé age avec `age-keygen -o /chemin/prive/foyer.agekey`, conserver la clé privée hors du serveur et noter la clé publique destinataire. Ne communiquer à l’automate que cette clé publique.

```sh
scripts/migration/preflight.sh
scripts/migration/export.sh --recipient age1_CLE_PUBLIQUE --output /destination/foyer-manuel.age
scripts/migration/verify.sh --identity /chemin/prive/foyer.agekey --archive /destination/foyer-manuel.age
```

Par défaut l’API est relancée après l’export. Aucun fichier existant n’est remplacé. `verify` authentifie le chiffrement et vérifie les empreintes ; cela ne remplace pas une restauration. Une extinction brutale de l’hôte pendant l’export peut laisser la source en maintenance : diagnostiquer avant `python3 scripts/migration/foyer.py resume-source`.

`scripts/backup.py --destination /Volumes/SAUVEGARDES/Foyer --recipient age1_…` crée un export horodaté et conserve un exemplaire pour chacun des 7 derniers jours représentés et 4 dernières semaines représentées. Seuls ses fichiers `foyer-YYYYMMDDTHHMMSSZ.age` sont candidats à rotation. Utiliser un dossier dédié. Aucun effacement n’a lieu si l’export échoue.

Adapter `deploy/fr.foyer.backup.plist.example` aux chemins réels, au contexte Docker et à la clé publique ; l’installer comme LaunchAgent seulement après un test manuel. Le modèle n’a pas été activé. Vérifier la présence du volume distant, les logs, l’heure de dernière archive et la reprise après reboot. Une copie chiffrée qui reste uniquement sur le Mac ne suffit pas.

## Exercice préalable et migration finale

1. Installer sur la cible **la même version du code** et le build web, puis construire l’image pour son architecture. Configurer secrets et origine cible ; `WORKERS_ENABLED=false` obligatoire. Utiliser une base et un volume images vierges, projet Compose distinct. Ne pas démarrer l’API cible avant restauration.
2. Sur la source : sauvegarde courante puis export final avec `--keep-maintenance`. L’API source reste arrêtée et la base en maintenance. Noter l’heure de début. Aucun autre processus ne doit écrire dans les volumes.
3. Transférer l’archive chiffrée. Fournir la clé de déchiffrement par un canal distinct. Contrôler l’archive, puis restaurer sur la cible :

   ```sh
   scripts/migration/verify.sh --identity /coffre/foyer.agekey --archive /transfert/final.age
   scripts/migration/restore.sh --identity /coffre/foyer.agekey --archive /transfert/final.age
   docker compose up -d api
   docker compose ps
   ```

4. Vérifier santé API, nombre de tickets, photos, auteurs, réalisateurs et historique, puis les deux connexions Google. Tester l’accès anonyme et un troisième compte. Laisser les workers désactivés pendant toute la recette ; les données modifiées sur cette cible de recette ne retournent pas implicitement à la source.
5. Si l’URL change : adapter `PUBLIC_ORIGIN`, les redirections OAuth, la route du tunnel Cloudflare et l’adresse dans les clients Android. Une URL stable ne doit être déplacée qu’après arrêt de la source. Ne jamais exécuter deux sources de vérité en parallèle.
6. Après validation : ouvrir la cible aux utilisateurs, activer `WORKERS_ENABLED=true` et recréer l’API, enregistrer les appareils reconnectés, tester commentaire et résumé. Noter fin d’interruption et effectuer une sauvegarde de la nouvelle source.

`FOYER_COMPOSE_FILE=/chemin/compose.yaml` et `FOYER_PROJECT=nom-isole` permettent de cibler une autre installation ; `DOCKER_CONTEXT` choisit son moteur. Ces paramètres sont obligatoires pour un exercice sur le même moteur afin de ne pas toucher la source.

## Retour arrière

**Avant toute nouvelle écriture sur la cible** : arrêter la cible, conserver ses volumes pour diagnostic, puis `python3 scripts/migration/foyer.py resume-source` sur la source. Vérifier santé, accès et notifications avant réouverture.

**Après nouvelles écritures sur la cible** : ne pas rallumer simplement l’ancienne source. Arrêter les écritures cible, en faire un export final, restaurer dans une nouvelle installation vierge compatible sur l’ancien hôte, vérifier puis basculer. Une réconciliation manuelle peut être nécessaire si deux serveurs ont accepté des changements. Les scripts refusent les bases/volumes déjà peuplés ; ils ne proposent pas de remplacement forcé.

En cas d’échec partiel de restauration, conserver la cible arrêtée pour diagnostic et repartir sur un nouveau projet Compose. Ne pas supprimer de volume avant d’avoir vérifié qu’aucune donnée utile n’y réside.

## Exercice livré

`scripts/tests/migration.py` a été exécuté sur des données fictives dans deux projets isolés : export age, restauration PostgreSQL/images, santé API, refus de remplacer une cible peuplée, absence de sessions/devices et jobs anciens actifs, reprise de la source, refus d’une archive altérée. Les projets de test sont arrêtés et leurs volumes conservés. Cela valide les scripts localement, pas encore le réseau ni les identités Google de la future installation.
