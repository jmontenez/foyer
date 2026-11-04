const { chromium } = require('../../artifacts/browser/node_modules/playwright');
(async () => {
  const browser = await chromium.launch({headless:true});
  const page = await browser.newPage({viewport:{width:390,height:844}});
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  const state = async () => page.evaluate(async()=> (await fetch('/api/v1/state')).json());
  const api = (method, path, body) => page.evaluate(async ([method, path, body]) => {
    const r = await fetch(path, {method, headers:{'Content-Type':'application/json','X-Foyer-CSRF':'1'}, body: body ? JSON.stringify(body) : undefined});
    if (!r.ok) throw new Error(method + ' ' + path + ' : ' + r.status + ' ' + await r.text());
  }, [method, path, body]);
  // Nom neuf à chaque passage : le catalogue retient les ingrédients des recettes précédentes.
  const fresh = 'Frites ' + Math.random().toString(36).slice(2, 7);
  const draft = async () => (await state()).shopping.lists.find(l => l.id === 'draft').items;
  // Les puces se lisent comme des cases à cocher (FilterChip) ou des choix (ChoiceChip).
  const chip = (name) => page.getByRole('checkbox',{name,exact:true}).or(page.getByRole('radio',{name,exact:true})).or(page.getByRole('button',{name,exact:true})).first();
  // Saisie dans la recherche : Flutter web crée le vrai champ au focus, on réessaie si besoin.
  const type = async (text, expected, field = 'Un ingrédient…') => {
    const box = page.getByRole('textbox',{name:field});
    for (let i = 0; i < 5; i++) {
      await box.click();
      await page.keyboard.press('ControlOrMeta+A');
      await page.keyboard.type(text);
      if (await expected.waitFor({timeout:3000}).then(() => true, () => false)) return;
    }
    throw new Error('Recherche sans effet : ' + text);
  };
  const until = async (check, what) => {
    for (let i = 0; i < 20; i++) { if (await check()) return; await page.waitForTimeout(400); }
    throw new Error(what);
  };
  await page.goto('http://localhost:5080');
  await page.locator('flt-glass-pane').waitFor({state:'attached'});
  await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
  await page.getByRole('button',{name:'Camille',exact:true}).click();
  await page.getByRole('button',{name:'Courses',exact:true}).first().waitFor();
  // Départ propre : les recettes précédentes ont pu laisser des courses ouvertes.
  for (const l of (await state()).shopping.lists.filter(l => l.id !== 'draft')) {
    const t = (await state()).tickets.find(x => x.id === l.id);
    await api('PUT', '/api/v1/tickets/' + t.id, {...t, stageId:'abandoned', performers:[]});
  }
  for (const item of await draft()) await api('DELETE', '/api/v1/shopping/items/draft/' + item.id);
  await page.reload();
  await page.locator('flt-glass-pane').waitFor({state:'attached'});
  await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());

  // Téléphone : la liste est l'écran ; « Ajouter un ingrédient » lève une feuille
  // (recherche + habituels). Un toucher sur un habituel l'ajoute (quantité mémorisée).
  await page.getByRole('button',{name:'Courses',exact:true}).click();
  await page.getByRole('button',{name:'Ajouter un ingrédient',exact:true}).click();
  await chip('Lait').waitFor();
  await page.screenshot({path:'artifacts/browser/courses-ajout-mobile.png'});
  await chip('Lait').click();
  await until(async () => (await draft()).some(i => i.text === 'Lait' && i.aisle === 'dairy'), 'Lait non ajouté directement');
  await page.getByRole('button',{name:'Modifier',exact:true}).click();
  await page.getByRole('textbox',{name:'Quantité'}).fill('2 L');
  await page.getByRole('button',{name:'Enregistrer',exact:true}).first().click();
  await until(async () => (await draft()).some(i => i.text === 'Lait' && i.qty === '2 L' && i.aisle === 'dairy'), 'Quantité non enregistrée');
  // Déjà dans la liste : la puce passe en « sélectionnée » et montre la quantité.
  await chip('Lait · 2 L').waitFor();
  // Nouvel ingrédient, rangé au rayon Surgelés.
  const addFresh = page.getByRole('button',{name:'Ajouter « ' + fresh + ' » Nouvel ingrédient'});
  await type(fresh, addFresh);
  await addFresh.click();
  await chip('Surgelés').click();
  await page.getByRole('button',{name:'Ajouter',exact:true}).click();
  await until(async () => (await draft()).some(i => i.text === fresh && i.aisle === 'frozen'), 'Nouvel ingrédient non ajouté');
  const known = (await state()).shopping.ingredients.find(i => i.name === fresh);
  if (!known || known.aisle !== 'frozen') throw new Error('Rayon non mémorisé');
  // Recherche tolérante : « frite » retrouve l’ingrédient, marqué dans la liste.
  await type(fresh.slice(0, 9), page.getByRole('button',{name:fresh + ' Dans la liste'}));
  await page.screenshot({path:'artifacts/browser/courses-recherche-mobile.png'});
  await page.getByRole('button',{name:'Effacer',exact:true}).click();
  // Ordre des rayons : l’écran s’ouvre depuis le menu.
  await page.getByRole('button',{name:'Plus d’options',exact:true}).click();
  await page.getByRole('menuitem',{name:'Ordre des rayons'}).or(page.getByRole('button',{name:'Ordre des rayons'})).or(page.getByText('Ordre des rayons',{exact:true})).first().click();
  await page.getByText('Glisser pour réordonner',{exact:false}).waitFor();
  await page.screenshot({path:'artifacts/browser/courses-rayons-mobile.png'});
  await page.getByRole('button',{name:'Back'}).click();
  // Modifier un ingrédient : le nouveau nom suit dans la liste en cours. La saisie Flutter web
  // sous Playwright est parfois ignorée : l’étape entière est retentée (vérification stricte).
  await page.getByRole('button',{name:'Plus d’options',exact:true}).click();
  await page.getByRole('menuitem',{name:'Ingrédients'}).or(page.getByRole('button',{name:'Ingrédients'})).or(page.getByText('Ingrédients',{exact:true})).first().click();
  const renamedTo = fresh + ' four';
  const isRenamed = async () => (await draft()).some(i => i.text === renamedTo);
  for (let attempt = 0; attempt < 3 && !(await isRenamed()); attempt++) {
    const entry = page.getByRole('button',{name:new RegExp('^' + fresh + '( |$)')}).first();
    await type(fresh, entry, 'Chercher un ingrédient…');
    await entry.click();
    const nameBox = page.getByRole('textbox',{name:'Nom'});
    await nameBox.waitFor();
    await nameBox.click();
    await page.waitForTimeout(300);
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.type(renamedTo);
    await page.waitForTimeout(300);
    await page.getByRole('button',{name:'Enregistrer',exact:true}).click();
    for (let i = 0; i < 10 && !(await isRenamed()); i++) await page.waitForTimeout(400);
    if (!(await isRenamed()) && await page.getByRole('button',{name:'Enregistrer',exact:true}).isVisible().catch(() => false)) await page.keyboard.press('Escape');
  }
  if (!(await isRenamed())) throw new Error('Ingrédient non renommé dans la liste');
  await page.screenshot({path:'artifacts/browser/courses-ingredients-mobile.png'});
  await page.getByRole('button',{name:'Back'}).click();
  const renamed = fresh + ' four';
  // Fermer la feuille d'ajout : la liste redevient l'écran principal.
  await page.getByRole('button',{name:'Fermer',exact:true}).click();
  await page.getByRole('heading',{name:/^SURGELÉS/}).waitFor();
  await page.screenshot({path:'artifacts/browser/courses-liste-mobile.png', fullPage:true});

  // En magasin : on coche un article ; « Courses faites ! » range les achats dans
  // l'historique (tâche déjà faite) et garde les non achetés dans le brouillon.
  await chip('En magasin').click();
  await page.getByRole('checkbox',{name:/^Lait/}).click();
  await until(async () => (await draft()).find(i => i.text === 'Lait')?.done === true, 'Lait non coché');
  await page.getByRole('heading',{name:/^DANS LE PANIER/}).waitFor();
  await page.screenshot({path:'artifacts/browser/courses-panier-mobile.png', fullPage:true});
  await page.getByRole('button',{name:'Courses faites !',exact:true}).click();
  // Feuille « Qui l'a réalisé ? » : le réalisateur est pré-choisi, on valide.
  await page.getByRole('button',{name:'Courses faites',exact:true}).click();
  await until(async () => (await state()).tickets.some(t => t.shopping && t.stageId === 'done'), 'Tâche Courses faite non créée');
  await page.screenshot({path:'artifacts/browser/courses-faites-mobile.png'});
  const back = await draft();
  if (back.length !== 1 || back[0].text !== renamed || back[0].done) throw new Error('Non acheté non gardé dans le brouillon : ' + JSON.stringify(back));
  if(errors.length) throw Error(errors.join('\n'));
  console.log('PASS : accès rapide, « déjà dans la liste », nouvel ingrédient et rayon, recherche, En magasin + « Courses faites » (checkout), brouillon conservé.');
  await browser.close();
})();
