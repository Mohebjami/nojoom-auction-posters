// These functions run in the isolated Bid.Cars browser. Keep them self-contained.
function inspectPage(vin) {
  const text = (document.body?.innerText || document.body?.textContent || '').slice(0, 180000);
  const title = document.title || '';
  const blocked = /just a moment|attention required|security verification/i.test(title) ||
    /verify (?:that )?you are human|performing security verification|checking your browser|enable javascript and cookies to continue/i.test(text);
  const visible = el => el.getClientRects().length > 0;
  const inputs = [...document.querySelectorAll('input')].filter(visible).map(el => ({
    placeholder: el.getAttribute('placeholder') || '', name: el.name || '', type: el.type,
  }));
  const links = [...document.querySelectorAll('a[href]')].map(a => {
    try {
      const u = new URL(a.getAttribute('href'), location.href);
      return { url: u.href.split('#')[0], text: a.textContent?.trim() || '' };
    } catch { return null; }
  }).filter(Boolean).filter(a => {
    const u = new URL(a.url);
    return u.protocol === 'https:' && ['bid.cars', 'www.bid.cars'].includes(u.hostname) &&
      /\/(?:lot|vehicle)\//.test(u.pathname) && u.pathname.toUpperCase().endsWith(`-${vin}`);
  });
  const headings = [...document.querySelectorAll('h1, h2, [itemprop="vehicleIdentificationNumber"]')]
    .map(el => (el.innerText || el.textContent || '').trim().toUpperCase());
  const pathMatches = /\/(?:lot|vehicle)\//.test(location.pathname) && location.pathname.toUpperCase().endsWith(`-${vin}`);
  const verified = pathMatches && headings.some(h => h === vin || h.endsWith(` ${vin}`));
  const images = [];
  if (verified) {
    for (const img of document.querySelectorAll('img')) {
      const alt = img.getAttribute('alt') || '';
      if (!alt.toUpperCase().includes(vin) || /thumbnail|360|rotation/i.test(alt) || !/photo|image|picture/i.test(alt)) continue;
      const candidates = [];
      const anchor = img.closest('[data-fancybox][data-src], a');
      if (anchor) {
        for (const name of ['data-src', 'data-fancybox-href', 'href']) {
          const value = anchor.getAttribute(name);
          if (value && !value.startsWith('#')) candidates.push(value);
        }
      }
      for (const name of ['data-full', 'data-large', 'data-original', 'data-src']) {
        if (img.getAttribute(name)) candidates.push(img.getAttribute(name));
      }
      const srcset = (img.getAttribute('data-srcset') || img.getAttribute('srcset') || '')
        .split(',').map(x => x.trim().split(/\s+/)).filter(x => x[0])
        .sort((a, b) => parseFloat(b[1] || '0') - parseFloat(a[1] || '0'));
      candidates.push(...srcset.map(x => x[0]), img.currentSrc, img.getAttribute('src'));
      for (const value of candidates.filter(Boolean)) {
        let url;
        try { url = new URL(value, location.href); } catch { continue; }
        if (url.protocol !== 'https:' || !['images.bid.cars', 'mercury.bid.cars', 'pluto.bid.car'].includes(url.hostname)) continue;
        if (/placeholder|no[-_]?image|logo|\.svg(?:\?|$)/i.test(url.href)) continue;
        images.push(url.href);
        break;
      }
    }
  }
  return {
    url: location.href, title, blocked, inputs, verified,
    links: [...new Map(links.map(a => [a.url, a])).values()],
    images: [...new Set(images)].slice(0, 200),
    noResults: /no (?:vehicles|results|cars|records)(?: were)? found|nothing found|no matches|0 vehicles|we (?:could not|couldn't) find|no vehicles matching/i.test(text),
  };
}

const callScript = (fn, ...args) => `(${fn.toString()})(${args.map(x => JSON.stringify(x)).join(',')})`;
module.exports = { inspectPage, callScript };
