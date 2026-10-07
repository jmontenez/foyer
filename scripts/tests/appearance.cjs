const { chromium } = require('../../artifacts/browser/node_modules/playwright');
(async () => {
  const browser = await chromium.launch({headless:true});
  const page = await browser.newPage({viewport:{width:390,height:844}});
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  async function semantics() {
    await page.locator('flt-glass-pane').waitFor({state:'attached'});
    await page.evaluate(()=>document.querySelector('flt-semantics-placeholder')?.click());
  }
  async function appearance() {
    await page.getByRole('button',{name:'Réglages',exact:true}).click();
    await page.getByText('Apparence',{exact:false}).first().click();
    await page.getByRole('button',{name:'Enregistrer',exact:true}).waitFor();
  }
  async function colors() {
    await page.getByRole('button',{name:/^Couleurs/}).click();
    await page.getByText('Vos couleurs',{exact:true}).waitFor();
  }
  async function me() { return (await page.evaluate(async()=> (await fetch('/api/v1/state')).json())).me; }
  async function save() {
    await page.getByRole('button',{name:'Enregistrer',exact:true}).click();
    await page.waitForTimeout(800);
  }
  await page.goto('http://localhost:5080');
  await semantics();
  await page.getByRole('button',{name:'Camille',exact:true}).click();
  // Couleurs choisies depuis l’écran Apparence, puis enregistrées.
  await appearance();
  await colors();
  await page.getByText('Violet & bleu nuit',{exact:true}).click();
  await page.waitForTimeout(400);
  await page.screenshot({path:'artifacts/browser/palettes-violet-mobile.png'});
  await page.getByRole('button',{name:'Enregistrer mes couleurs',exact:true}).click();
  await save();
  if((await me()).paletteId !== 'violet-navy') throw Error('Palette non enregistrée');
  // Aperçu puis annulation : rien n’est enregistré.
  await page.reload();
  await semantics();
  await appearance();
  await colors();
  await page.getByText('Ciel & orange',{exact:true}).click();
  await page.getByRole('button',{name:'Enregistrer mes couleurs',exact:true}).click();
  await page.getByRole('button',{name:'Annuler',exact:true}).click();
  await page.waitForTimeout(500);
  if((await me()).paletteId !== 'violet-navy') throw Error('Annulation non respectée');
  // Palette v2 de la refonte : onglet « Découpes », veillée appliquée telle quelle.
  await appearance();
  await colors();
  await page.getByText('Découpes',{exact:true}).click();
  await page.getByText('Braise, veillée',{exact:true}).click();
  await page.waitForTimeout(400);
  await page.screenshot({path:'artifacts/browser/apparence-braise-veillee-mobile.png'});
  await page.getByRole('button',{name:'Enregistrer mes couleurs',exact:true}).click();
  await save();
  let m=await me();
  if(m.paletteId !== 'd2-braise-nuit') throw Error('Palette v2 non enregistrée : '+m.paletteId);
  // Réglage de densité conservé après rechargement, avec la palette.
  await page.reload();
  await semantics();
  await appearance();
  await page.getByRole('button',{name:'Compacte',exact:true}).click();
  await save();
  m=await me();
  if(m.density !== 'compact' || m.paletteId !== 'd2-braise-nuit') throw Error('Densité non enregistrée');
  // Le sélecteur de couleurs rouvre sur l’onglet de la palette choisie.
  await appearance();
  await colors();
  await page.getByText('Braise, veillée',{exact:false}).waitFor();
  await page.getByRole('button',{name:'Annuler',exact:true}).click();
  await page.getByRole('button',{name:'Annuler',exact:true}).click();
  if(errors.length) throw Error(errors.join('\n'));
  console.log('PASS : écran Apparence, couleurs, palette v2 veillée, densité, annulation et persistance après rechargement.');
  await browser.close();
})();
