import {checkListing} from './auction.js';

export async function runVehicles({auction, vehicles, publish = false, startItem, state = {}, saveState = async () => {}, record = async () => {}, capture = async () => {}}) {
  let nextItem = startItem;
  for (const vehicle of vehicles) {
    try {
      const match = await auction.findVehicle(vehicle.vin);
      const listings = await auction.listings();
      const existing = listings.find(row => row.lot === match.lot);
      if (existing) {
        checkListing(existing, vehicle);
        if (publish) {
          state[vehicle.vin] = {...vehicle, lot: match.lot, item: existing.item, status: 'verified', at: new Date().toISOString()};
          await saveState(state);
        }
        await auction.verify(vehicle, match.lot, existing.item);
        await record({...vehicle, lot: match.lot, item: existing.item, status: 'already-present'});
        continue;
      }
      if (state[vehicle.vin]) {
        throw new Error(`A previous publish attempt for ${vehicle.vin} is recorded, but its lot is missing from the current list. Inspect the auction and reports state file before retrying. No second publish was attempted.`);
      }
      const maximum = Math.max(0, ...listings.map(row => row.item));
      if (nextItem !== undefined && nextItem <= maximum) throw new Error(`Item ${nextItem} would overlap the existing auction (highest item ${maximum}). Use a start item above ${maximum}, or omit --start-item.`);
      nextItem ??= maximum + 1;
      await auction.fill(vehicle, match, nextItem);
      await capture(vehicle, nextItem, 'form');
      if (publish) {
        state[vehicle.vin] = {...vehicle, lot: match.lot, item: nextItem, status: 'pending', at: new Date().toISOString()};
        // Durable checkpoint precedes the single publish click. Never blindly retry it.
        await saveState(state);
        await auction.publish();
        await auction.verify(vehicle, match.lot, nextItem);
        state[vehicle.vin].status = 'verified';
        await saveState(state);
        await capture(vehicle, nextItem, 'verified');
      } else {
        await auction.closeModal();
      }
      await record({...vehicle, lot: match.lot, item: nextItem, status: publish ? 'published' : 'preview'});
      nextItem++;
    } catch (error) {
      await record({...vehicle, status: 'failed', error: error.message});
      throw error;
    }
  }
}
