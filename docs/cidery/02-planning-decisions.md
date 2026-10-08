# Planning decisions (Phase 0)

**Date:** 2026-09-30
**Answers** the open questions in Part 6 of [01-research-manufacturing-systems.md](01-research-manufacturing-systems.md), plus three cider-specific questions the answers raised. Each decision names what it changes in the draft memory model.

## Decisions

| # | Question | Decision | What it changes in the design |
|---|---|---|---|
| 1 | What is a "project order"? | **A production order**: the plan to make a batch (product, recipe version, planned quantity, dates, vessels). | No client-job or client-billing entities. Contract production, if ever needed, becomes a grouping over production orders. |
| 2 | Who is the client? | **Many producers, SaaS Plus+.** Each producer gets a dedicated PostgreSQL database, MaluDB memory, and authenticated MCP endpoints. | Client provisioning and per-client settings are part of the product, not an afterthought. |
| 3 | What size first? | **Nano to small craft.** Taproom and self-distribution, a handful of vessels, one site typical. | Manual vessel assignment with conflict warnings; simple roles; locations support several sites but nothing assumes it. |
| 4 | Several kinds of TTB premises per client? | **Yes.** A client can hold a brewery permit and a bonded winery permit (cider lives under the winery). | *Premises* is an entity with a permit type; every location belongs to one; the report regime is per premises. |
| 5 | Which beverage is the exemplar? | **Cider.** | The first slices run under the bonded-winery regime (27 CFR Part 24, form 5120.17): fruit intake, press runs, juice lots, fermentation, carbonation, and the hard-cider tax class. Beer and wine specifics come later on the same model. |
| 6 | How rigid are the controls? | **Interlocks only where it matters.** Hard stops on using a quarantined lot and on moves that change tax state; everything else warns and logs. | Quarantine status and tax state are enforced in the ledger; overrides elsewhere are activity-log events. |
| 7 | Costing in the first version? | **Actual lot cost for ingredients, standard cost for packaging materials, a flat overhead rate per unit volume.** The recipe's standard cost gives the variance. | Ledger lines carry cost; moving average and full absorption can be added later without changing the ledger. |
| 8 | How far into sales? | **Removals and keg tracking only.** Every departure of finished goods has a destination type; kegs are serialized assets. No sales orders or invoicing. | Customer exists only as a removal destination. |
| 9 | Compliance scope? | **Generate the TTB operations reports with drill-down.** Form 5120.17 per bond first; 5130.9 or 5130.26 when a brewery premises exists; excise numbers alongside. State reports later, as templates over the same data. | Every ledger event and loss carries its report line category and tax class. |
| 10 | Integrations? | **None in the first version.** CSV export everywhere; the ledger is designed so accounting, fermentation sensors, and lab analyzers can attach later. | No external ids or sync state in the first schema beyond what export needs. |
| 11 | How does the cidery get juice? | **Both fruit and purchased juice.** Fruit arrives with weigh tags and is pressed into juice lots; juice can also be received directly as a lot. | Fruit intake is a receipt; press run is a stage event with yield; juice lot is an intermediate item either way. |
| 12 | Cider packaging and carbonation paths? | **Kegs and cans, force-carbonated.** CO₂ is recorded at carbonation. Still cider and bottle-conditioned cider are deferred. | The finished lot carries ABV, CO₂ (g/100 mL), and fruit share so the tax class is a query; a package-level CO₂ reading is supported but not required yet. |

## Revised slice order (cider first)

Replaces section 5.6 of the research document. The brief says "starting with receiving"; the exemplar slice is receiving including fruit intake, once the foundation it needs exists.

1. **Foundation:** client provisioning, premises, locations with bonded or tax-paid flag, items and units, suppliers, vessels, actors and roles.
2. **Receiving (exemplar slice):** purchase orders, receipts, lots, certificate values, quarantine and release, putaway; fruit intake with weigh tags (gross, tare, net, variety, orchard, Brix); purchased juice lots.
3. **Inventory:** the ledger, balances, transfers, adjustments with reasons, counts, FEFO, reorder points, valuation.
4. **Products and recipes:** versions, scaling, stages, expected losses, QC targets, packaging configurations, standard cost. For cider the recipe is mostly a juice blend target, yeast and nutrients, and expected losses.
5. **Production orders** and vessel assignment with conflict warnings.
6. **Batch execution:** press runs (fruit lots in, juice lots out, yield per ton and per bushel), consumption, additions, readings (Brix, pH, TA, free and total SO₂, ABV, temperature), transfers, splits, blends, losses with reasons and report categories, yeast lots with generations.
7. **Packaging:** carbonation with CO₂ reading, packaging runs into kegs and cans, finished lots with tax class, kegs as serialized assets with state and deposit.
8. **Quality:** specs per product per stage, lab tests, sensory records, release decisions with overrides.
9. **Yield and cost reporting:** per-stage yield and loss, variance to recipe, batch cost, cost per keg and per case.
10. **Removals and compliance:** removals by destination type, customers as destinations, form 5120.17 with drill-down, excise numbers.

Later, in no fixed order: a brewery premises with form 5130.9 or 5130.26 and the beer stages; wine specifics (barrels and topping, press fractions, blend composition against label rules); still and bottle-conditioned cider; state reports; accounting and sensor integrations; sales orders and invoicing.

Activity logging is not a slice. It ships with the shell in Phase 2 and every slice adds its own events.

## Assumptions carried forward (raise them if wrong)

- Display units are US customary (gallons, pounds, tons, bushels, barrels) over a metric base (liters, kilograms).
- For cider, tax is determined on removal from bond; a taproom is a tax-paid area, not a designated serving tank.
- Keg deposits are tracked per keg; whether they post to accounting is out of scope until an accounting integration exists.
- State reports are not needed until a client names a state.

## Next step

Phase 0 deliverables for approval: the memory model refined for cider-first, the record and activity question lists mapped to the entities, and the feature list in the slice order above. Those feed Phase 1 (full schema, MCP tool surface, action manifest).
