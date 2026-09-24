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
  async function picker() {
    await page.getByRole('button',{name:'Réglages',exact:true}).click();
    await page.getByText('Couleurs de l’application',{exact:false}).click();
    await page.getByText('Vos couleurs',{exact:true}).waitFor();
  }
  await page.goto('http://localhost:5080');
  await semantics();
  await page.getByRole('button',{name:'Camille',exact:true}).click();
  await picker();
  await page.getByText('Violet & bleu nuit',{exact:true}).click();
  await page.waitForTimeout(400);
  await page.screenshot({path:'artifacts/browser/palettes-violet-mobile.png'});
  await page.getByRole('button',{name:'Enregistrer mes couleurs',exact:true}).click();
  await page.waitForTimeout(700);
  let state=await page.evaluate(async()=> (await fetch('/api/v1/state')).json());
  if(state.me.paletteId !== 'violet-navy') throw Error('Palette non enregistrée');
  await page.reload();
  await semantics();
  await picker();
  await page.getByText('Ciel & orange',{exact:true}).click();
  await page.getByRole('button',{name:'Annuler',exact:true}).click();
  state=await page.evaluate(async()=> (await fetch('/api/v1/state')).json());
  if(state.me.paletteId !== 'violet-navy') throw Error('Annulation non respectée');
  await picker();
  await page.getByText('Ciel & orange',{exact:true}).click();
  await page.getByRole('button',{name:'Enregistrer mes couleurs',exact:true}).click();
  await page.waitForTimeout(700);
  await page.screenshot({path:'artifacts/browser/sky-orange-mobile.png'});
  state=await page.evaluate(async()=> (await fetch('/api/v1/state')).json());
  if(state.me.paletteId !== 'sky-orange') throw Error('Palette ciel non enregistrée');
  if(errors.length) throw Error(errors.join('\n'));
  console.log('PASS : choix violet/ciel, aperçu mobile, persistance après rechargement et annulation.');
  await browser.close();
})();
