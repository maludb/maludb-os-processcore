# Research: inventory receiving and manufacturing systems for beer, wine, and cider

**Date:** 2026-09-30
**Status:** research input to Phase 0 planning (memory-first). Nothing here is a decision; Part 6 lists what still has to be decided.
**Scope asked for:** a full inventory management system starting with receiving, with recipe control, yield tracking from manufacturing, project orders, and everything an inventory control system should do, built as an ask-me-anything, memory-first application.

## How to read this

| Part | What it answers | Read it when |
|---|---|---|
| Summary | The findings that change the design | Always |
| Part 1 | What fifteen brewery, winery, and cidery systems actually build, and where their users complain | Deciding what is table stakes and where to beat the market |
| Part 2 | What an inventory control and process-manufacturing system must do, with the decision each concept forces | Designing the memory model and the ledger |
| Part 3 | The domain facts: stages, yield and loss benchmarks, measurements, and US regulatory records for each beverage | Designing stages, losses, quality, and compliance memory |
| Part 4 | The ask-me-anything frame: who asks, what they ask, and what must be remembered | The Phase 0 planning conversation |
| Part 5 | What the research implies we should build differently, and a candidate order for feature slices | Phase 0, after the memory model is agreed |
| Part 6 | Open questions only the owners can answer | Before Phase 1 |

## Summary: the findings that matter most

1. **The table stakes are settled.** Every incumbent does purchase order to receipt with lot capture, scalable recipes, batch-on-vessel tracking, packaging runs with lot codes, forward and backward traceability, TTB reports derived from transactions, batch cost, and accounting sync. These are the entry ticket, not differentiators.

2. **Incumbents are weak in six places.** Loss per stage (only Beer30 treats it as first-class data), tax state on inventory (Ekos pre-fills three of ten parts of the wine report), kegs as serialized assets (only Breww), correcting mistakes (Ekos users: hard to delete, help desk needed), reporting and export, and costing in the wine tools. Users also complain about rigid hard stops and weak mobile apps.

3. **Beer tools are recipe-centric; wine tools are lot-centric and have no recipe at all.** A system that covers all three needs the recipe as an optional plan and the batch graph as the record of truth. Cider sits between them: one cidery tool's rule is that a batch is juice until yeast is pitched.

4. **Two backbones answer most questions.** An immutable inventory ledger, where every movement is an event carrying its TTB category, tax state, actor, and cost, and a batch genealogy graph, where every split and blend carries volumes. Yield, cost, the TTB reports, label composition, and recalls are all derivations of those two.

5. **Yield is a set of per-stage losses, not a number.** Beer loses 10 to 15 % from grain to glass across identifiable stages. Wine yields about 165 to 170 gallons per ton with at least 6 to 7 % post-fermentation loss and 2 to 5 % per year barrel evaporation. Cider yields 2.5 to 3 gallons per bushel. The recipe should carry an expected loss per stage; actuals are loss events with reasons; variance falls out.

6. **TTB reporting is derivable** if every transaction carries its report line category, tax class, and bonded or tax-paid flag. Beer distinguishes a loss (known event) from a shortage (inventory variance, potentially taxable). Wine allows 6 % or 3 % annual inventory loss by tax class. Cider's tax class depends on ABV, carbonation, and fruit share per lot. The wine label rules (75, 85, and 95 % thresholds) require blend composition by volume.

7. **FSMA is light but not zero.** Facility registration and good manufacturing practice apply. Preventive controls do not apply to the alcoholic beverages. The Food Traceability Rule does not cover beer, wine, cider, or their main ingredients, but a producer that receives fresh herbs or fresh-cut fruit may owe receiving records from July 2028.

8. **The ask-me-anything inventory in Part 4** has twelve actors, roughly ninety record questions, ten activity questions, and one draft memory model (a backbone plus six groups). The activity questions ("who released it, who adjusted it, when did planning start") are exactly the ones incumbents answer badly, and the activity memory answers them with no screens at all.

9. **Where memory-first beats the market:** certificate-of-analysis values as structured lot attributes (nobody does it), loss events instead of yield fields, composition on blends, serialized kegs, tax state on locations, TTB category on every transaction, and corrections as compensating entries with an activity trail instead of deletions.

10. **The open questions in Part 6** start with what "project orders" means, who the client is, and whether one client can hold more than one kind of TTB premises.

---

## Part 1: What the market builds

Fifteen products surveyed on 2026-09-30 from vendor documentation, help centers, review sites (Capterra, Software Advice, GetApp), and the ProBrewer forums. Reddit's r/TheBrewery could not be crawled.

### Comparison table

| Product | Segment | Beverages | Core modules | Distinctive modeling choices |
|---|---|---|---|---|
| **Ekos** (Next Glass) | Nano to regional; brewpubs and self-distribution | Beer, wine, cider, seltzer, spirits | Inventory, batches and production planning, recipes, lot tracking, keg tracking, sales/Order Hub, TTB, QuickBooks/Xero sync, 150+ reports | Raw-material lot entered on the "item receipt"; lot picking FIFO/LIFO/FEFO; traceability grouped by packaging run; kegs barcode-scanned per keg with deposits synced to accounting; drag-and-drop batches onto vessels; winery intake tracks vineyard "blocks" and assigns multiple lots from a single intake; the TTB 5120.17 pre-fills only 3 of 10 parts |
| **Ollie Ops / Ollie Order** (Next Glass) | 1 to 1,000 bbl; Ops plan about $201/mo | Beer (marketed also to wine, cider, spirits) | Ops: inventory, batches, brew logs, fermentation logs, yeast generations, tank/barrel overview, packaging, lot codes, cost breakdown, TTB. Order: sales, invoicing, distribution, excise-by-sales | Two separate apps (products set up twice). "Brew log" is the unit of work. Taxable beer is designated either at packaging **or when it enters a designated tank**; entering volume-left-in-tank at packaging auto-computes losses; lot code auto-generated at packaging if blank |
| **Beer30** (5th Ingredient) | Craft, data-driven; batch costing, POs, packaging materials are paid add-ons; NetSuite integration | Beer, kombucha | Scheduling, brew logs, fermentation curves vs a "Gold Standard", tank management, inventory + MRP/POs, batch costing, packaging and keg fleet, QA measurements (gravity, pH, VDK), TTB, sales/CRM, dashboards | **Losses are first-class**, categorized by event (fermentation trub, dry-hop absorption, transfer/filtration, packaging, full-batch QA dumps, serving, returns); start/end volume per stage; losses roll into per-batch liquid COGS; brewhouse, filtration, and packaging yield metrics; flow-meter totalizer vs packaged volume |
| **Breww** | Small to mid (800+ users), strong UK/EU, has US TTB | Beer, cider, spirits ("anything you make is called a beer") | Versioned recipes to live brew sheet, vessel planning, fermentation device feeds, yeast family tree, QA gates, stock items/POs/inventory receipts, lot traceability and recall report, container (keg/cask) tracking, deliveries, batch costing to cost-per-can, multi-country duty | Recipe has "stage types" and "calculated variables"; **batch (gyle) vs turn** (multi-turn batches); vessel capacity includes headspace; vessel groups and types including "yeast brink"; **containers are individually barcoded reusable assets with states** (available/filled/in trade/missing/out of service), gross vs taxable capacity, deposit ledger; a wasted batch keeps its ingredients "used"; batches tied to a duty return cannot be deleted; TTB report shows the transactions behind each line |
| **OrchestratedBEER / OVintner** (on SAP Business One) | $1M to $1B revenue, mid-size and regional; 12 to 20 week implementation | Beer, wine, spirits | Full general-ledger ERP: MRP, purchasing, production orders, brew/cellar/packaging sheets, batch and lot management, inventory in tank, scheduler, TTB with digital signature for counts, keg tracking, COGS costing | **One bill of materials per process stage per brand** (wort through packaging), with "batch production" vs "variance production"; the "brew sheet" lists production orders by date and status; every move posts inventory and GL journals automatically |
| **vintrace** (Encompass) | Boutique to enterprise, custom crush; from $95/mo | Wine (also cider, spirits) | Fruit bookings and intake (intake delivery, external weigh tag), work orders of operations (press cycle, new batch, transfer, additions, tirage), vessels and barrels, lab analysis, bulk wine intake, dry goods and POs, bottling and packaged stock, sales orders, client billing, TTB 5120.17 | **Operation-centric**: operations can sit on a work order or be recorded independently; a press cycle splits a product into multiple fractions; products carry tax state, tax class, and bond; the 5120.17 is per bond with a "tax breakdown report" to see the batches behind each line; losses explained in-app |
| **InnoVint** | Boutique to large groups, custom crush; tiered packages | Wine (cider via the wine model) | Lots, vessels (barrel/tank/bin/keg), work orders of actions and tasks, lab with analyzer integrations, 3D tank maps, dry goods, case goods (bonded vs tax-paid, allocations, depletions), TTB 5120.17, finance add-on for lot-based COGS | **Lot-centric**: the wine lot is the primary object and vessels hold lots; direct actions vs work-order tasks; the 5120.17 is an editable PDF pre-filled with gains and losses by tax class; bulk wines declared by latest alcohol reading; iOS-first |
| **Vinsight** (NZ) | Garage to multinational; Xero shops | Wine, beer, cider, spirits | Operation worksheets, blends and component tracking, fermentation graphs, lab, vineyard diaries, multi-location stock, POs, sales, excise, recall, Xero | Vessel chain of unitanks, brite tanks, barrels, kegs; bonded-location aware; excise focus is AU/NZ, not TTB |
| **Unleashed** | Generic SMB wholesale/manufacturing | Any | POs, receipting, multi-level BOM, assembly/disassembly, batch, serial and expiry (FEFO), landed/average cost, B2B portal, accounting sync | No tank, fermentation, or TTB concept; beer is an "assembly" of a BOM |
| **Katana** | Generic SMB MRP; free tier | Any | Manufacturing orders, BOM/recipes, batch/lot and expiry, moving-average cost, shop-floor app, scheduler | WIP visible by stage; no vessel or TTB concept |
| **Fishbowl** | SMB, QuickBooks-centric | Any food and beverage | Vendor/PO/receive, lot/expiry, multi-level BOM, manufacture order to work orders, MRP, FIFO and landed cost, labor costing, multi-location | Manufacture order generates work orders from the BOM; no excise or fermentation features |
| **BrewPlanner** | Nano to regional; $49 planning / $125 ERP | Beer, wine, cider, spirits | Drag-drop batch scheduling across fermenters, brites, barrels; versioned, scalable recipes and blends; inventory and MRP; QA checkpoints | Scheduling-first; the tank timeline is the core object |
| **BrewMan** (UK) | 300+ breweries and distilleries | Beer, spirits | Recipes, vessel summary screen (volume changes, QC, losses, ingredient usage), raw-material batch traceability, QR container tracking, multi-jurisdiction duty, CRM and routes | The vessel summary is the batch ledger |
| **Brew Ninja** (CA) | Small; from $189/mo by volume | Beer | Batches, raw and finished inventory, lot numbers, COGS from production and POs, keg QR tracking, taproom, Canadian provincial and TTB reports | Waste and discrepancy tracked as an expense |
| **Cidery Manager** (beta 2026) | Craft cideries; Pro $99/mo | Cider | Press logs and juice receipt, fermentation, packaging and bottle fermentation, inventory, costing, TTB (cider) and state excise | "Batches are juice until yeast is pitched"; built for continuous and seasonal cider |
| Also noted | Crafted ERP and VicinityBrew (NetSuite-based enterprise); Enolytics is DTC sales analytics, not production; Vinmetrica is a bench analyzer, not software |

### Common capabilities every system has (the table stakes)

- **Purchasing and receiving**: PO to receipt that increments stock, with the lot number captured on the receipt line. Expiry and FEFO in Ekos, Unleashed, Katana, Fishbowl. None of the systems surveyed documents the certificate of analysis as a structured field; it is handled as notes or attachments at best.
- **Recipe or BOM with scaling**: every brewery tool scales to batch volume; versioning in Breww, BrewPlanner, Orchestrated. Wine tools do not use "recipe" at all: the lot's history is the formula.
- **Batch with vessel occupancy and transfers**, consumption of ingredients, recorded volumes, fermentation readings, and yeast-generation tracking.
- **Packaging run** producing finished SKUs with a lot code; keg tracking by scanned ID with customer linkage.
- **Forward and backward lot traceability with a recall report**.
- **TTB or duty report generated from transactions**, with drill-down to the supporting transactions.
- **Batch cost and COGS** from consumed material cost; **accounting sync** to QuickBooks or Xero rather than an internal general ledger (except the ERP-class products).

### Where systems differ or users complain

- **Loss modeling by stage.** Beer30 is the only brewery product that documents per-event loss categories tied to COGS; Ollie derives loss only from the volume left in tank at packaging; Breww records a "wastage reason" when emptying a vessel. ERP Research argues yield and loss must be first-class data, and that generic ERPs treat loss as scrap against single work orders.
- **Tax determination point.** Ollie lets the brewery choose packaging vs a "designated tank" (brewpub serving tanks); vintrace and InnoVint carry tax class and bond on the product or lot and report gains and losses by tax class; Ekos pre-fills only 3 of 10 parts of the wine report and says there is no quick fix for the rest.
- **Kegs as returnable assets.** Breww alone documents a full state machine, gross vs taxable capacity, deposit ledger, and rental-pool reporting; Ekos tracks keg to customer with deposits; generic ERPs treat kegs as consumable inventory.
- **Hard stops vs flexibility.** ProBrewer users report Ekos would not let them proceed to brew until the PO was received, and that numbers drift so they spent more time keeping the system in check than brewing.
- **Correcting mistakes.** Ekos reviewers: hard to delete things after a mistake; batch-task errors need the help desk. Breww forbids deleting batches already in a duty return.
- **Reporting.** Ekos custom reports time out; InnoVint reporting called very poor, barrel notes not exportable; vintrace exports called unclean.
- **Costing in wine tools.** InnoVint had no integrated costing until a finance add-on; vintrace users say COGS is hard to get accurate.
- **Blends and topping.** InnoVint complicated blends need "added brain power"; vintrace cannot top from multiple vessels at once and dates all analyses in a work order to one day.
- **Two-app split and support.** Ollie Ops and Order require products entered twice; recipes only accept pounds.
- **Pricing and contracts.** Reported Ekos renewal increase to $8,700/yr with a 3-year auto-renew; Orchestrated called far too big for small breweries; Beer30 charges extra for batch costing and POs.
- **Mobile.** Ekos app called buggy and slow; InnoVint lacks Android; BrewPlanner has no app.
- Reddit r/TheBrewery was not crawlable; community evidence is ProBrewer and review sites.

### Vocabulary: the same concept under different names

| Concept | Terms in the wild |
|---|---|
| Unit of production | **batch** (Ekos, Beer30, Ollie, BrewPlanner); **batch = gyle** with **turn** = one brewhouse run inside a batch (Breww); **production order** with a BOM per stage (Orchestrated); **manufacturing order** (Katana); **manufacture order → work orders** (Fishbowl); **assembly** (Unleashed); **wine batch / product** (vintrace); **lot** (InnoVint, Ekos wine); **vintage** is an attribute, not an object |
| Work instructions | **brew sheet** (Breww, OBeer, plus OBeer cellar sheet and packaging sheet); **brew log** (Ollie, Beer30); **work order** of **operations** (vintrace) or **actions/tasks** (InnoVint); **operation worksheet** (Vinsight) |
| Formula | **recipe** with stage types and calculated variables (Breww); **recipe/BOM** (Orchestrated, Katana, Unleashed); wine tools have no recipe, blends are operations on lots |
| Holding equipment | **vessel** (Breww, InnoVint, vintrace, Ekos); **tank/barrel** (Ollie); **inventory in tank** (OBeer); **unitank/brite** (Vinsight) |
| Package | **container** (Breww, BrewMan: keg/cask/can with gross vs taxable capacity); **keg** by keg number (Ekos); **case goods** (InnoVint); **finished goods** (Ekos, Beer30); **product** = sellable item vs **beer** = liquid (Breww) |
| Raw-material lot | **stock item batch** (Breww); **lot** on **item receipt** (Ekos); **lot code** (Ollie); **batch number** (Unleashed) |
| Fruit intake | **intake / block** (Ekos); **intake delivery / fruit booking / external weigh tag / press cycle fractions** (vintrace); **fruit receiving** (InnoVint); **press log / juice receipt** (Cidery Manager) |
| Loss | **wastage reason** (Breww); **beer loss** by event (Beer30); auto **losses** from volume left (Ollie); **gains/losses by tax class** (vintrace, InnoVint); TTB **losses** line |
| Tax state | **tax determined / designated taxable** (Ollie, TTB); **duty / bonded site** (Breww, BrewMan); **bond, tax state, tax class** (vintrace); **bonded vs tax-paid** (InnoVint) |
| Receiving | **item receipt** (Ekos); **inventory receipt** from PO (Breww); **Receive** operation (vintrace); **receipting** (Unleashed) |


---

## Part 2: What an inventory control and manufacturing system must do

A concept reference for process manufacturing as it applies to a beverage producer. Each concept is defined in one or two sentences, followed by the decision a system builder must make about it. The decisions are collected and, where the research supports a choice, resolved in Part 5.

### A. Receiving and procurement

**Purchase order (PO).** The agreed quantity, price, UoM and delivery date for a supplier item; it is the demand signal that drives receiving and the baseline for matching. *Decide:* discrete POs only, or also blanket/standing orders with releases (common for malt and glass).

**Goods receipt note (GRN).** The record that a specific quantity of a PO line physically arrived on a date, at a dock, in a given UoM; it creates on-hand stock and a liability accrual. *Decide:* allow receipts not tied to a PO (samples, free goods) and under what approval.

**Three-way match.** Before paying, the invoice is compared to the PO and the GRN on quantity, price and totals; a two-way match (PO vs invoice) is used for services with no receipt. *Decide:* tolerance rules (percentage and absolute, per supplier) that auto-approve small differences and route the rest to review.

**Supplier lot and internal lot.** The supplier's lot/batch number is kept as an attribute, while the system assigns its own lot ID at receipt so that one supplier lot received twice, or split across locations, stays unambiguous. *Decide:* one internal lot per receipt line (simplest for genealogy) or allow merging identical supplier lots.

**Certificate of analysis (CoA).** A lot-specific document stating test results against specification (hop alpha acid, malt extract and moisture, juice Brix); it is the usual evidence used to release a lot from hold. *Decide:* store the CoA as an attachment only, or parse key values into structured lot attributes so they can drive potency adjustments and specs checks.

**Quarantine / inspection / release status.** A lot carries a status (Quarantine, Pending/Hold, Released, Rework, Reject) that the system enforces as a hard interlock, blocking picking, issue to production and shipment until an authorized role posts a disposition with an audit trail. *Decide:* default status at receipt per item class (packaging may auto-release; ingredients wait for CoA), and who can release.

**Putaway and locations.** After receipt the lot is moved to a storage location (cold room, dry store, hop freezer). *Decide:* directed putaway (system proposes a bin by rules) or free putaway with a confirming scan.

**Partial receipts and backorders.** A PO line can be received in several deliveries; the undelivered remainder is a backorder until received or the line is closed short. *Decide:* whether a short-closed line requires a reason code and whether planning treats open backorders as on-order supply.

**UoM conversion at receipt.** The item master holds a purchase unit (25 kg sack, case of 1,000 crowns) and a conversion factor to the stock unit (kg, each); the receipt is entered in purchase units and stored in stock units, and cost per stock unit is derived from price per purchase unit. *Decide:* fix the conversion on the item or allow it per supplier-item (different sack sizes from different maltsters), and whether to retain the original purchase-unit quantity for matching.

**Landed cost.** Freight, duty, brokerage, insurance and inspection fees added to the purchase price so inventory carries the full cost to the dock, allocated to lines by value, weight, volume or quantity. *Decide:* capitalize an estimate at receipt and true-up when the carrier invoice arrives, or expense inbound freight; and the allocation basis per charge type.

### B. Inventory control fundamentals

**Item master (SKU).** One record per distinct thing you stock, with type (raw, packaging, intermediate, finished, returnable container), base UoM, lot/expiry control flags, shelf-life days, valuation method, and planning parameters. *Decide:* whether a beer in keg, can and case are separate SKUs or one product with pack variants, and whether kegs are tracked as returnable assets with a deposit.

**Units of measure and conversions.** Every quantity is stored in the item's base unit; purchasing, recipes and sales may use alternate units with fixed factors (lb, bbl, hL, case). *Decide:* one base unit per item (mass for solids, volume for liquids) and whether non-fixed conversions are forbidden except for catch-weight items.

**Locations, bins, warehouses.** A hierarchy (site, warehouse, zone, bin) that answers "where is it"; for a brewery or winery, tanks, barrels and fermenters are locations that hold exactly one lot at a time. *Decide:* model vessels as locations with capacity and a single-lot constraint, or as equipment resources linked to lots.

**Lot control and expiry; FIFO vs FEFO.** Lot-controlled items are stocked and moved per lot with a production and expiry date; FIFO picks the oldest receipt first, FEFO picks the soonest-expiring first regardless of arrival. *Decide:* FEFO as the default pick rule for perishable ingredients and finished goods, with FIFO for non-dated items; and whether to allow override with a reason.

**On-hand, available, allocated, on-order.** On-hand is physical stock; allocated is stock committed to orders (soft allocation at item level, hard allocation to a specific lot or bin); available = on-hand minus allocations and holds; on-order is open POs and production orders; available-to-promise = on-hand + scheduled receipts minus commitments. *Decide:* whether reservations are soft or hard, and whether quarantined stock counts as on-hand but not available (it should).

**Reorder points, min-max, safety stock.** Safety stock is a buffer against demand and supply variability; a reorder point triggers replenishment when available stock falls below it; min-max orders up to max when stock drops below min. *Decide:* simple min-max per item/warehouse (usually enough for a producer) versus MRP-driven netting from the production schedule.

**Cycle counting and physical inventory.** Cycle counting counts a rotating subset of items on a schedule, usually weighted by ABC class (value or velocity); physical inventory counts everything, typically with operations stopped. *Decide:* count by location or by item, tolerance before a recount is required, and whether a count variance posts automatically or awaits approval.

**Adjustments and reason codes.** Any non-transactional change to on-hand (count variance, damage, sampling, spillage) is posted as an adjustment with a mandatory reason code, user and timestamp. *Decide:* the reason-code list (it should map to TTB loss categories, see F) and approval thresholds by value.

**Inventory valuation.** Standard cost (preset cost with variances), moving average (recomputed at each receipt), FIFO (cost layers) or specific identification (cost follows the lot). Valuation is usually set per item or item group, e.g. packaging at standard, ingredients at moving average, finished lots at specific identification. *Decide:* method per item class, and recognize that a FEFO physical flow with FIFO cost layers must be documented for auditors.

**Inventory transaction ledger.** Every movement (receipt, issue, transfer, adjustment, production output, shipment) is an immutable, signed-quantity event carrying item, lot, from/to location, status, reason, actor, reference document and idempotency key; on-hand is the sum of the ledger, materialized into a balance table for speed. *Decide:* corrections only by compensating entries, never edits; and whether the balance table is recomputable from the ledger on demand (it should be).

**Negative inventory.** On-hand below zero arises when consumption is recorded before the receipt that supplied it; it corrupts COGS timing, availability and replenishment. *Decide:* block by default, with an explicit per-warehouse or per-item policy (and standard-cost valuation of the shortfall) if transaction sequencing cannot be guaranteed.

### C. Process manufacturing vs discrete manufacturing

**Formula/recipe vs bill of materials.** A BOM lists countable parts assembled into a unit that can be disassembled; a formula lists ingredients by proportion for a bulk product that cannot be taken apart, and is scaled to any batch size. ISA-88 separates the recipe (what to do) from the equipment (how it is done) and defines general, site, master and control recipe levels. *Decide:* express the formula per a nominal batch (e.g., 20 bbl) or per 100 kg/100 L of output, and keep the packaging BOM separate from the liquid formula.

**Batch vs work order.** A batch is the quantity produced from one execution of a recipe and becomes a lot; a work (production) order is the planning document that authorizes making it. *Decide:* one order per brew, or one order per tank fill with multiple brews feeding it.

**Scaling by batch size.** Ingredient quantities scale linearly with target output, but some steps do not (boil-off, hop utilization, dead space). *Decide:* which formula lines scale and which are fixed per batch.

**Yield percentage and loss by step.** Each operation has an expected output ratio (brewhouse extract efficiency, trub and whirlpool loss, fermenter and filtration loss, racking and topping loss in the cellar); the formula carries these so planned input and expected output reconcile. *Decide:* a single overall yield or a yield per routing step (per-step is needed for meaningful variances).

**Co-products and by-products.** Co-products are main outputs made together and share joint cost; by-products are minor incidental outputs (spent grain, pomace, lees, trub, spent yeast) that get no cost allocation and whose proceeds are credited against COGS or other income. *Decide:* list by-products as formula outputs so they get lots and quantities (needed for animal-feed records), and whether to assign them a cost percentage or zero cost.

**Potency / strength adjustment.** The item has a batch attribute (hop alpha acid %, must Brix, base-wine ABV) and the formula specifies the required amount of active ingredient; consumption of that lot is adjusted to hit the target, with compensating and filler ingredients rebalancing the batch. *Decide:* adjust automatically from the lot attribute or just warn, and whether purchase price is also potency-adjusted.

**Shelf life.** Expiry is computed at lot creation as production date plus the item's shelf-life days, or from a "based-on" date, or from the earliest-expiring active component. *Decide:* which method per item, and whether a best-before (AI 15) and a use-by (AI 17) are both stored.

**Catch weight.** An item stocked in one unit (case, bin of grapes) but costed and billed by actual weight recorded at the transaction, because there is no fixed conversion. *Decide:* dual-quantity storage on every ledger line for catch-weight items versus converting to weight at receipt and ignoring the count.

**Variable yields and intermediates.** Wort, must, juice, base wine and bright beer are intermediate items with their own lots, locations (tanks) and WIP cost, so their quantity can differ from plan without breaking the chain. *Decide:* model each stage as a separate item and order, or as one order with multiple operations and in-process lots.

**Blending and splitting.** Blending consumes several lots into a new lot (cost flows by volume contribution); splitting moves part of a lot to another vessel while keeping its identity and genealogy. *Decide:* whether a split creates a child lot or the same lot in two locations, and the volume basis (gallons, liters, proof gallons) for cost allocation.

**Backflush vs explicit issue.** Backflush deducts formula quantities automatically when output is reported; explicit (direct) issue records each lot and quantity as it is consumed. Backflush is cheaper but theoretical and picks lots by rule, so genealogy is only as good as the rule. *Decide:* explicit issue for lot-critical ingredients (malt, hops, fruit, additives) and backflush for low-value consumables (CO2, cleaning chemicals, labels).

**Work-in-process valuation.** Material issued plus labor and overhead charged to an open order sit in WIP until output is received into stock; at order close the WIP is cleared to finished goods and variances. *Decide:* carry WIP per order or per tank, and whether long-aged wine or barrel-aged beer accrues overhead monthly.

### D. Production orders and execution (MES)

**Order lifecycle.** Created → estimated (materials and cost) → scheduled → released (visible to the floor) → started → reported as finished → ended (actual costs replace estimates, WIP reversed, order locked). *Decide:* which transitions are automatic, which need a sign-off, and whether a closed order can be reopened.

**Routing and operations.** The ordered steps (mash, lauter, boil, ferment, condition, filter, package) with resources, durations and expected yields. *Decide:* routing fixed per recipe or editable per order.

**Finite scheduling.** Tanks, brewhouse and packaging line have hard capacities and occupancy durations; scheduling must assign a fermenter for the whole fermentation, not just the brew day. *Decide:* model vessels as finite resources with calendars and clean-in-place turnaround, or schedule manually with conflict warnings.

**Material staging and issue.** Picking the planned lots to the brewhouse (FEFO, released status only) and recording the issue to the order. *Decide:* pick-list driven staging with scan confirmation, or issue at point of use.

**Recording actual consumption and output.** Operators record what lots and quantities really went in and what volume at what gravity came out, per operation. *Decide:* allow substitution of lots and quantities outside the plan with a reason code, and whether output can be recorded before all inputs are issued.

**Scrap and loss.** Losses (dumped batch, spillage, filtration loss, sampling) are recorded against the order with a reason code, so they feed yield variance and TTB loss records. *Decide:* loss types that are "expected" (in the yield) versus "exceptional" (require approval).

**Variances.** Purchase price variance = (actual − standard price) × quantity; material usage variance = (actual − standard quantity) × standard price; yield variance = (actual output − expected output from the input) × standard cost. *Decide:* post variances at order close or at each confirmation, and to which accounts.

**Batch record / electronic batch record (EBR).** The structured, timestamped record of a batch: formula version, each ingredient's lot and quantity, process readings, in-process checks with pass/fail, deviations with disposition, and sign-offs; reviewed before the lot is released. *Decide:* whether EBR review is a gate on changing the output lot from Hold to Released.

**Genealogy.** For every lot, which lots went in (one-up) and which lots and shipments it went into (one-down), built automatically from explicit issues and output receipts. *Decide:* store genealogy as explicit parent-child links (fast queries) rather than reconstructing from ledger joins.

**Mock recall.** A timed drill: given a supplier lot, list every affected finished lot, on-hand quantity and customer shipment; given a finished lot, trace back to supplier lots and CoAs. GFSI schemes commonly expect this within about four hours, tested at least annually. *Decide:* ship a one-click forward/backward trace report with timestamps.

### E. Costing

**Standard vs actual cost per batch.** Standard cost is the planned cost of a batch from the formula; actual cost is the sum of issued material at its valuation, actual labor and absorbed overhead. *Decide:* standard costing with variance reporting, or actual (specific-lot) costing where each batch carries its own cost.

**Cost roll-up.** Computing the standard cost of a finished item by summing component costs through each level (ingredients → wort → beer → packaged case) plus labor and overhead from the routing. *Decide:* roll-up frequency and whether yield losses are built into the standard.

**Absorption of labor and overhead.** Allocating direct labor and manufacturing overhead (utilities, depreciation, rent) to batches via a rate per brew, per hour or per barrel. *Decide:* the driver (hours, volume) and whether aging stock absorbs overhead over time.

**Cost of goods sold.** The cost of the lots actually shipped, recognized at shipment under the item's valuation method, with by-product proceeds credited. *Decide:* by lot, by SKU average or at standard.

**Cost of a keg or case.** Liquid cost per unit volume (from the batch) times fill volume, plus packaging materials, packaging labor and overhead, plus any landed-cost share; wineries typically report cost per gallon, per barrel and per case. *Decide:* whether packaging is a second production order (bulk lot consumed, cases produced) so packaged cost is auditable.

### F. Standards and references

**APICS / ASCM.** The ASCM Supply Chain Dictionary is the reference vocabulary for on-hand, allocated, available-to-promise, safety stock, cycle counting, backflush and MRP terms; use its definitions in the data model.

**ISA-95.** The enterprise–control integration standard: Level 4 is business planning (ERP), Level 3 is manufacturing operations management (MES), Levels 0–2 are process control (PLC, SCADA). Part 1 defines terminology and object models; Parts 2–5 define attributes, Level-3 activities and exchange objects. MES functions include product definition, scheduling, dispatching, execution, data collection, performance analysis and track-and-trace (MESA-11 lists a similar set). *Decide:* which functions the system owns versus leaves to brewhouse automation.

**ISA-88.** The batch control standard: physical model (enterprise, site, area, process cell, unit, equipment module, control module), procedural model (procedure, unit procedure, operation, phase) and four recipe types; its separation of recipe from equipment is the right mental model for formulas.

**GS1.** GTIN-14 (AI 01) identifies a product type; AI 10 lot, AI 11 production date, AI 15 best-before, AI 17 expiry, AI 21 serial, AI 310x net weight, AI 37 count; AI 00 is the SSCC pallet identifier. GS1-128 case labels carrying GTIN + lot + date are what distributors scan at receipt. *Decide:* assign GTINs per SKU and print GS1-128 case and pallet labels from the lot record.

**FSMA.** 21 CFR 117.5(i) exempts alcoholic beverages at TTB-permitted, FDA-registered facilities from Part 117 subparts C (preventive controls) and G (supply-chain program); non-alcoholic foods are permitted only prepackaged and at no more than 5% of sales. FDA facility registration is still required. The FSMA 204 Food Traceability Rule (21 CFR 1.1305 et seq.) applies only to foods on the Food Traceability List; beer, wine, cider, hops, malt and grapes are not on it, and there is no alcohol-specific exemption. A producer that receives an FTL food (fresh herbs, fresh-cut fruit) is covered for that ingredient unless an exemption applies, e.g. the kill-step exemption, which still requires keeping receipt KDEs. The compliance date was extended to July 20, 2028. *Decide:* model Key Data Elements (traceability lot code, dates, locations) on every receipt and transformation anyway, since they are the same data a recall needs.

**TTB.** 27 CFR 25.292 requires brewers to keep daily records of materials received and used, beer produced, transferred to and from bottling and racking, bottled, racked, removed, returned, destroyed and lost, with daily summaries, feeding the Brewer's Report of Operations (Form 5130.9); wineries report on Form 5120.17 with an additions log. *Decide:* tag every ledger event and loss reason with its TTB category so reports are derived, not re-entered.


---

## Part 3: The domain facts

Stages, measurements, yield and loss benchmarks, and US regulatory records for each beverage. Numbers carry their source; where sources disagree or are wrong, the entry is flagged.

### 3.1 Beer

**Stages, what is measured, and where volume is lost**

| Stage | Measured or recorded | Loss point and benchmark |
|---|---|---|
| Milling | Grain weight by malt lot, crush gap, malt lot ids | Negligible |
| Mashing | Strike water volume and temperature, mash temperature 148 to 158 °F, mash pH 5.2 to 5.4, water-to-grist ratio | — |
| Lautering | First-runnings and pre-boil gravity (°P or SG), pre-boil volume | Grain absorption about 0.08 to 0.12 gal per lb of grain (BeerSmith). *Flag:* one planning blog states 0.5 to 1 gal per lb, which is an order of magnitude off; ignore it |
| Boil | Boil length, kettle hop weights, post-boil volume and gravity | Boil-off 4 to 10 % per hour |
| Whirlpool / knockout | Cast-out ("knockout") volume and original gravity, the basis of brewhouse efficiency; wort pH | Kettle trub and hop absorption. Brewhouse loss target 8 to 12 % of pre-boil volume |
| Fermentation | Fill volume, OG, pitch rate 1 to 2 million cells/mL/°P, daily gravity, temperature, pH, cell count and viability, VDK | Trub and yeast sediment 2 to 5 % of fermenter volume |
| Dry hop / post-fermentation adjuncts | Hop or adjunct weight, contact time | 2 % loss at 250 g/hL rising to 14 % at 2,000 g/hL (TNS 2019 trial); rule of thumb about 1 gal per lb of vegetative matter |
| Conditioning / bright tank | Volume, CO₂ volumes, dissolved oxygen, clarity; transfers in and out | Transfer loss 0.5 to 1.5 % per move |
| Filtration / centrifuge | Pre and post volume, haze (NTU) | Usually folded into cellar loss; not separately benchmarked |
| Packaging (keg, can, bottle) | Units filled, fill volume, DO and TPO, CO₂, seam and date-code checks | 1 to 5 % of bright-tank volume; packaging is often about half of total loss |

**Yield metrics**

- *Extract yield*: the lab maximum gravity points per pound per gallon (2-row about 37 PPG).
- *Mash efficiency*: extract actually in the kettle divided by theoretical extract.
- *Brewhouse efficiency* = (cast-out volume × gravity points) ÷ (grain lb × PPG). Commercial target 80 % or better; homebrew 65 to 75 %.
- *Stage losses*: brewhouse = (pre-boil − into fermenter) / pre-boil; fermentation = (into fermenter − into bright) / into fermenter; packaging = (bright − packaged) / bright.
- *Total grain-to-glass loss*: 8 to 15 % of starting volume, with a stated target of 12 to 18 % in the same source. *Flag:* the source contradicts itself; treat 10 to 15 % as a default and make it configurable per recipe.

**Yeast harvest and repitch.** Harvest from a normal fermentation only; bottom-crop after cooling below 40 °F with trub discharged; repitch 5 to 10 generations (Wyeast), many breweries cap at about 8; store at 34 to 36 °F for no more than 2 weeks; pitch about 1 L thick slurry per bbl for ale, 2 L per bbl for lager, 3 L per bbl for high-gravity lager. Record per generation: source batch, generation number, harvest date, cell count, viability, micro result, pitch volume.

**Kegs as returnable assets.** The industry loses 5 to 10 % of its keg fleet per year without tracking and 1 % or less with tracking; deposits run about $30 to 50 against a replacement cost of $100 to 150. Each keg is a serialized asset with a state (empty, filled, at distributor, at retailer, lost), a deposit liability, and a cleaning cycle. TTB tax on keg beer is computed on rated capacity at removal.

### 3.2 Wine

**Stages.** Receive by lot and vineyard block → weigh (tons) → sort → crush and destem → (whites: press → settle → rack off solids) → ferment (reds on skins; press at dryness into free-run and press fractions) → malolactic → rack → barrel or tank aging with topping → fining → filtration → blend → bottle. A TTB "lot" is wine of the same type, or, once bottled, the same wine bottled on the same date (27 CFR 24.10).

**Yield numbers**

| Metric | Value | Source |
|---|---|---|
| Red juice or wine per ton | 165 gal/ton; white and rosé 170 gal/ton (planning figures) | WineMaker |
| General range | 140 to 180 gal/ton | multiple |
| Australian industry means 2007 to 2020 | White 687 L/tonne (651 to 733); red 714 L/tonne (689 to 733); about 700 L/tonne combined, roughly 168 gal per short ton | AWRI |
| Free-run plus light press | 500 to 600 L/tonne; pressing adds 100 to 150 L; over 800 L/tonne possible with hard pressing | AWRI |
| White settling loss | 5 to 10 %; flotation as low as 3 % | AWRI |
| White fermentation lees | 1 to 3 % | AWRI |
| Red gross fermentation lees | 4 to 10 % (the largest red loss) | AWRI |
| Bentonite heat stabilization | about 5 % lees | AWRI |
| Barrel evaporation ("angel's share") | 2 to 5 % per year (AWRI); 3 to 4 % per year (other sources). *Flag:* varies with climate and humidity; make it a per-cellar parameter | AWRI, WineMaker |
| New barrel absorption | 5 to 6 L per new 300 L hogshead (about 2 %) on first fill | AWRI |
| Topping | up to 500 mL every 2 to 4 weeks per barrel; weekly to every 6 weeks depending on humidity | WineMaker |
| Filtration plus packaging | 0.5 to 5 % (larger for small runs); 1 to 3 % typical at bottling | AWRI |
| Post-fermentation combined loss | at least 6 to 7 % (40 to 50 L/tonne) from extracted juice to packaged product | AWRI |
| Finished extraction, small premium winery | 600 to 650 L/tonne (about 144 to 156 gal/ton) | AWRI |

**Measured per lot.** Brix, pH, TA, and YAN at harvest (target YAN 150 to 250 mg N/L for a 21 to 23 °Brix must; pre-fermentation pH under 3.50 so post-malolactic pH stays under 3.65); temperature and Brix daily during fermentation; Brix at or below 0 before pressing; malic and lactic two or more weeks after malolactic inoculation; residual sugar, ABV, VA; free SO₂ within days of each addition, then about every two months during aging and again before bottling. TTB requires the volume produced by fermentation to be determined by actual measurement, and alcohol content determined when the wine leaves the fermenter.

**Blending and label composition rules (27 CFR Part 4)**

| Claim on the label | Minimum composition | Section |
|---|---|---|
| Varietal name | 75 % of that variety, all grown in the labeled appellation (51 % for *Vitis labrusca*, with disclosure) | 4.23 |
| Multiple varieties listed | 100 % from the listed varieties; each percentage shown within 2 % | 4.23 |
| Country, state, or county appellation | 75 %; wine fully finished in that state or an adjacent one | 4.25 |
| Multi-state or multi-county | 100 %, percentages shown within 2 % | 4.25 |
| American Viticultural Area | 85 % | 4.25 |
| Vintage | 95 % if AVA-labeled; 85 % for other appellations | 4.27 |
| Vineyard, orchard, farm, or ranch name | 95 % | 4.39(m) |
| Estate bottled | 100 % from owned or controlled vineyards in the AVA; crushed through bottled continuously on the premises | 4.26 |

Design implication: every blend must carry its composition by variety, vintage, appellation, and vineyard, as volume fractions, so the system can test each label claim. Blending across tax classes must be recorded by volume in and out (24.301; form 5120.17 section A).

### 3.3 Cider

**Stages.** Receive fruit by variety and lot (bins or bushels; a bushel is about 42 to 48 lb) → wash → mill or grind → press (rack-and-cloth, belt, bladder) → juice storage (cold, sulfited, or frozen) → ferment → maturation → rack → blend → back-sweeten (juice or sugar; often requires sterile filtration or sorbate) → carbonate → package.

**Yields**

| Metric | Value | Source |
|---|---|---|
| Juice per bushel | 2.5 gal (Cornell conversion factor) | Cornell CCE |
| Juice per bushel, commercial | 2.5 to 3 gal; 3 to 3.5 gal with efficient presses | MSU Extension |
| Juice per ton | 130 to 185 gal/ton depending on variety and condition | Eve's Cidery |
| Pressing efficiency | about 60 % on a hand or screw press; 13 lb per gal (about 0.64 L/kg) on a bladder or hydro press, up to 20 lb per gal on poor equipment | multiple |
| *Flag* | One extension survey page states 11 to 15 gallons per bushel, which is physically impossible for a 42 to 48 lb bushel; treat it as an error | Penn State |
| Post-press losses | Not separately benchmarked; the wine lees, racking, and filtration figures (1 to 10 %) are the usual proxy | AWRI |

**TTB tax classification.** Cider is wine under 27 CFR Part 24, and a bonded winery is required at 0.5 % ABV or more. The tax class changes both the rate and the records that must be kept.

| Condition | Tax class | Rate per wine gallon |
|---|---|---|
| CO₂ at or below 0.64 g/100 mL, **and** more than 50 % apple or pear juice (reconstituted concentrate counts), **and** no other fruit product or fruit flavoring, **and** 0.5 % to under 8.5 % ABV. Spices, honey, hops, and pumpkin as flavoring are allowed. | Hard cider, 5041(b)(6) | $0.226 (CBMA credits of 6.2¢, 5.6¢, 3.3¢ on the 30k, 100k, 620k gallon tiers) |
| Fails any test, 16 % ABV or less, still | Still wine | $1.07 |
| Fails, artificially carbonated (over 0.392 g/100 mL injected CO₂) | Artificially carbonated wine | $3.30 |
| Fails, naturally sparkling | Sparkling wine | $3.40 |

Sources: 27 CFR 24.331, 24.332, 24.270; TTB cider FAQs. Hard-cider labels must carry "Tax class 5041(b)(6)" (24.257). Records must therefore capture CO₂ in g/100 mL, ABV, and fruit and flavor composition per lot. Labeling: under 7 % ABV falls under FDA food labeling (ingredients, nutrition, allergens) with no COLA, but the health warning still applies; 7 % and over falls under the FAA Act and needs a COLA. A formula is not required for apple-only cider; it is required when flavors or spices (including hops) are added, or when finished wines are blended with excess sugar or water.

### 3.4 US regulatory records

**Forms and thresholds**

| Producer | Form | Frequency rule | Due | Source |
|---|---|---|---|---|
| Brewery | TTB F 5130.9 Brewer's Report of Operations | Monthly if beer excise tax exceeded $50,000 in the prior year or is expected to this year; otherwise quarterly (on 5130.9 or 5130.26) | 15th after the period | 27 CFR 25.297 |
| Brewery | TTB F 5130.26 Quarterly Brewer's Report | Quarterly filers only | Apr 15, Jul 15, Oct 15, Jan 15 | form instructions |
| Brewery | TTB F 5000.24 excise return | Semimonthly by default; quarterly at or below $50k tax; annual at or below $1k | 14 days after the period | 27 CFR 25.164 |
| Winery or cidery | TTB F 5120.17 Report of Wine Premises Operations | Monthly by default; quarterly if a quarterly tax filer with bulk plus bottled wine never over 60,000 gal in a quarter; annual if an annual tax filer with 20,000 gal or less in any month | 15th after the period | 27 CFR 24.300(g) |
| Winery or cidery | TTB F 5000.24 | Semimonthly; quarterly at or below $50k; annual at or below $1k | 14 days | 27 CFR 24.271 |

Units: beer in barrels of 31 gallons to two decimals; wine in wine gallons (records may be kept in liters, converted at 0.26417). Retention: beer three years; wine three years, extendable by three on TTB request.

**Form 5130.9 structure (Part 1, beer summary).** Line 1 on hand; 2 produced; 5 received in bond; 7 and 8 returned; 13 total; 14 removed tax-paid; 15 removed tax-determined to the brewery tavern; 21 consumed on premises (not taxed); 28 destroyed; 30 loss (known event); 31 shortage (found at inventory, potentially taxable, must be explained in Part 3); 33 on hand at end (must equal physical inventory); 35 and 36 prior-period adjustments. Tax = (lines 14 + 15) × rate. Form 5130.26 compresses this. Removals without tax (25.181 to 25.207): transfer to a same-ownership brewery, unfit for beverage use, lab and R&D, to a distilled spirits plant, export, personal use.

**Brewery daily records (27 CFR 25.292 to 25.293).** Each material received and used (with Balling and wort composition); beer produced (including water added after); transfers to and from bottling and racking and quantities packaged; removals for sale (date, consignee, kegs vs bottles); tax-exempt removals; lab samples; beer consumed on premises; returns; reconditioned and destroyed beer; beer received from other breweries; losses (breakage, theft, casualty); measuring-device tests; daily summaries of packaged, removed, returned, and on hand.

**Winery records (27 CFR 24 subpart O).** Section 24.301 requires bulk still wine by tax class: produced by fermentation (actual measurement), received, amelioration, sweetening, spirits addition, blending (volumes of each class in and out), water added, used for formula wine, vinegar, or distilling, refermentation, transaction dates, and explanations of unusual entries. Form 5120.17 Part I section A (bulk) lines: 1 on hand; 2 produced by fermentation (whole container volume including lees); 3 sweetening; 4 wine spirits; 5 blending; 6 amelioration; 7 received in bond; 8 bottled wine dumped to bulk; 9 inventory gain; 13 bottled; 14 removed tax-paid; 15 transfers in bond; 16 and 17 distilling and vinegar; 18 to 22 used for sweetening, spirits, blending, amelioration, effervescent wine; 23 testing; 29 losses other than inventory (casualty, 24.268); 30 inventory losses (topping, racking, evaporation, lees, bottling, booked only at the annual physical inventory); 31 on hand. Section B covers bottled wine: bottled, received, tax-paid returned, removed tax-paid, in bond, dumped, tasting, export, family use, testing, destroyed, breakage, inventory shortage. Part III covers spirits in proof gallons; Part IV covers materials received and used (fruit, juice, concentrate).

**Losses.** Beer distinguishes a *loss* (a known event) from a *shortage* (an inventory variance, potentially taxable); fire, casualty, and theft claims under 25.282 require immediate written notice. Wine allows bulk losses from racking, filtering, and evaporation without a claim up to an annual physical-inventory threshold (24.266(b)): 6 % for still wine and hard cider produced by fermentation and for bottle-fermented sparkling wine; 3 % for wine received in bond, special natural wine, artificially carbonated wine, and bulk-process sparkling wine, computed per tax class on the year's opening stock plus receipts and production. Bottled-wine shortages are presumed to be unreported removals and are taxed (24.266(c)).

**Bonded vs tax-paid.** Beer tax attaches on removal for consumption or sale (25.151); the whole brewery is bonded, and an on-premises tavern receives tax-determined beer. Wine: bonded wine premises hold untaxpaid wine; tax-paid wine premises or a tax-paid bottling house hold tax-paid wine; tax is determined on removal from bond, to 0.1 gallon for bottled wine (24.10, 24.270). Model bonded vs tax-paid as an attribute of every location, and therefore of every inventory record.

**Formulas.** Beer: 27 CFR 25.55 requires a formula (Formulas Online or TTB F 5100.51) for colors, flavors, fruit, spices, honey, non-traditional processes (reverse osmosis, concentration, ice, character-changing filtration), under 51 % malted barley, or 0.0 % ABV; TTB Ruling 2015-1 exempts more than fifty traditional ingredients (honey, chocolate, cherries, oranges, allspice, clove, coffee and so on) in whole, juice, puree, concentrate, or peel form (not extracts, essential oils, or syrups) and aging in used wine or spirits barrels. Wine: 24.80 requires pre-production formula approval for special natural wine, agricultural wine, and other-than-standard wine. *Flag:* the CFR text still cites TTB F 5120.29 while TTB now accepts filings through Formulas Online.

**COLA.** Beer needs a certificate of label approval before bottling only for interstate shipment (27 CFR 7.21); intrastate-only beer needs neither a COLA nor an exemption certificate. Wine and cider at 7 % ABV and over need a COLA (or a certificate of exemption for intrastate sale) under Part 4; under 7 % needs no COLA and follows FDA labeling.

**CBMA reduced rates (permanent since the 2020 Act)**

| Product | Reduced rate or credit | Standard rate |
|---|---|---|
| Beer, brewer producing 2 million bbl or less per year | $3.50/bbl on the first 60,000 bbl | $18/bbl |
| Beer, any brewer | $16/bbl on the first 6 million bbl | $18/bbl |
| Wine | credit of $1.00 on the first 30,000 gal; $0.90 on the next 100,000; $0.535 on the next 620,000 | $1.07 (16 % ABV or less) and up |
| Hard cider | credit of 6.2¢, 5.6¢, 3.3¢ on the same tiers | $0.226 |

Controlled groups and some franchise or contract arrangements are treated as one taxpayer for the tiers.

**State.** Separate state excise returns, production reports, and label registrations exist in nearly every state; thresholds and formats vary. Model these as pluggable report templates over the same ledger.

**FDA and FSMA.** All producers register as food facilities and renew in even years. Under 21 CFR 117.5(i), TTB-permitted registered alcohol facilities are exempt from preventive controls and the supply-chain program (subparts C and G) for alcoholic beverages but remain subject to current good manufacturing practice (subpart B); non-alcoholic food that is not prepackaged, or that exceeds 5 % of sales, is fully covered. The Food Traceability Rule (21 CFR Part 1 subpart S, compliance date 20 July 2028) does not list apples, grapes, hops, malt, or alcoholic beverages, so finished beer, wine, and cider carry no obligations under it. *Flag:* a producer that *receives* a listed food (fresh herbs, fresh-cut fruit, peppers, cucumbers) may owe receiving key data elements unless the kill-step exemption with a written agreement applies; counsel review recommended.

### 3.5 Quality and lab data

**Beer, per batch.** Wort OG or °P, pH, FAN, cast-out volume. Fermentation: daily gravity, temperature, pH, cell count and viability, VDK or diacetyl (threshold about 0.1 ppm; lager spec under 0.05 ppm, ale under 0.10 ppm). Finished: ABV, IBU, color (SRM), haze (NTU), CO₂ at 2.4 to 2.8 volumes, package dissolved oxygen 20 to 50 ppb in bottles and 30 to 60 ppb in cans, total package oxygen target 100 ppb or less. Micro: plating for wild yeast and bacteria from fermenter, bright tank, and package. Packaging: fill volume, seam, date code. Shelf-life pulls at 0 to 5, 30, 60, 90, and 120 days.

**Wine and cider, per lot.** Brix, pH, TA, YAN, optional potassium, malic and lactic, VA, free and total SO₂, residual sugar, ABV, temperature; for cider also CO₂ in g/100 mL and ABV against the 8.5 % limit, since both set the tax class. Every result carries lot, vessel, date, method, and analyst.

**Sensory panel.** Descriptive panels of 8 to 15 trained, screened assessors. Record a blind sample code mapped to batch or lot, panelist id, true-to-brand pass or fail, attribute intensities (hop aroma, malt sweetness, body and so on), fault presence and intensity (beer: diacetyl, acetaldehyde, DMS, oxidation; wine and cider: TCA, Brettanomyces, VA, oxidation, sulfides, smoke taint), free-text comments, and the release decision. Keep training and validation results per panelist.


---

## Part 4: Through the ask-me-anything lens

The three research sections above describe what the market builds and what the domain demands. This section turns that into the planning artifact the memory-first method needs: **who asks, what they ask, and what must be remembered to answer.** Every feature in the final system should trace back to a question here, and every entity in the memory model should be needed by at least one question.

### 4.1 Who asks

| Actor | What they care about | Beverage-type notes |
|---|---|---|
| **Owner / general manager** | Margin, inventory value, what is selling, what is stuck, cash tied up in stock | Same for all three |
| **Head brewer / winemaker / cidermaker** | Recipes, what is in every vessel, yields, what is ready, what is drifting | The winemaker also thinks in vineyard blocks, vintages, and blends |
| **Cellar / production crew** | Today's tasks, transfers, additions, readings, cleaning status | Barrel work (topping, racking) is cellar work in wine |
| **Receiving / warehouse clerk** | What is arriving, receive against the order, where to put it, lot numbers, damaged goods | Grape and apple receiving is seasonal and by weight (weigh tags) |
| **Purchasing / buyer** | What to reorder, lead times, supplier performance, open orders | Hop contracts and grape contracts are multi-year commitments |
| **QA / lab** | Readings per batch, specs, out-of-spec events, release decisions, supplier certificates | SO2 and VA in wine; DO and cell counts in beer |
| **Packaging lead** | What to package, packaging materials on hand, output counts, line losses, keg fleet | Bottling in wine is often a mobile-line event booked in advance |
| **Sales / taproom / distribution** | What is available to sell, allocations, keg returns, what is coming | Taproom removals are tax-determined removals |
| **Accountant / controller** | Cost per batch, cost per keg or case, COGS, inventory valuation, variances | Bonded vs tax-paid inventory matters for excise accrual |
| **Compliance officer** | TTB periodic reports, removals, losses, formula and label approvals, tax class | Brewery, winery, and cidery file different TTB forms |
| **External readers** | Auditor or TTB inspector (read-only records), distributor (keg returns), supplier (COA) | |
| **The client's own AI tools** | Everything above, through the record and activity MCP servers (SaaS Plus+) | |
| **System actors** | Log ingestion into MaluDB, reorder checks, period-end report generation | |

### 4.2 What they ask: record questions (answered from PostgreSQL)

Grouped by the area of the system. Each line is a question in the actor's own words; the bracket names the memory it needs.

**Receiving and purchasing**
- What is arriving this week, and against which purchase order? [purchase order, PO line, expected date]
- Did the delivery match the order? What was short, over, or damaged? [goods receipt vs PO line, discrepancy]
- What lot numbers came in on that delivery, and do we have the certificate of analysis? [receipt line, inventory lot, supplier lot, COA document]
- Is this lot released for use, or still in quarantine? [lot quality status, release decision]
- Which open orders are overdue? [PO, expected date, receipt status]
- What did we pay for malt per pound this year versus last? [receipt line price, item, supplier]
- Which supplier's hops arrive late or short most often? [supplier, PO, receipts]

**Inventory**
- How much of X do we have on hand, by lot and by location? [inventory balance, lot, location]
- How much is actually available after what the next three brews already need? [on-hand, allocations from production orders]
- Which lots should we use first? Which are expiring? [lot received date, expiry, FEFO rule]
- What is below reorder point? [item min/max or reorder point, on-hand, on-order]
- What do the scheduled production orders need that we do not have? [production order, recipe version, on-hand, on-order] (MRP in one question)
- What adjustments were made this month and why? [inventory transaction, reason code]
- When was the hop freezer last counted, and what was the variance? [count, count lines, adjustment]
- What is our inventory worth, by category, as of month end? [inventory transaction ledger, cost layer or standard cost]
- Which items have not moved in six months? [inventory transactions by item]

**Recipes**
- What is the current recipe for product X, and at what batch size? [product, recipe version, recipe lines, stages]
- What changed between version 3 and version 4, and why? [recipe version diff, change note]
- Which batches were made with version 3? [batch → recipe version]
- Can we make X at 20 barrels with what is on hand right now? [recipe scaled to batch size vs available inventory]
- What is the standard cost of a batch of X at this batch size? [recipe lines × item standard cost, plus overhead rule]
- What does X typically yield, from brewhouse to package? [recipe expected yields vs batch actuals]

**Production orders and batches**
- What is in every vessel right now, since when, and what stage is it at? [vessel, batch, occupancy, stage]
- Which batches are in progress and when will each be ready? [batch, stage, planned dates]
- What was brewed, pressed, or crushed this week? [production order, batch, stage events]
- Which production orders are released but have not started? [production order status]
- What was consumed in batch B, by lot? [material consumption, lot]
- What was added after fermentation (dry hops, fining, sulfite, sugar)? [addition events]
- Which batches were blended together, and in what proportion? [blend event, parent batches, volumes]
- What is the full genealogy of what is in tank 7? [batch graph: splits, blends, transfers]
- What is the fermentation curve for batch B? [readings over time]

**Yield and loss**
- What was the yield of batch B at each stage against the recipe's expectation? [stage outputs, expected losses]
- Where did we lose volume on batch B? [loss events by stage with reason]
- What is our brewhouse efficiency for product X over the last ten batches, and is it trending? [batch measurements, recipe expectation]
- How many gallons per ton did we get from the Chardonnay this harvest, by block and press fraction? [grape receipt, press run, fractions]
- How much did we lose to evaporation in barrel this year? [topping events, barrel volumes]
- How much juice per ton did each apple variety give? [fruit receipt, press run]
- What was the packaging loss on the last canning run? [packaging run input vs output]

**Packaging and finished goods**
- How many cases and kegs of X are ready to sell, and how many are allocated? [finished goods lot, balance, allocation]
- What packaging materials do we need for next week's runs, and do we have them? [packaging run plan, packaging BOM, on-hand]
- Which finished-goods lots came from batch B? Which batch is in this can? [packaging run → finished lot → batch]
- Where are our kegs, how many are out, and for how long? [keg asset, keg movement, customer]
- What is the cost of a finished keg or case of X from batch B? [batch actual cost, packaging materials, output count]

**Quality**
- What was the last reading on batch B? Is anything out of spec? [readings, specs per product/stage]
- Which batches are awaiting release? Who released batch B and on what basis? [release decision, readings] (also an activity question)
- What were the free SO2 and VA history of lot W? [lab tests]
- What did the sensory panel say about batch B? [sensory records]

**Costing and finance**
- What did batch B actually cost, and how does that compare to standard? [actual consumption × lot cost, overhead, standard cost]
- What is our COGS this month by product? [removals / sales × finished-lot cost]
- Which products have the best gross margin? [cost per unit, price]
- What is the value of bonded versus tax-paid inventory? [location bonded flag, finished-lot balance, cost]

**Compliance**
- How many barrels did we produce, remove tax-paid, remove in bond, and lose this period? [batch outputs, removals by type, loss events]
- How many gallons of wine are in bulk versus bottled, by tax class? [batch volumes, finished lots, tax class]
- Does this blend still qualify for the vintage, varietal, and appellation on the label? [blend composition percentages, lot attributes]
- Is this cider still inside the hard-cider tax class? [ABV, carbonation, fruit composition]
- Which products need a formula approval or a new label approval? [product, formula/COLA records]
- What did we remove to the taproom last month? [removals by destination]
- Where did the spent grain and pomace go? [co-product output, disposition]

**Traceability and recall**
- Supplier says lot L of malt is contaminated. Which batches used it, and which packaged goods, and who received them? [lot → consumption → batch → packaging → finished lot → removal/customer]
- Customer returns a bad can. Which batch, which lots of ingredients, which other packages share them? [reverse of the above]

### 4.3 What they ask: activity questions (answered from MaluDB logs)

These are never built as screens. The log stream is the feature.

- Who received that delivery, and when did they enter the lot numbers?
- Who changed recipe X from version 3 to version 4, and what did they look at first?
- When did we start planning the Oktoberfest batch? Who created the production order?
- Who adjusted the hop inventory last Tuesday, and what did they do right before that?
- Who released batch B for packaging, and did anyone override an out-of-spec reading?
- Who approved purchase order 123 and how long did it sit before approval?
- When did the cellar crew last open the tank board? Which screens does the night shift actually use?
- Who last counted the cold room? How long did the count take?
- Which recipes has nobody opened in a year?
- What was the sequence of actions on the day batch B lost 40 gallons?

What the log must capture to answer these: timestamp, actor, action, screen/route, affected record ids, before/after values on every change. The stack already requires this from day one.

### 4.4 What must be remembered: the draft memory model

Named in domain language, not SQL. One backbone and six surrounding groups.

**The backbone: the inventory ledger and the batch graph**

- **Inventory transaction** — an append-only event: something moved. Receipt, issue to a batch, transfer between locations, adjustment, count correction, production output, packaging output, removal (sale, taproom, in-bond, export, destruction), return. Every transaction names the item, lot, quantity, unit, from/to location or batch, reason, actor, and cost. Balances are derived, never edited.
- **Batch** — a quantity of product in process, with a number, a recipe version, a product, and a current stage. Batches form a graph: a brew can be split across fermenters, two fermenters can be blended into one bright tank, a press run yields several juice lots, barrels are blended into a bottling lot. Every split and blend is a recorded event with volumes, so genealogy runs forward (what did lot L end up in?) and backward (what is in this can?).

**Group 1 — Things we buy and keep**
- **Item** — anything with a quantity: raw material (malt, hops, yeast, grapes, apples, juice, adjuncts, additives), packaging material (cans, ends, bottles, corks, labels, cartons), intermediate (wort, must, juice, base wine), finished good (keg, case, bottle SKU), co-product (spent grain, pomace, lees), returnable asset (keg). Has a base unit, alternate units with conversions, lot-control flag, shelf-life rule, costing method, category, and reorder rule.
- **Lot** — a received or produced quantity of an item with its own identity: supplier lot number, internal lot, received or produced date, expiry, quality status, and lot attributes (hop alpha acid %, malt moisture, grape variety / vineyard / block / Brix at receipt, apple variety).
- **Location** — site, building, room, bin, cooler, with a bonded or tax-paid flag.
- **Supplier**, **Purchase order** and its lines, **Goods receipt** and its lines, **Certificate of analysis** (document attached to a lot).
- **Count** — a physical or cycle count with lines and resulting adjustments.

**Group 2 — What we know how to make**
- **Product** — a thing we sell or make: brand, style, beverage type (beer / wine / cider), tax class, formula and label approval references, specs.
- **Recipe version** — for a product: target batch size, stages, ingredient lines (item, quantity per batch or per unit volume, stage, timing), expected losses per stage, expected yield, QC targets per stage, change notes. Versions are immutable; batches point at the version they used.
- **Packaging configuration** — how a product becomes finished goods: package SKU, fill volume, packaging bill of materials, expected line loss.

**Group 3 — What we are making now**
- **Production order** — the intent: product, recipe version, planned quantity, planned dates, assigned vessels, status (planned → released → in progress → complete → closed). Allocates materials. (This is the entity we believe the brief calls a *project order* — to confirm.)
- **Vessel** — tank, fermenter, bright tank, barrel, tote, press, with capacity, type, status, and current occupant batch. Barrels also have age, cooperage, fill count.
- **Stage event** — a batch entered or left a stage (mash, boil, ferment, condition, barrel, blend, package), with volume in and out.
- **Consumption**, **Addition**, **Transfer**, **Split**, **Blend**, **Loss** — the batch-side events that pair with inventory transactions.
- **Reading** — a measurement on a batch or vessel at a time: gravity/Plato, Brix, pH, temperature, TA, VA, free/total SO2, alcohol, dissolved oxygen, cell count.
- **Packaging run** — batch in, finished lots out, packaging materials consumed, loss.

**Group 4 — What we judge**
- **Spec** — acceptable ranges per product per stage.
- **Lab test** and **Sensory record** — results against specs.
- **Release decision** — who released a lot or batch, when, on what basis, including overrides.

**Group 5 — What it cost and what we sold**
- **Standard cost** per item (versioned) and **Actual batch cost** roll-up (materials at lot cost, packaging, labor and overhead rule).
- **Customer**, **Sales order / removal** — finished goods leaving: destination type (tax-paid distributor, taproom, in-bond transfer, export, sample, destruction), which drives excise.
- **Keg** (serialized asset) and **Keg movement** — fill, ship, return, clean, lost.
- **Co-product disposition** — spent grain to farmer, pomace to compost, with quantities.

**Group 6 — What the regulator wants**
- **Tax class** per product and per batch where it can change (cider ABV and carbonation; wine alcohol tiers).
- **Period report** — derived, not entered: brewery operations, wine premises operations, cider under either, built from the ledger and removals.
- **Formula approval** and **Label approval** records per product.
- **Loss record** — every loss with stage, quantity, reason, and whether it is reportable.

**Cross-cutting**
- **Actor** — user and role; **Activity log** — the day-one logging stream into MaluDB.
- **Unit of measure** — everything stored in a base unit (liters, kilograms, each) and shown in domain units (barrels, gallons, hectoliters, pounds, tons, cases).

### 4.5 Running the loop

Question → memory gaps found while drafting: the market survey shows most systems treat yield as a single number; the questions above require loss **per stage with a reason**, so the memory model carries a loss event, not a yield field. Wine labeling questions require **composition percentages across blends**, so blend events carry volumes, not just links. Keg questions require kegs as **serialized assets**, not stock counts.

Memory → question check: every entity above traces to at least one question. The two weakest are **Sensory record** (one question) and **Co-product disposition** (one compliance question plus a cost question). Both are cheap to remember; keep them unless the scope conversation cuts them.

---

## Part 5: What the research implies for the design

These resolve the "decide" items from Part 2 where Parts 1, 3, and 4 give a clear answer. Each is a recommendation for the Phase 0 conversation, not a decision.

### 5.1 Structural choices

- **Ledger first.** Every inventory movement is an append-only event with item, lot, quantity in base units, from and to (location or batch), reason code, TTB category, tax state, actor, reference document, and cost. Balances are materialized from the ledger and recomputable from it. Corrections are compensating entries, never edits or deletions. This single choice answers the inventory, valuation, TTB, and "who changed what" questions, and removes the market's most-cited complaint (mistakes that cannot be fixed safely).
- **Batch graph second.** Batches link to parent batches through split and blend events that carry volumes. Vessel occupancy is a separate many-to-many record (batch, vessel, volume, from, to) because a wine lot sits in twenty barrels and a beer batch can be two brewhouse turns into one fermenter. Genealogy is stored as explicit links, not reconstructed from joins.
- **Recipe as plan, batch as record.** The recipe version is immutable and carries stages, ingredient lines, expected loss per stage, and QC targets. A batch always points at the version it used, but a batch can exist with no recipe (a wine lot from a fruit intake). Wine and cider "recipes" are mostly expected-loss and QC templates.
- **Vessels hold batches; they are not locations.** Storage locations hold lots of items. Vessels hold batch volume and have capacity, type, status, and (for barrels) cooperage, age, and fill count.
- **One client, possibly several premises.** A producer can hold a brewery permit and a bonded winery permit (cider lives under the winery). Each premises has its own TTB regime, so premises is an entity, and every location belongs to one.

### 5.2 Receiving and inventory

- **Explicit issue for lot-critical materials, backflush for consumables.** Malt, hops, yeast, fruit, juice, and additives are issued by lot. CO₂, cleaning chemicals, and similar low-value consumables are backflushed from the recipe.
- **FEFO by default** for dated materials and finished goods, FIFO otherwise, with override allowed and the reason logged.
- **Quarantine by item class.** Ingredients default to hold until a certificate of analysis or inspection releases them; packaging materials auto-release. Release is a recorded decision by an authorized role, and it is an activity question as much as a record one.
- **Certificates of analysis as data.** Parse the handful of values that matter (hop alpha acid, malt extract and moisture, juice Brix) into lot attributes so recipes can warn on potency and specs can be checked. Keep the document attached as well. No surveyed product does this.
- **Internal lot per receipt line**, with the supplier lot kept as an attribute. Simplest genealogy; a supplier lot received twice stays unambiguous.
- **Fruit intake is receiving.** A grape or apple delivery is a receipt with a weigh tag (gross, tare, net tons), variety, vineyard and block or orchard, Brix at receipt, and lot. It creates a fruit lot that the first press or crush stage consumes.
- **Base units are metric; display units are the domain's.** Store liters, kilograms, and each; show barrels, gallons, hectoliters, pounds, tons, and cases, with the conversion fixed on the item (and optionally per supplier item for sack sizes). TTB needs barrels to two decimals for beer and wine gallons for wine.
- **Negative inventory is blocked** by default, with a per-location policy for the rare case where sequencing cannot be guaranteed.

### 5.3 Production and yield

- **Production orders carry intent; batches carry fact.** The order holds product, recipe version, planned quantity, dates, assigned vessels, and status (planned, released, in progress, complete, closed). Allocation of materials happens on release. Packaging is a second order type that consumes a batch and produces finished lots, so packaged cost is auditable.
- **Expected vs exceptional loss.** The recipe's expected loss per stage is the yield; a loss event outside it needs a reason and, above a threshold, an approval. Every loss event carries stage, quantity, reason, TTB category (loss vs shortage for beer; inventory vs casualty for wine), and whether it is reportable.
- **Readings are a single entity** with a measurement type, so gravity, Brix, pH, SO₂, dissolved oxygen, and cell counts share one table, one spec mechanism, and one fermentation-curve view.
- **Blend events carry composition.** Volume in from each parent, volume out, and the resulting fractions by variety, vintage, appellation, and vineyard, so the label rules in Part 3 are a query.
- **Tax-determination point is configurable** per premises: at packaging, or on entry to a designated serving tank for a brewpub.
- **Yeast is a lot with generations.** A harvested yeast lot points at its source batch and generation number; pitching it is a consumption.

### 5.4 Costing and finished goods

- **Start with actual lot cost for ingredients and standard cost for packaging materials.** A batch's actual cost is its consumptions at lot cost plus packaging plus an overhead rate per unit volume. The recipe's standard cost gives the variance. Moving-average and full absorption can come later without changing the ledger.
- **Kegs are serialized assets** with a state machine (empty, filled, at distributor, at retailer, lost, out of service), a deposit, and a cleaning cycle. Breww is the only incumbent that documents this; the finance webinar numbers (5 to 10 % fleet loss untracked, 1 % tracked) make it worth the slice.
- **Removals, not sales orders, are the compliance object.** Every departure of finished goods has a destination type (tax-paid, taproom, in bond, export, sample, destruction, return) that maps to a report line. Whether full sales orders and invoicing belong in scope is an open question.

### 5.5 Compliance and quality

- **TTB reports are derived views** over the ledger and loss events: form 5130.9 or 5130.26 for a brewery, form 5120.17 per bond for a winery or cidery. Every line drills down to its transactions, which is what users praise in Breww and vintrace. State reports are templates over the same data.
- **Tax class is an attribute of the batch and of the finished lot** and can change: cider crossing 8.5 % ABV or 0.64 g/100 mL CO₂ leaves the hard-cider class.
- **Specs per product per stage** drive out-of-spec flags; the release decision is recorded with the readings it was based on and any override.

### 5.6 A candidate order for feature slices

For the Phase 0 conversation, not a commitment. The brief says "starting with receiving," which this order honors once the foundation it depends on exists.

1. Foundation: premises, locations, items, units, suppliers, vessels, actors.
2. Purchasing and receiving: purchase orders, receipts, lots, certificates, quarantine and release, putaway, fruit intake with weigh tags.
3. Inventory: ledger, balances, transfers, adjustments with reasons, counts, FEFO, reorder points, valuation.
4. Products and recipes: versions, scaling, stages, expected losses, packaging configurations, standard cost.
5. Production orders and vessel scheduling.
6. Batch execution: consumption, additions, readings, transfers, splits, blends, press runs, losses, yeast lots.
7. Packaging runs, finished goods, kegs.
8. Quality: specs, lab tests, sensory, release decisions.
9. Yield and cost reporting: per-stage yield, variance, batch cost, cost per keg and case.
10. Removals, customers, tax class, TTB reports.

Activity logging is not a slice; it ships with the shell in Phase 2 and every slice adds its own events.

---

## Part 6: Open questions for the owners

> **Answered 2026-09-30.** The decisions, the revised slice order, and the assumptions carried forward are in [02-planning-decisions.md](02-planning-decisions.md). The questions are kept here as the record of what was open.

1. **What is a "project order"?** This document assumes it is a production order (the plan to make a batch). The other reading is a client project: contract brewing or custom crush, where a client's fruit or recipe is produced and billed to them. vintrace and InnoVint both support that model. Which one, or both?
2. **Who is the client?** A single producer running its own operation, or many producers as a SaaS Plus+ product with a dedicated database each? And what size: nano and taproom, regional, or both? This sets how much scheduling, approval, and multi-site capability the first version needs.
3. **Can one client hold more than one kind of premises?** A brewery that also makes cider holds a brewery permit and a winery permit. The draft model allows it; it costs an entity and a regime switch per premises.
4. **How rigid should the controls be?** Users resent hard stops (no brewing until the purchase order is received; no issue from a quarantined lot) but auditors like them. The recommendation is interlocks on quarantine and tax state, warnings elsewhere.
5. **Costing in the first version:** actual lot cost plus standard packaging and a flat overhead rate, as recommended, or full standard costing with variances from day one?
6. **How far into sales?** Removals are required for compliance. Sales orders, invoicing, distributor portals, and route delivery are a separate product in most of the market. In or out?
7. **Compliance scope:** generate the TTB forms, or only the numbers behind them? Excise returns? State reports for which states?
8. **Integrations deferred?** Accounting (QuickBooks, Xero), fermentation sensors (Tilt, Plaato, TankNET), and lab analyzers appear in most incumbents. The recommendation is to design the ledger so they can be added, and to ship none in the first version.
9. **Which beverage first?** The draft model covers all three, but the first exemplar slice has to be one of them. Beer has the most complete recipe-to-package path; wine has the hardest genealogy; cider has the trickiest tax class.

---

## Sources

### Market survey

- Ekos: https://www.goekos.com/ ; https://www.goekos.com/feature/harvest/ ; https://www.goekos.com/feature/keg-tracking_/ ; https://www.goekos.com/feature/lot-tracking_/ ; https://www.goekos.com/blog/compliance-made-easy-simplifying-the-brewers-report-of-operations/ ; https://www.goekos.com/blog/how-to-fill-out-the-report-of-wine-premises-operations/ ; https://www.capterra.com/p/151906/Ekos-Brewmaster/reviews/
- Ollie: https://www.getollie.com/ ; https://getollie.com/brewery-production-software ; https://getollie.com/blog/generate-ttb-reports-in-30-seconds-or-less-with-ollie-ops-and-ollie-order ; https://support.ollieorder.com/hc/en-us/articles/6319905755540-Tax-Determination-Settings-TTB-Reporting ; https://www.capterra.com/p/151911/Ollie/reviews/
- Beer30: https://the5thingredient.com/beer30-software/ ; https://the5thingredient.com/craft-brewery-software/ ; https://the5thingredient.com/how-to-calculate-beer-loss-at-your-brewery/
- Breww: https://www.breww.com/features ; https://breww.com/features/production/ ; https://breww.com/features/container_tracking/ ; https://breww.com/docs/recipes-and-brew-sheets/ ; https://breww.com/docs/brewing-systems-and-vessels/ ; https://breww.com/docs/multi-turn-batches/ ; https://breww.com/docs/ttb-brewers-reports-of-operations/ ; https://breww.com/docs/destroy_-delete-or-waste-a-batch/ ; https://breww.com/docs/breww-glossary-a-guide-to-key-terms-in-breww/
- Orchestrated: https://www.slideshare.net/OrchestratedBEER/orchestratedbeer-product-presentation ; https://support.orchestrated.com/hc/en-us/articles/206419468-Brew-Sheet ; https://sourceforge.net/software/product/OrchestratedBEER/
- vintrace: https://www.encompasstech.com/vintrace/ ; https://www.encompasstech.com/vintrace/wine-production-software ; https://support.vintrace.com/hc/en-us/articles/32301318546964-vintrace-Operations ; https://support.vintrace.com/hc/en-us/articles/32303292459668-TTB-Report-5120-17 ; https://www.capterra.com/p/130918/vintrace/ ; https://www.softwareadvice.com/winery/vintrace-profile/
- InnoVint: https://www.innovint.us/product/ ; https://www.innovint.us/product/wine-production/ ; https://www.innovint.us/product/inventory-tracking/ ; https://www.innovint.us/product/winery-compliance/ ; https://www.innovint.us/packages/ ; https://support.innovint.us/hc/en-us/articles/204848455-using-a-custom-action-or-custom-task ; https://www.capterra.com/p/144038/InnoVint/reviews/ ; https://balanced-business-group.squarespace.com/perspectives/choosing-the-right-winery-management-software-innovint-vs-vintrace
- Vinsight: https://vinsight.net/ ; https://vinsight.net/winery-software/ ; https://vinsight.net/brewery-software/
- Generic MRP: https://www.unleashedsoftware.com/en-us/industry/brewery-software/ ; https://katanamrp.com/industries/brewery-inventory-management-software/ ; https://www.fishbowlinventory.com/en-au/industries/food-and-beverage
- Others: https://www.brewplanner.com/ ; https://www.capterra.com/p/165682/BrewPlanner/reviews/ ; https://www.premiersystems.com/brewman/ ; https://www.brewninja.net/ ; https://www.brewbound.com/pr/2026/03/16/cidery-manager-production-management-software-built-by-cider-consultant ; https://www.erpresearch.com/en-us/brewery-erp ; https://craftederp.com/the-buzz/brewery-ttb-compliance ; https://vicinitybrew.com/compliance-software/
- ProBrewer threads (via search snippets; direct fetch returns 403): https://discussions.probrewer.com/forum/probrewer-message-board/craft-brewing-business/general-r-b-discussions/24093-brewery-management-software ; https://discussions.probrewer.com/forum/probrewer-message-board/general-discussions/general-discussions-sponsored-by-stout-tanks-and-kettles/26532-ekos-brewmaster ; https://discussions.probrewer.com/forum/probrewer-message-board/craft-brewing-business/brewery-accounting-tax-issues-q-a/303671-ekos-software ; https://discussions.probrewer.com/forum/probrewer-message-board/brewery-operations/brewery-controls-automation-q-a-available-for-sponsorship/306781-brewplanner-feedback

### Process manufacturing and inventory control

- https://en.wikipedia.org/wiki/Process_manufacturing
- https://en.wikipedia.org/wiki/ISA-88
- https://en.wikipedia.org/wiki/Manufacturing_execution_system
- https://tulip.co/blog/mes-isa-95-mes-11-cmes-namur/
- https://en.wikipedia.org/wiki/Available-to-promise
- https://www.inventoryops.com/inventoryops-glossary.html
- https://en.wikipedia.org/wiki/First_Expired,_First_Out
- https://tipalti.com/resources/learn/3-way-match/
- https://sgsystemsglobal.com/glossary/quarantine-quality-hold-status/
- https://support.katanamrp.com/en/articles/5945008-purchasing-items-in-different-units-of-measure
- https://invoicedataextraction.com/blog/landed-cost-allocation-manufacturing
- https://www.batchmaster.com/blog/inventory-valuation-process-manufacturing/
- https://docs.infor.com/ln/10.6/en-us/lnolh/help/wh/onlinemanual/000317.html
- https://www.andea.com/resources/blog/component-traceability-and-accuracy-in-different-consumption-modes-part-1/
- https://www.inecta.com/blog/calculate-food-catch-weight
- https://learn.microsoft.com/en-us/previous-versions/dynamicsax-2012/appuser-itpro/about-potency-management
- https://docs.oracle.com/en/applications/jd-edwards/supply-chain-manufacturing/9.2/eoaim/expiration-date-calculation-method.html
- https://docs.oracle.com/en/applications/jd-edwards/supply-chain-manufacturing/9.2/eoapm/understanding-co-products-and-by-products.html
- https://www.accountingtools.com/articles/by-product-costing-and-joint-product-costing
- https://www.accountingtools.com/articles/material-yield-variance
- https://www.hyperbots.com/glossary/cost-rollup
- https://learn.microsoft.com/en-us/dynamics365/supply-chain/production-control/create-production-orders
- https://learn.microsoft.com/en-us/previous-versions/dynamicsax-2012/appuser-itpro/about-production-order-status
- https://www.tryharmony.ai/digital-batch-records-in-food-manufacturing
- https://valdata.com/weblog/food-traceability-playbook-mock-recall/
- https://www.gs1-128.info/application-identifiers/
- https://www.fda.gov/food/food-safety-modernization-act-fsma/fsma-final-rule-requirements-additional-traceability-records-certain-foods
- https://www.fda.gov/food/food-safety-modernization-act-fsma/food-traceability-list
- https://www.law.cornell.edu/cfr/text/21/1.1305
- https://www.law.cornell.edu/cfr/text/21/117.5
- https://bevlaw.com/do-wineries-breweries-distilleries-cideries-meaderies-etc-need-to-be-registered-with-fda-as-a-food-facility/
- https://www.law.cornell.edu/cfr/text/27/25.292

### Domain and compliance

Read in full:
- 27 CFR Part 25 (beer): https://www.law.cornell.edu/cfr/text/27/25.297 ; /25.292 ; /25.282 ; /25.55 ; /25.151 ; /25.164
- 27 CFR Part 24 (wine and cider): https://www.law.cornell.edu/cfr/text/27/24.10 ; /24.80 ; /24.257 ; /24.266 ; /24.270 ; /24.271 ; /24.300 ; /24.301 ; /24.331 ; /24.332
- 27 CFR Part 4 (wine labeling): https://www.law.cornell.edu/cfr/text/27/4.23 ; /4.25 ; /4.26 ; /4.39
- 21 CFR: https://www.law.cornell.edu/cfr/text/21/117.5 ; https://www.law.cornell.edu/cfr/text/21/1.1305
- TTB: https://www.ttb.gov/regulated-commodities/beverage-alcohol/cbma/tax-reform-cbma ; https://www.ttb.gov/cider/cider-faqs/print ; https://www.ttb.gov/system/files/images/pdfs/wine_report_detailed_instructions.pdf ; https://www.reginfo.gov/public/do/DownloadDocument?objectID=55282601 (5130.9 instructions) ; https://www.ttb.gov/media/70359/download?inline= (5130.26 instructions) ; https://www.ttb.gov/regulated-commodities/beverage-alcohol/beer/exempt-ingre ; https://www.ttb.gov/regulated-commodities/formulation/which-alcohol-beverages-require-formula-approval-beer-and-malt-beverages-mbev
- FDA: https://www.fda.gov/food/food-safety-modernization-act-fsma/food-traceability-list ; https://bevlaw.com/do-wineries-breweries-distilleries-cideries-meaderies-etc-need-to-be-registered-with-fda-as-a-food-facility/
- Beer process and yield: https://byo.com/articles/calculating-brewhouse-efficiency/ ; https://byo.com/articles/vetting-your-brew-starting-a-quality-control-program/ ; https://brewplanner.com/blog/track-and-reduce-brewing-losses-from-grain-to-glass ; https://wyeastlab.com/resource/professional-yeast-harvesting-repitching/ ; https://sennos.com/blog/how-much-beer-are-you-losing-to-dry-hopping/ ; https://craftbreweryfinance.com/webinar-managing-your-keg-fleet-hidden-costs-and-opportunities/
- Wine process and yield: https://winemakermag.com/wine-wizard/1732-wine-yields-from-a-vineyard ; https://winemakermag.com/technique/monitoring-your-wine ; https://www.awri.com.au/wp-content/uploads/2021/10/s2259.pdf ; https://extension.oregonstate.edu/catalog/em-9583-preparing-harvest-grape-chemistry-prefermentation-adjustments ; https://www.liquidlux.com.au/blogs/liqlux-academy/why-is-my-barrel-losing-so-much-wine-the-angels-share-explained
- Cider: https://extension.psu.edu/hard-cider-business-benchmark-survey ; https://rvpadmin.cce.cornell.edu/uploads/doc_401.pdf

Used through search snippets only:
- https://www.ecfr.gov/current/title-27/chapter-I/subchapter-A/part-7/subpart-B/section-7.21 ; https://www.ttb.gov/regulated-commodities/beverage-alcohol/wine/7percentorless ; https://www.fda.gov/food/food-safety-modernization-act-fsma/fsma-final-rule-requirements-additional-traceability-records-certain-foods ; https://www.craftbrewingbusiness.com/ingredients-supplies/tobacco-tax-trade-beer-formula-exempt-ingredients/ ; https://www.evescidery.com/pressing-cider-apples/ ; https://www.canr.msu.edu/news/its_cider_time ; https://beersmith.com/blog/2014/11/05/brewhouse-efficiency-vs-mash-efficiency-in-all-grain-beer-brewing/ ; https://www.biorxiv.org/content/10.1101/2020.06.26.166157v1.full ; https://xerafy.com/post/kegs-rentals-efficiency-sustainability/ ; https://winemakermag.com/articles/small-batch-barrels ; https://discussions.probrewer.com/forum/probrewer-message-board/brewery-operations/packaging-q-a/16365-dissolved-oxygen-levels-chart ; https://byo.com/mr-wizard/appropriate-carbonation-levels/ ; https://www.siroccoconsulting.com/consumer-sensory-science-wine-industry/
