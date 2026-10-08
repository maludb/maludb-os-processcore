---
name: processcore-receiving-day
description: The runbook for a receiving day at ProcessCore — what is expected, how to bring a delivery in against its purchase order, weigh tags for fruit, quality holds, and the end-of-day check that nothing is left unposted.
kind: runbook
---

# A receiving day

1. **Morning: what is expected.** `receiving_open_orders` with today's date range (and `overdue_only` for what is late).
   Tell receiving what is coming, from whom, how much.
2. **A delivery arrives.** Find the purchase order (`find_po`). `receipt_create` against it: the supplier, the delivery
   note reference, each line's quantity in the purchase unit. Fruit comes with weigh tags: record them line by line.
   A short, over, damaged or substituted line is recorded as it is — never adjusted to match the order.
3. **Lots and quarantine.** Each received line becomes a lot. Items that quarantine by default stay on hold until
   quality releases them (`receiving_lot_status`); do not move a held lot into production.
4. **Post the receipt.** `receipt_post` makes it stock. Then `receiving_receipt_vs_order` to confirm what the order
   still expects.
5. **End of day.** `receiving_open_orders` again for anything still open that was due today; `inventory_movements`
   for today to see every posting; anything created and not posted is reported to receiving by name, not posted by you.
