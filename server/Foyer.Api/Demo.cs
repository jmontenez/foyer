namespace Foyer;

// Démonstration publique (PublicDemo) : instance séparée, ouverte à tous, sur des données
// fictives remises à zéro chaque nuit. Jamais de compte réel, de secret ni de notification.
public static class Demo
{
    public const int MaxTickets = 150, MaxCommentsPerTicket = 30, MaxTags = 30, MaxSessions = 300;
    public const string Limit = "Limite de la démonstration atteinte (remise à zéro chaque nuit).";

    // Raison de refuser le démarrage, ou null. Verrou contre une activation sur de vraies données :
    // adresses réservées (.invalid, RFC 2606) uniquement, aucun secret Google/Firebase, aucun envoi.
    public static string? Refusal(Settings settings, IConfiguration config)
    {
        if (settings.AllowedEmails.Length != 2 || settings.AllowedEmails.Any(e => !e.EndsWith(".invalid", StringComparison.OrdinalIgnoreCase)))
            return "PublicDemo exige deux adresses fictives en .invalid.";
        if (!string.IsNullOrEmpty(settings.GoogleClientId) || !string.IsNullOrEmpty(config["GoogleClientSecret"]))
            return "PublicDemo refuse toute configuration Google.";
        if (!string.IsNullOrEmpty(config["FirebaseCredentialFile"]) || settings.WorkersEnabled)
            return "PublicDemo refuse Firebase et les traitements différés.";
        return null;
    }

    // Les connexions de démonstration s’accumulent : on ne garde que les plus récentes.
    public static void PruneSessions(Household h)
    {
        var extra = h.Sessions.Count - MaxSessions;
        if (extra <= 0) return;
        var dropped = h.Sessions.OrderBy(s => s.CreatedAt).Take(extra).Select(s => s.Hash).ToHashSet();
        h.Sessions.RemoveAll(s => dropped.Contains(s.Hash));
        h.Devices.RemoveAll(d => dropped.Contains(d.SessionHash));
    }

    // Remplace tout le foyer par le jeu de démonstration (sessions comprises : chacun se reconnecte).
    public static void Reset(Household h, Settings settings, DateTimeOffset now)
    {
        var seed = Seed(settings, Rules.Today(h, now), now);
        h.Maintenance = false;
        h.Members = seed.Members; h.Stages = seed.Stages; h.Tags = seed.Tags; h.Tickets = seed.Tickets;
        h.Sessions = []; h.Devices = []; h.Notifications = [];
        h.Shortcuts = seed.Shortcuts; h.ShortcutsSeeded = true; h.RepeatsSuggested = true;
    }

    public static Household Seed(Settings settings, DateOnly today, DateTimeOffset now)
    {
        var h = new Household();
        var camille = new Member { Subject = "demo-0", Email = settings.AllowedEmails[0], Name = "Camille", PaletteId = "ember-night", FontId = "grotesk" };
        var alex = new Member { Subject = "demo-1", Email = settings.AllowedEmails[1], Name = "Alex", PaletteId = "sage", FontId = "serif" };
        h.Members = [camille, alex];
        string C = camille.Id, A = alex.Id;
        var n = 0;
        Ticket T(string title, string kind, string priority, string stage, int? start, int? due, string[] who, int[] tags,
            (string, bool)[]? steps = null, string[]? performers = null, int? closedDaysAgo = null, string? description = null)
        {
            var t = new Ticket
            {
                Number = ++n, Title = title, Kind = kind, Priority = priority, StageId = stage, Description = description ?? "",
                StartDate = start is { } s ? today.AddDays(s) : null, DueDate = due is { } d ? today.AddDays(d) : null,
                Assignees = [.. who], Performers = [.. performers ?? []], TagIds = [.. tags.Select(i => h.Tags[i].Id)],
                Checklist = [.. (steps ?? []).Select((x, i) => new CheckItem($"c{i}", x.Item1, x.Item2))],
                CreatedAt = now.AddDays(-4), UpdatedAt = now.AddHours(-n),
            };
            if (closedDaysAgo is { } ago) t.ClosedAt = now.AddDays(-ago);
            t.History.Add(new(Guid.NewGuid().ToString("N"), who.FirstOrDefault() ?? C, "created", "Tâche créée", t.CreatedAt));
            h.Tickets.Add(t);
            return t;
        }
        // Tags par défaut : 0 Bricolage, 1 Intérieur, 2 Extérieur, 4 Santé, 5 Famille, 6 Administratif,
        // 7 Courses, 8 Entretien, 9 Voiture, 10 Vacances, 11 Finances.
        T("Réparer la fuite sous l’évier", "obligation", "urgent", "doing", null, 0, [C], [8], [("Acheter un joint", true), ("Couper l’eau", true), ("Changer le joint", false)])
            .Comments.Add(new("m1", A, "J’ai trouvé le bon joint, je m’en occupe samedi si besoin.", now.AddHours(-2)));
        T("Déclaration d’impôts", "obligation", "high", "waiting", null, -1, [C], [6, 11], [("Rassembler les justificatifs", true), ("Remplir en ligne", false)])
            .Comments.Add(new("m2", C, "Il manque encore l’attestation de la mutuelle.", now.AddHours(-20)));
        T("Courses de la semaine", "obligation", "normal", "todo", 0, 1, [], [7], [("Lait", false), ("Pain", false), ("Légumes", true)]);
        T("Rendez-vous contrôle technique", "obligation", "high", "todo", null, 2, [A], [9]);
        T("Tailler la haie", "obligation", "normal", "todo", null, 5, [A], [2]);
        T("Anniversaire de Mamie : trouver un cadeau", "obligation", "normal", "todo", null, 9, [C, A], [5], description: "Idées : un album photo, un atelier poterie.");
        T("Réserver le week-end à la mer", "wish", "normal", "backlog", 20, null, [C, A], [10]);
        T("Repeindre la chambre", "wish", "low", "backlog", null, null, [], [0, 1]);
        T("Trier les photos de vacances", "wish", "low", "backlog", null, null, [A], [5]);
        T("Vaccin du chat", "obligation", "normal", "done", null, null, [C], [4], performers: [C], closedDaysAgo: 2);
        T("Payer la cantine", "obligation", "normal", "done", null, null, [C], [11], performers: [C], closedDaysAgo: 1);
        T("Monter l’étagère", "obligation", "normal", "done", null, null, [C, A], [0], performers: [C, A], closedDaysAgo: 3);
        T("Rendre les livres à la médiathèque", "obligation", "low", "abandoned", null, null, [A], [5], closedDaysAgo: 8);
        Shortcuts.SeedOnce(h);
        Recurrence.SuggestOnce(h);
        // Une lessive déjà faite : « dernière fois il y a 2 jours » dans le panneau de création.
        T("Faire une lessive", "obligation", "normal", "done", null, null, [A], [8], performers: [A], closedDaysAgo: 2).ShortcutId = h.Shortcuts.First(s => s.SeedKey == "laundry").Id;
        return h;
    }
}

// Remet la démonstration à zéro au démarrage (si vide) puis chaque nuit à 4 h, heure du foyer.
public sealed class DemoReset(Store store, Settings settings, ILogger<DemoReset> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!settings.PublicDemo) return;
        if (await store.Read(h => h.Members.Count == 0))
            await store.Update(h => { Demo.Reset(h, settings, DateTimeOffset.UtcNow); return true; });
        while (!stoppingToken.IsCancellationRequested)
        {
            var zone = TimeZoneInfo.FindSystemTimeZoneById(await store.Read(h => h.TimeZone));
            var local = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, zone);
            var next = new DateTimeOffset(local.Date.AddHours(4), local.Offset);
            if (next <= local) next = next.AddDays(1);
            // Sans traitements différés en démonstration : les répétitions avancent ici, chaque minute.
            while (DateTimeOffset.UtcNow < next && !stoppingToken.IsCancellationRequested)
            {
                await store.Update(h => { var now = DateTimeOffset.UtcNow; Recurrence.Tick(h, now); Rules.Schedule(h, now); h.Notifications.Clear(); return true; });
                var wait = next - DateTimeOffset.UtcNow;
                await Task.Delay(wait < TimeSpan.FromMinutes(1) ? (wait > TimeSpan.Zero ? wait : TimeSpan.Zero) : TimeSpan.FromMinutes(1), stoppingToken);
            }
            await store.Update(h => { Demo.Reset(h, settings, DateTimeOffset.UtcNow); return true; });
            log.LogInformation("Démonstration remise à zéro.");
        }
    }
}
