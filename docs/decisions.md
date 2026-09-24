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

- Accès cible actualisé le 2026-09-24 : Cloudflare Tunnel pour web et API sur `https://foyer.jmops.fr`, domaine conservé chez IONOS et DNS géré par Cloudflare. Remplace Tailscale obligatoire pour les utilisateurs de Foyer. Adaptation code livrée le 2026-09-24 : limitation par visiteur via `CF-Connecting-IP` (configurable, fiable grâce au binding loopback), budget strict sur les routes d’authentification, `no-store` sur toutes les réponses privées. Recette publique avec comptes réels à réaliser avant activation de la route.
