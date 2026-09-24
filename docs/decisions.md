# Décisions conservées

Source : cadrage utilisateur et plan approuvé dans la conversation du 24 septembre 2026.

- Deux personnes, un foyer commun, aucune tâche privée. Connexion par comptes Google.
- Android natif installable hors store ; accès navigateur ; iOS ultérieur.
- Mac Intel sous macOS retenu comme serveur. Migration ultérieure reportée, scripts et guide exigés dès la V1. NAS DS216j non retenu comme hôte de cette stack.
- Backlog distinct des tâches actives, Aujourd’hui et Cette semaine, vue foyer par défaut et sélecteur de personne.
- Choix explicite des réalisateurs à la clôture, sans les assimiler à l’attribution. Historique pour mémoriser les décisions et responsabilités, sans classement de contribution.
- Date de début et échéance optionnelles ; résumé quotidien à heure individuelle ; notification des commentaires à l’autre membre, avec sujet.
- Images et checklist, tags colorés rapides, statuts intermédiaires adaptables.
- Fluidité et coût limité ; sécurité tenant compte du caractère familial/sensible. Aucun service payant souscrit.
- Calendrier, récurrence, mode hors connexion en écriture et notifications web reportés.

Choix techniques de cette implémentation : Flutter, ASP.NET Core 10, PostgreSQL 17, agrégat transactionnel pour deux utilisateurs et fichiers privés. Les sessions sont renouvelées lors d’une restauration ; les anciennes notifications sont neutralisées mais leur journal conservé. Voir architecture et migration pour les limites.
