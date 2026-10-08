# 14 — Tank view (Inventory)

**Date:** 2026-10-05. **Ask:** under Inventory, a view like the rack board but for tanks that may hold juice, fermenting
cider, base cider or finished product, arranged the way they stand on the floor, showing how much remains in each
(the owner's example: `tank-view.png`).

## What it is
- Screen `tank-view` at `/tanks/` (Inventory → Tank view, beside the rack board). Every active vessel is a card on a
  dotted canvas at its floor position; filters by premises and vessel kind; a button to the list-style Tank board
  (Production) and to Add Vessel.
- A card: the vessel's name (the drag handle), a glass filled to the volume held with the percentage, what it holds
  (the batch's product, or the juice lot's item), the batch or lot number and the batch's stage, litres held of
  capacity, and buttons — Open (the batch or lot), Move (the batch transfer form) for a batch, the vessel's edit form
  otherwise. Cleaning shows a blue glass rim; out of service is dimmed; a vessel never placed has a dashed border and
  sits after the placed ones.
- Colours by what the tank holds: juice (a lot), fermenting (stages pitch, primary), base cider (rack, maturation,
  blend, back-sweeten), finished (carbonate, package).
- Dragging a card's name (production or owner) moves it; on drop the position snaps to the 20 px grid and saves
  (`POST /tanks/{id}/position`, x and y in grid units, logged `tank_position_set`); the canvas grows with the furthest
  card and scrolls sideways on a phone. A failed save marks the card's border red.

## Data
- `db/022_tank_view.sql`: `vessels.board_x`, `vessels.board_y` (grid units, 0–400, NULL = never placed);
  `v_vessel_board` gains `board_x`, `board_y`, `lot_item_name`, `location_id` (appended).
- The records MCP's `production_tank_board` answers `floor_position` per vessel; the kernel's actions server gets
  `tank_position_set` (`/tanks/{vessel}/position`, resolved through `find_vessel`).

## Not done, on purpose
- "Build in place" from the example (start a batch in a tank that holds juice) is `batch_pitch` with the vessel
  pre-chosen; the pitch form does not take a vessel prefill today, so the card does not offer it yet.
- Rotation or sizing of cards by capacity; a per-premises floor image behind the canvas.
