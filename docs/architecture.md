# Architecture et règles du foyer

## Structure

`client/lib` contient l’interface Flutter Android/web, le client HTTP et le stockage sécurisé de session Android. `server/Foyer.Api` regroupe le domaine, le stockage transactionnel, l’authentification et le worker FCM. `server/Foyer.Tests` couvre les règles sensibles. `compose.yaml` déploie API, base et volumes privés.

Pour deux personnes, le foyer est un agrégat JSONB unique dans PostgreSQL (`foyer_state`, schéma 1). Chaque écriture verrouille cette ligne dans une transaction. Ce choix réduit les migrations et garantit la cohérence des tickets, commentaires et notifications. Il convient à un foyer ; des milliers de pièces jointes ou un historique très volumineux nécessiteront pagination et tables séparées. Les images sont sur un volume privé, jamais dans le bundle web. Les binaires sont réencodés JPEG ; les métadonnées sensibles sont supprimées.

Une version par ticket refuse les écrasements concurrents (HTTP 409). Les étapes utilisent la révision globale du foyer. Un polling de 12 secondes actualise les autres écrans ; une panne réseau ne permet pas d’éditer hors connexion. Le formulaire conserve les modifications locales lorsqu’un conflit est signalé.

## Règles métier

- Un titre suffit pour créer un ticket dans le backlog.
- Types : obligation/envie. Priorités : basse, normale, haute, urgente.
- Étapes fixes backlog/terminé/abandonné ; étapes actives configurables classées à faire/en cours/en attente. L’étape système `todo` conserve sa fonction pour les activations automatiques.
- Attribution à zéro, un ou deux membres. À la clôture « terminé », sélectionner un ou deux réalisateurs, indépendamment des responsables. La réouverture efface les réalisateurs courants mais conserve l’événement précédent.
- Dates civiles dans le fuseau Europe/Paris ; début et échéance optionnels, début ≤ échéance. Date de début atteinte : seul un ticket encore en backlog passe à À faire. Les autres états ne sont jamais rétrogradés.
- Aujourd’hui : tickets ouverts dont une date est atteinte, ainsi que les tickets en cours. Les retards restent visibles. Un ticket À faire sans date se retrouve dans le tableau.
- Cette semaine : jusqu’au dimanche inclus, avec les retards et les tâches en cours ; les tickets datés du backlog sont inclus.
- Recherche dans titres, descriptions et commentaires au sein de la vue courante. Historique : terminés/abandonnés, filtrables par période, tags et réalisateurs. Le sélecteur principal concerne les responsables dans les vues actives. Aucun score de contribution.
- Commentaires datés, auteur identifié et notification du sujet à l’autre membre. Images limitées à 10 Mo, 40 mégapixels et 20 par ticket ; conversion à 2048 px maximum et première image seulement pour les animations.

## Notifications

Un worker toutes les 30 secondes programme les activations et résumés ; chaque personne règle son heure. Un redémarrage après l’heure prévue génère le résumé du jour, pas une cascade des jours manqués. Les notifications sont stockées dans la même transaction que le commentaire ou la transition.

FCM est un transport au mieux : reprise exponentielle plafonnée à une heure, expiration, suppression des jetons invalides et suivi des appareils déjà traités. Chaque notification a un titre qui dit qui ou quoi (« Clemence a commenté », « À faire aujourd’hui ») et un corps court : titres des tâches, et début du texte pour un commentaire. Le résumé du matin liste les tâches du jour (retards d’abord, trois titres au plus) et n’est pas envoyé les jours sans tâche. Les attributions par l’autre membre sont notifiées. Heures calmes de 22 h à l’heure du résumé : les rappels de minuit sont repris par le résumé (ou attendent cette heure s’il est désactivé), les annonces de mise à jour attendent aussi ; commentaires et attributions partent tout de suite. Toucher un commentaire ouvre son ticket ; le résumé ouvre Aujourd’hui. En premier plan, l’application montre une bannière.

La cloche de l’en-tête liste l’historique des trente derniers jours (`GET /api/v1/notifications`, purge existante) avec un badge de non-lus alimenté par `/state`. Ouvrir le panneau marque tout comme lu (`POST /api/v1/notifications/seen`, horodatage par membre) ; toucher une entrée liée à une tâche l’ouvre. Les annonces de mise à jour n’y figurent pas : ciblées par appareil (`BelowVersion`) et déjà portées par la bannière, elles seraient du bruit incohérent entre appareils. L’historique ne dépend pas de FCM : il couvre aussi le web et les pushes perdus.

### Widgets Android

Le widget « Aujourd’hui » affiche un instantané de `GET /api/v1/widget` (tâches du jour du membre, dans l’ordre du résumé) écrit par l’application via `home_widget`. Il est rafraîchi à chaque chargement de l’application, à chaque notification reçue (handler FCM d’arrière-plan) et au plus toutes les 30 minutes (le widget demande alors `foyer://refresh`, exécuté en Dart dans un isolat d’arrière-plan avec la session de l’application ; au plus une demande toutes les 5 minutes). Le code natif (`TodayWidget.kt`) ne fait que du rendu ; les touchers ouvrent l’application sur `foyer://today`, `foyer://create` ou `foyer://ticket/<id>`. Le rond d’une tâche envoie `foyer://done?id=…` : Dart appelle `POST /api/v1/tickets/{id}/done` (réalisée par le membre connecté, reste inchangé), la ligne affiche « Envoi… » puis disparaît ; hors ligne, elle réapparaît avec « Action non envoyée ».

Les touchers d’action passent par `WidgetActionReceiver` (non exporté) : la ligne passe en « envoi » immédiatement en natif, puis l’URI part vers le callback Dart de `home_widget` par notre propre file WorkManager (`APPEND_OR_REPLACE`, accélérée sur Android 12+ ; la file `APPEND` du plugin restait bloquée après un échec). Les widgets suivent la charte de l’application : palette et angles exportés par l’application ouverte (`widgetTheme`), fonds teintés sur Android 12+ (couleurs de repli avant), point d’accent des titres (« Courses. »). Les polices propres à Foyer ne sont pas disponibles dans un widget Android.

Le widget « Courses » (`ShoppingWidget.kt`) affiche la liste en cours (prochaine tâche Courses, sinon le brouillon) : articles à acheter groupés par rayon dans l’ordre du magasin, dans une liste défilante (`RemoteViewsCompat`). Toucher un article envoie `foyer://check?list=…&item=…` (Dart : `PATCH /api/v1/shopping/items/{list}/{id}`) ; l’en-tête ouvre l’onglet Courses, « + » l’ouvre avec la recherche prête (`foyer://courses?add=1`).

Un crash entre acceptation FCM et enregistrement serveur peut provoquer un renvoi ; l’identifiant/tag de notification limite les doublons visibles, sans garantie d’exactement une livraison. Aucune notification push web dans cette V1. Le contenu reste consultable dans l’application. `WORKERS_ENABLED=false` suspend aussi les passages automatiques de date ; réservé aux tests/restaurations ou à une pause volontaire.

## Évolutions prévues

Le domaine, le worker et le transport sont séparés pour ajouter rappels, récurrence et autres canaux. Schéma versionné dans les exports. iOS nécessitera configuration Apple/APNs, signature et validation spécifique ; aucune promesse de support iOS dans cet APK.

## Apparence personnelle

Réglages → Couleurs de l’application : 11 palettes prédéfinies, dont Ciel & orange et Violet & bleu nuit. Aperçu immédiat ; Annuler rétablit la palette enregistrée. Le choix est conservé par membre et synchronisé entre ses appareils, indépendamment des préférences de résumé et de l’autre membre. Les données existantes gardent Sauge & crème par défaut. Les tags et couleurs de priorité restent indépendants.

Le thème est centralisé dans `client/lib/appearance.dart`. Ajouter une palette demande une entrée (identifiant, nom et trois couleurs) dans ce catalogue et son identifiant dans `Appearance.PaletteIds` côté serveur. Les rôles Material sont dérivés pour conserver des contrastes lisibles ; un test vérifie les principales paires texte/fond à 4,5:1 minimum. Les palettes actuelles sont claires ; aucun mode sombre n’est ajouté dans cette évolution.
