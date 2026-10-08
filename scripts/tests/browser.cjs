const { chromium } = require('../../artifacts/browser/node_modules/playwright');
(async () => {
  const browser = await chromium.launch({headless: true});
  const page = await browser.newPage({viewport: {width: 1365, height: 900}});
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('http://localhost:5080');
  await page.locator('flt-glass-pane').waitFor({state:'attached'});
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(1500);
  await page.screenshot({path:'artifacts/browser/login.png',fullPage:true});
  await page.getByRole('button', {name:'Camille', exact:true}).click();
  await page.getByText('Aujourd’hui', {exact:true}).first().waitFor();
  await page.screenshot({path:'artifacts/browser/today-desktop.png',fullPage:true});
  await page.getByRole('button', {name:'Une nouvelle tâche'}).click();
  await page.getByRole('button', {name:'Créer',exact:true}).waitFor();
  await page.screenshot({path:'artifacts/browser/create-desktop.png',fullPage:true});
  const title = 'Peindre le meuble — navigateur ' + Date.now();
  // Les cartes se lisent par leur titre (étiquette d’accessibilité).
  const cardOf = (t) => page.getByRole('button', {name: new RegExp('^' + t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))}).first();
  await page.getByRole('textbox', {name:'Qu’est-ce qu’on a en tête ?'}).fill(title);
  await page.getByRole('button', {name:'Créer',exact:true}).click();
  await page.waitForTimeout(1000);
  await page.screenshot({path:'artifacts/browser/after-save.png'});
  await page.getByRole('button', {name:'Prévu', exact:true}).click();
  await page.getByRole('button', {name:'Un jour', exact:true}).click();
  await cardOf(title).waitFor();
  await page.screenshot({path:'artifacts/browser/unjour-desktop.png',fullPage:true});
  // Un filtre de personne choisi ailleurs ne masque rien dans le Backlog (pas de pastilles).
  await page.getByRole('button', {name:'Aujourd’hui', exact:true}).click();
  await page.getByRole('button', {name:'Alex', exact:true}).click();
  await page.getByRole('button', {name:'Prévu', exact:true}).click();
  await page.getByRole('button', {name:'Un jour', exact:true}).click();
  await cardOf(title).waitFor({timeout: 5000}).catch(() => { throw new Error('Filtre de personne caché appliqué au Backlog'); });
  await page.getByRole('button', {name:'Aujourd’hui', exact:true}).click();
  await page.getByRole('button', {name:'Tout le foyer', exact:true}).click();
  await page.getByRole('button', {name:'Prévu', exact:true}).click();
  await page.getByRole('button', {name:'Un jour', exact:true}).click();
  await cardOf(title).waitFor();
  await page.setViewportSize({width:390,height:844});
  await page.waitForTimeout(700);
  await page.screenshot({path:'artifacts/browser/backlog-mobile.png',fullPage:true});
  await cardOf(title).click();
  await page.getByRole('button', {name:'Enregistrer',exact:true}).waitFor();
  await page.waitForTimeout(500);
  await page.screenshot({path:'artifacts/browser/ticket-mobile.png',fullPage:true});
  // Actions rapides de la fiche : bloquer puis terminer, en choisissant qui l’a réalisé.
  const find = async () => (await page.evaluate(async()=> (await fetch('/api/v1/state')).json())).tickets.find(t => t.title === title);
  await page.getByRole('button', {name:'À faire'}).click();
  await page.waitForTimeout(1200);
  if ((await find()).stageId !== 'todo') throw new Error('Tâche « Un jour » non passée à faire');
  await page.getByRole('button', {name:'Bloqué'}).click();
  await page.waitForTimeout(1200);
  const waiting = await find();
  if (waiting.stageId !== 'waiting') throw new Error('Tâche non bloquée : ' + waiting.stageId);
  await page.getByRole('button', {name:'C’est fait'}).first().click();
  await page.getByText('Qui l’a réalisé ?', {exact:true}).waitFor();
  await page.getByRole('button', {name:'C’est fait', exact:true}).last().click();
  await page.waitForTimeout(1500);
  const done = await find();
  if (done.stageId !== 'done' || done.performers.length !== 1) throw new Error('Tâche non terminée : ' + done.stageId + ' ' + done.performers);
  // Raccourci : un toucher crée la tâche, « Annuler » la retire.
  // « C’est fait » a refermé la fiche : retour sur l’écran principal.
  await page.getByRole('button', {name:'Une nouvelle tâche'}).waitFor();
  const tickets = async () => (await page.evaluate(async()=> (await fetch('/api/v1/state')).json())).tickets;
  const laundries = async () => (await tickets()).filter(t => t.shortcutId && t.title === 'Faire une lessive').length;
  const before = (await tickets()).length, laundryBefore = await laundries();
  await page.getByRole('button', {name:'Une nouvelle tâche'}).click();
  await page.getByRole('button', {name:/^Faire une lessive/}).click();
  // Une lessive est peut-être déjà à faire (recette API) : l’anti-doublon demande confirmation.
  // On attend soit la confirmation, soit la tâche créée (la CI est plus lente qu’un poste local).
  const again = page.getByRole('button', {name:'En ajouter une', exact:true});
  let launched = false;
  for (let i = 0; i < 20 && !launched; i++) {
    if (await again.isVisible().catch(() => false)) await again.click();
    await page.waitForTimeout(500);
    launched = (await laundries()) === laundryBefore + 1;
  }
  if (!launched || (await tickets()).length !== before + 1) throw new Error('Raccourci non lancé');
  await page.getByRole('button', {name:'Annuler', exact:true}).click();
  await page.waitForTimeout(1500);
  if ((await tickets()).length !== before) throw new Error('Lancement non annulé');
  // Répétition : activer la suggestion de la lessive depuis Réglages → Raccourcis.
  await page.getByRole('button', {name:'Réglages', exact:true}).click();
  await page.getByText('Raccourcis', {exact:false}).first().click();
  await page.getByRole('button', {name:/^Faire une lessive/}).first().click();
  // La section « Répéter » est en bas de l’éditeur : on fait défiler jusqu’à elle.
  const auto = page.getByRole('switch', {name:/Créer automatiquement/}).or(page.getByRole('checkbox', {name:/Créer automatiquement/})).first();
  for (let i = 0; i < 8 && !(await auto.isVisible().catch(() => false)); i++) { await page.mouse.move(195, 500); await page.mouse.wheel(0, 500); await page.waitForTimeout(300); }
  await auto.click();
  await page.getByRole('button', {name:'Enregistrer', exact:true}).click();
  await page.waitForTimeout(1500);
  const lessive = (await page.evaluate(async()=> (await fetch('/api/v1/state')).json())).shortcuts.find(x => x.seedKey === 'laundry');
  if (!lessive.repeat || lessive.repeat.active !== true || lessive.repeat.every !== 3) throw new Error('Répétition non activée : ' + JSON.stringify(lessive.repeat));
  if (errors.length) throw new Error(errors.join('\n'));
  console.log('PASS : connexion, création rapide, persistance backlog, affichage mobile, fiche (Backlog → à faire, bloquer, terminer avec réalisateur), raccourci lancé puis annulé, répétition activée.');
  await browser.close();
})();
