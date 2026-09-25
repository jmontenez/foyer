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
  await page.getByText('Backlog Tab 4 of 5', {exact:true}).click();
  await cardOf(title).waitFor();
  await page.screenshot({path:'artifacts/browser/backlog-desktop.png',fullPage:true});
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
  if ((await find()).stageId !== 'todo') throw new Error('Tâche du Backlog non passée à faire');
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
  const again = page.getByRole('button', {name:'En ajouter une', exact:true});
  if (await again.isVisible({timeout: 1500}).catch(() => false)) await again.click();
  await page.waitForTimeout(1500);
  if ((await tickets()).length !== before + 1 || (await laundries()) !== laundryBefore + 1) throw new Error('Raccourci non lancé');
  await page.getByRole('button', {name:'Annuler', exact:true}).click();
  await page.waitForTimeout(1500);
  if ((await tickets()).length !== before) throw new Error('Lancement non annulé');
  if (errors.length) throw new Error(errors.join('\n'));
  console.log('PASS : connexion, création rapide, persistance backlog, affichage mobile, fiche (Backlog → à faire, bloquer, terminer avec réalisateur), raccourci lancé puis annulé.');
  await browser.close();
})();
