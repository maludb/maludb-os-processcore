---
name: processcore-basics
description: How to read and act in ProcessCore — the record vocabulary (items, lots, batches, vessels, removals), how to resolve what a person means before calling a tool, which tool answers which question, and which actions pause for approval. Use whenever you hold ProcessCore's tools.
---

# ProcessCore basics

## Resolve first
Every entity parameter of an action (`vessel`, `batch`, `lot`, `po`, `receipt`, `supplier`, `product`, `customer`,
`sales_order`, `keg`, `item`, `equipment`, `reservation`, `order` = production order) takes a number (B-26-001, L-261001-004, PO-00001, GR-00001,
WO-00001, SO-00001), a name, or an id. When the person's words are ambiguous ("the tank", "that lot"), call the matching
`find_*` tool with the fragment and offer the candidates; proceed only with one.

## Which tool answers which question
| Question | Tool |
|---|---|
| What is on hand / available after orders / below reorder | `inventory_on_hand`, `inventory_available_after_orders`, `inventory_below_reorder` |
| What is arriving, what is overdue, did the delivery match | `receiving_open_orders`, `receiving_receipt_vs_order`, `receiving_lot_status` |
| What is in the tanks, which batches are in progress, what is short | `production_tank_board`, `production_batches_in_progress`, `production_order_shortages` |
| What is booked on the canning line, when is FV-3 free, what equipment does WO-00012 hold | `equipment_schedule`, `equipment_free` (tanks and presses are vessels; mills, pumps, filters and lines are equipment) |
| A batch's readings, losses, genealogy | `batch_readings`, `batch_losses`, `batch_genealogy` |
| What is ready to release, what is out of spec | `quality_release_queue`, `quality_out_of_spec` |
| What the TTB report says for a period | `compliance_period_summary`, `compliance_report` |
| Where did this lot go / come from (a recall) | `trace_forward`, `trace_backward` |
| What did a batch cost | `cost_batch` |
| What customers ordered and what to make or buy | `orders_find`, `demand_projection`, `production_projection`, `purchase_projection` |
| Who did what, when | `activity_record_history`, `activity_who_did`, `activity_day_replay` |

## Acting
- Readings and additions: `batch_reading_record`, `batch_addition_record`; a stage move: `batch_stage_move`; a loss:
  `batch_loss_record`. A vessel's state: `vessel_set_status` (empty, cleaning, out_of_service).
- Equipment: `equipment_reserve` books a vessel or equipment for a run (order, batch, press run, packaging run) or
  blocks it (cleaning, maintenance, hold), whole days or with times; a clash is refused and named — book it shared
  (`share=true`) only when the organization allows double booking and the person said so. `equipment_reservation_cancel`
  asks first. `equipment_create`, `equipment_set_status` (available, cleaning, out_of_service).
- Receiving: `po_create`, `receipt_create`, then `receipt_post`. Stock: `transfer_create` + `transfer_post`,
  `adjustment_post`, `count_start` / `count_line_record` / `count_submit`.
- Kegs: `keg_register`, `keg_event`, `keg_return`. Orders: `order_create`, `order_add_line`, `order_confirm`,
  `order_package`, `order_ship`.
- Posting is final: a posted receipt, transfer, adjustment or removal is corrected by a compensating entry, never edited.
- Deleting a supplier, customer or item class, and finalizing a TTB report, pause for a person's approval.
