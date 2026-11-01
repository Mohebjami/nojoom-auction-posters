const MODES = ['both', 'bidcars', 'nca'];
async function lookupSources(browsers, mode, vin, signal) {
  if (!MODES.includes(mode)) throw new Error('Choose a supported photo source.');
  const names = mode === 'both' ? ['bidcars', 'nca'] : [mode];
  const errors = [];
  for (const name of names) {
    signal?.throwIfAborted();
    try { return { ...await browsers[name].lookup(vin), provider: name }; }
    catch (error) {
      signal?.throwIfAborted();
      if (['SKIPPED', 'STOPPED'].includes(error.code)) throw error;
      errors.push({ name, error });
    }
  }
  const message = errors.map(({ name, error }) => `${name === 'nca' ? 'NCA' : 'Bid.Cars'}: ${error.message}`).join(' ');
  const error = new Error(message);
  if (errors.every(item => item.error.code === 'NOT_FOUND')) error.code = 'NOT_FOUND';
  throw error;
}
module.exports = { MODES, lookupSources };
