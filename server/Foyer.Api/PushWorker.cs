using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;
namespace Foyer;

public sealed class PushWorker(Store store, Settings settings, IConfiguration config, ILogger<PushWorker> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!settings.WorkersEnabled) return;
        FirebaseMessaging? messaging = null;
        var credentialPath = config["FirebaseCredentialFile"];
        if (!string.IsNullOrWhiteSpace(credentialPath))
        {
            var credential = CredentialFactory.FromFile<ServiceAccountCredential>(credentialPath).ToGoogleCredential();
            messaging = FirebaseMessaging.GetMessaging(FirebaseApp.Create(new AppOptions { Credential = credential, ProjectId = config["FirebaseProjectId"] }));
        }
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var release = Updates.Android(settings.Updates);
                await store.Update(h => { var now = DateTimeOffset.UtcNow; Recurrence.Tick(h, now); Rules.Schedule(h, now); Rules.AnnounceUpdate(h, release?.VersionCode, now); return true; });
                if (messaging != null) await Deliver(messaging);
            }
            catch (Exception ex) { log.LogError("Traitement différé : {Type}", ex.GetType().Name); }
            await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
        }
    }
    private async Task Deliver(FirebaseMessaging messaging)
    {
        var jobs = await store.Read(h => h.Maintenance ? [] : h.Notifications.Where(n => !n.Finished && n.NextAttempt <= DateTimeOffset.UtcNow).Select(n => (Notification: n, n.Count, Devices: Rules.Recipients(h, n).Where(d => !n.DeliveredDeviceIds.Contains(d.Id)).ToList())).Take(20).ToList());
        // Count relevé avant l’envoi : une notification reprise entre-temps (rafale) n’est pas
        // marquée reçue avec l’ancien texte ; elle repartira au tour suivant.
        foreach (var (n, count, devices) in jobs)
        {
            if (n.ExpiresAt <= DateTimeOffset.UtcNow) { await Finish(n.Id); continue; }
            foreach (var d in devices)
            {
                if (await store.Read(h => h.Maintenance)) return;
                try
                {
                    var (title, body) = Notify.Text(n);
                    await messaging.SendAsync(new Message
                    {
                        Token = d.Token,
                        Notification = new FirebaseAdmin.Messaging.Notification { Title = title, Body = body },
                        Data = new Dictionary<string, string> { ["notificationId"] = n.Id, ["kind"] = n.Kind, ["ticketId"] = n.TicketId ?? "" },
                        Android = new AndroidConfig { Priority = Priority.High, CollapseKey = n.Id, TimeToLive = n.ExpiresAt - DateTimeOffset.UtcNow, Notification = new AndroidNotification { Tag = n.Id, ChannelId = Notify.Channel(n.Kind) } }
                    });
                    await store.Update(h => { var current = h.Notifications.First(x => x.Id == n.Id); if (current.Count == count) current.DeliveredDeviceIds.Add(d.Id); return true; });
                }
                catch (FirebaseMessagingException ex) when (ex.MessagingErrorCode == MessagingErrorCode.Unregistered)
                {
                    await store.Update(h => { h.Devices.RemoveAll(x => x.Id == d.Id); return true; });
                }
                catch (Exception ex) { log.LogWarning("Envoi push différé : {Type}", ex.GetType().Name); }
            }
            await store.Update(h =>
            {
                var current = h.Notifications.First(x => x.Id == n.Id);
                if (current.Count != count) return true;
                current.Attempts++;
                // Sans appareil concerné (jamais enregistré, ou déjà à jour), rien ne reste en attente.
                current.Finished = Rules.Recipients(h, current).All(d => current.DeliveredDeviceIds.Contains(d.Id));
                current.NextAttempt = DateTimeOffset.UtcNow.AddMinutes(Math.Min(60, Math.Pow(2, Math.Min(current.Attempts, 6)))); return true;
            });
        }
    }
    private Task<bool> Finish(string id) => store.Update(h => { h.Notifications.First(x => x.Id == id).Finished = true; return true; });
}
