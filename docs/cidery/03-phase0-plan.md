# Phase 0 plan: memory model, questions, and build order (cider first)

**Date:** 2026-10-01
**Status:** Phase 0 deliverable for approval. Builds on [01-research-manufacturing-systems.md](01-research-manufacturing-systems.md) (Part 4 draft model and question lists) and [02-planning-decisions.md](02-planning-decisions.md) (the twelve decisions and the cider-first slice order). Nothing in 02 is reopened here; this document refines the model to the decisions and makes it precise enough to hand to Phase 1.
**Workflow:** the `new-app` skill's fixed order. Phase 0 ends when the owner approves sections 2, 3, and 4 below.

## 1. Where the project stands

| Phase | Deliverable | State |
|---|---|---|
| 0 Planning | Memory model, question list, feature order | Research and decisions done; **this document closes it** |
| 1 Database and memory design | Full schema (every slice), activity log, MaluDB ingestion, MCP tool surface, action manifest, one build spec per slice | Done 2026-10-01 (`db/`, docs 04 and 05, `docs/build-specs/`) |
| 2 Auth and shell | Login (password, Google, TOTP), nxl shell, command bar stub, activity logging live | Done 2026-10-01; look and feel approved (`docs/06-phase2-shell.md`) |
| 3 Vertical slices | Ten slices in the order in section 4; receiving is the exemplar | Built 2026-10-01 (`docs/08-phase3-progress.md`) |
| 4 MCP servers and assistant | Records MCP, activity MCP, actions MCP, unified Agent SDK assistant, client token screen | Built 2026-10-01; live model tests wait for an API key (`docs/10-phase4-progress.md`) |
| 5 Customer orders and planning | Orders, packaging and shipping from orders, imports, standing orders, forecasts, projections, order history, assistant tools | Built 2026-10-02 (`docs/11` plan, `docs/12` design, `docs/13` progress) |

Host check (2026-10-01): PostgreSQL 17.10 with `maludb_core` 0.104.0 and `vector` 0.8.5 available, PHP 8.3.6 with `pdo_pgsql`, Apache 2.4.58 (only the default site), Python 3.12 with `psycopg2` only. Phase 4 needs `mcp` (FastMCP) and `claude-agent-sdk` installed into a venv; nothing else is missing. The repo holds `docs/` and a placeholder `html/index.php`.

## 2. The memory model, refined for cider first

Named in domain language. Every entity traces to at least one question in section 3; the slice column says when it first gets screens. Entities needed only by beer or wine are listed in 2.10 so Phase 1 can leave room for them without building them.

### 2.1 The backbone

**Inventory transaction** (the ledger). An append-only event: something moved. Remembers the item, lot, signed quantity in the item's base unit, where from and where to (a location, a batch, a press run, a packaging run, or an outside party), the transaction type (receipt, issue, transfer, adjustment, count correction, production output, packaging output, removal, return, destruction), the reason code, the premises, the tax state of the stock after the move (bonded or tax paid), the TTB report line it feeds, the cost per base unit, the actor, the reference document, when it happened and when it was posted, an idempotency key, and, for corrections, the transaction it reverses. **Balances are derived from the ledger and never edited; corrections are compensating entries.** Hard interlocks live here: no issue from a quarantined lot, no move that changes tax state without a removal or return record. Everything else warns and logs.

**Batch.** A quantity of cider in process. Remembers its number, product, recipe version (optional), premises, the production order that intended it (optional), when it started, its current stage and status, its current tax class (derived from readings and composition, overridable with a reason), and its lineage. **A batch begins when yeast is pitched.** Before that, juice is a lot of an intermediate item sitting in a vessel. Splits and blends are recorded events carrying volumes, so genealogy runs forward and backward and composition (fruit share, parent batches) is a query.

### 2.2 Group 0: who we are (SaaS Plus+ and the premises)

| Entity | What it remembers | Slice |
|---|---|---|
| **Client** | The producer: name, subdomain, database name, status, display preferences (units, time zone). Lives in a small operator registry outside any client database; everything below lives inside the client's own database. | 1 |
| **Premises** | A TTB permit held by the client: name, kind (bonded winery now; brewery later), registry number, report form and filing frequency, tax determination point, CBMA tier. Every location, vessel, batch, and transaction belongs to one premises. | 1 |
| **Actor** | A user: name, email, role, password or Google identity, TOTP enrollment, recovery codes, status. Roles: owner, production, receiving, quality, compliance, viewer (read only, for auditors). | 1 (auth in Phase 2) |
| **Location** | Where stock sits: premises, name, kind (dry store, cold room, freezer, cellar, packaged goods, taproom, outside), tax state (bonded or tax paid), negative-inventory policy, active flag. Vessels are not locations. | 1 |
| **Unit of measure** | Base units (liter, kilogram, each) and display units (gallon, barrel, pound, ton, bushel, case) with fixed factors; per-item alternates (25 kg sack, 42 lb bushel) and per-supplier purchase units. | 1 |

### 2.3 Group 1: things we buy and keep

| Entity | What it remembers | Slice |
|---|---|---|
| **Item** | Anything with a quantity: code, name, class (fruit, juice, yeast, additive, packaging, consumable, intermediate, finished good, co-product, returnable asset), base unit, lot-controlled flag, catch-weight flag, shelf-life days, default status at receipt (quarantine or released), consumption mode (explicit lot or backflush), costing method (actual lot or standard), reorder point and min/max, TTB material category for Part IV. | 1 |
| **Supplier** and **supplier item** | Who sells it and in what purchase unit, conversion, last price, lead time. | 1 |
| **Purchase order** and **PO line** | Intent to buy: supplier, status (open, partial, closed, closed short with reason), lines with item, quantity in purchase unit, price, expected date. | 2 |
| **Goods receipt** and **receipt line** | What arrived: date, supplier, PO (optional, unplanned receipts allowed), lines with quantity in purchase and base units, unit cost, discrepancy (short, over, damaged, note), and the lot each line created. | 2 |
| **Weigh tag** | A fruit receipt line's weights: gross, tare, net, bin count, variety, orchard and block, Brix at receipt, condition notes. Creates a fruit lot. | 2 |
| **Lot** | One internal lot per receipt line or production output: item, lot number, supplier lot, received or produced date, expiry, quality status (quarantine, hold, released, rejected), cost per base unit, source (receipt line, press run, batch, packaging run), and typed attributes (variety, orchard, Brix, pH, TA, free and total SO2, yeast strain and generation, ABV, CO2, fruit share). | 2 |
| **Certificate of analysis** | A document attached to a lot plus the parsed values copied into lot attributes. | 2 |
| **Release decision** | Who moved a lot or batch between quality statuses, when, on what basis (readings, CoA, inspection), and whether a spec was overridden. | 2 (lots), 8 (batches) |
| **Count** and **count line** | A cycle or physical count: scope (location or items), expected vs counted per lot, variance, approval, and the adjustments it posted. | 3 |
| **Inventory balance** | Materialized from the ledger per item, lot, and location: on hand, allocated, available. Recomputable on demand. | 3 |
| **Allocation** | A production order's claim on an item (soft) or a lot (hard). | 5 |
| **Reason code** | For adjustments, losses, and overrides: code, where it applies, TTB loss category, whether it needs approval above a threshold. | 3 |

### 2.4 Group 2: what we know how to make

| Entity | What it remembers | Slice |
|---|---|---|
| **Product** | A cider we make: name, style, beverage type, intended tax class, target ABV, target fruit share, formula approval and label approval references, status. | 4 |
| **Recipe version** | Immutable once active: product, version, target batch volume, ordered stages (juice blend, pitch, primary, rack, maturation, blend, back-sweeten, carbonate, package) each with expected loss percent and QC targets, ingredient lines (item, quantity per batch or per liter, stage, consumption mode), standard cost snapshot, change note. For cider this is mostly a juice blend target, yeast and nutrients, sulfite, and expected losses. | 4 |
| **Packaging configuration** | How a product becomes a finished good: finished-good item (half-barrel keg, sixth-barrel keg, 16 oz can case), fill volume, packaging bill of materials, expected line loss. | 4 |
| **Spec** | Acceptable range per product per stage per measurement type. | 4 (defined), 8 (enforced) |
| **Standard cost** and **overhead rate** | Versioned cost per item for standard-costed classes; a flat rate per liter per premises. | 4 |

### 2.5 Group 3: what we are making now

| Entity | What it remembers | Slice |
|---|---|---|
| **Vessel** | Tank, fermenter, brite, tote, IBC, barrel: premises, name, kind, capacity, status (empty, in use, cleaning, out of service). | 1 |
| **Vessel occupancy** | Which juice lot or batch is in which vessel, how much, from when to when. Supports a batch across several vessels. | 3 (juice), 6 (batches) |
| **Production order** | Intent: product, recipe version, planned volume, planned pitch and package dates, planned vessels, status (planned, released, in progress, complete, closed), allocations, notes. Vessel conflicts warn, never block. | 5 |
| **Press run** | A standalone execution record: date, press, fruit lots pressed with weights, juice lots produced with volumes and Brix, pomace produced, losses, yield per ton and per bushel, actor. Posts the ledger transactions. | 6 |
| **Stage event** | A batch entered or left a stage: volume in, volume out, timestamps, actor. | 6 |
| **Consumption** | An item lot used by a batch or press run: quantity, stage, purpose (base juice, yeast pitch, nutrient, sulfite, enzyme, sweetener, other), planned vs actual. Additions are consumptions with a purpose. | 6 |
| **Transfer**, **Split**, **Blend** | Batch volume moving between vessels (with loss), one batch becoming several (volumes), several becoming one (volumes in, volume out, composition carried). | 6 |
| **Loss event** | Volume lost: batch or lot, stage, quantity, reason code, TTB category (inventory loss, casualty, testing, destroyed), reportable flag, expected or exceptional, approval. | 6 |
| **Reading** | One measurement on a batch, lot, or vessel: type (Brix, SG, pH, TA, VA, free SO2, total SO2, ABV, temperature, CO2, dissolved oxygen, cell count), value, unit, taken at, method, analyst, spec result. One entity for every measurement type, so fermentation curves and specs share a mechanism. | 6 |
| **Yeast lot** | A lot of a yeast item with strain, generation, source batch, harvest date, viability; pitching is a consumption. | 6 |

### 2.6 Group 4: packaging and finished goods

| Entity | What it remembers | Slice |
|---|---|---|
| **Packaging run** | Batch in, finished lots out: date, packaging configuration, volume in, units out, packaging materials consumed (backflushed from the BOM; explicit for lot-controlled), loss, CO2 reading at carbonation, actor. | 7 |
| **Finished lot** | A lot of a finished-good item with batch, packaged date, ABV, CO2, fruit share, tax class, label approval reference, best-before. Tax class is a query over its attributes, snapshotted at packaging and at each removal. | 7 |
| **Keg** | A serialized returnable asset: serial, size, owner, state (empty, filled, at customer, returned dirty, cleaning, lost, out of service), deposit amount, current contents, current holder, fill count. | 7 |
| **Keg movement** | Fill, ship, return, clean, mark lost, retire: keg, finished lot, customer, actor, time. | 7 |

### 2.7 Group 5: what we judge

| Entity | What it remembers | Slice |
|---|---|---|
| **Lab test** | A reading with a method and a result document; same entity as reading, flagged as lab. | 8 |
| **Sensory record** | Panel date, panelist, blind sample code, batch or lot, pass or fail, attribute intensities, faults, comment. | 8 |
| **Release decision** | Shared with 2.3; for batches it gates packaging. | 8 |

### 2.8 Group 6: what it cost

| Entity | What it remembers | Slice |
|---|---|---|
| **Batch cost** | Derived: consumptions at lot cost, packaging at standard, overhead rate times volume; variance against the recipe standard; cost per liter, per keg, per case. | 9 |
| **Inventory valuation** | Derived: balance times lot cost or standard cost, by item class, location tax state, and date. | 9 |

### 2.9 Group 7: leaving the premises and the regulator

| Entity | What it remembers | Slice |
|---|---|---|
| **Customer** | A removal destination only: name, kind (distributor, retailer, taproom, consumer, other bonded premises), default tax treatment. No orders, no invoices. | 10 |
| **Removal** and **return** | Finished goods leaving: date, finished lots and quantities, kegs included, destination kind (tax-paid sale, taproom transfer, in-bond transfer, export, sample or testing, destroyed, breakage, family use), customer, report line, tax determination (wine gallons, tax class, rate, CBMA credit), actor. A return reverses. | 10 |
| **Co-product disposition** | Pomace leaving: lot, quantity, destination (compost, farm, sale), date. | 6 |
| **Tax class rule** | Versioned parameters of the hard-cider test (CO2 at or below 0.64 g/100 mL, more than 50 percent apple or pear juice, no other fruit or flavoring, 0.5 to under 8.5 percent ABV) and the fallback classes. | 7 |
| **Period report** | Derived, then frozen: premises, form (5120.17 now; 5130.9 or 5130.26 later), period, generated at, lines with values and the transaction set behind each, status (draft, filed), prior-period adjustments. | 10 |
| **Formula approval**, **Label approval** | Per product: number, date, status, document. | 4 |

### 2.10 Cross-cutting

| Entity | What it remembers |
|---|---|
| **Activity log event** | When, who, which client, action name, screen, entity type and id, before and after values, request id, source (screen, command bar, MCP), session. Written by every handler from Phase 2 onward; ingested into MaluDB continuously. |
| **Attachment** | A file on any entity: CoA, weigh ticket photo, COLA, lab report. |
| **MCP access token** | Per client: name, hashed token, scope (records, activity), created, revoked, last used. |

### 2.11 Reserved for later beverages (no screens now, room in the schema)

Barrel attributes and topping events (wine), press fractions and blend composition by variety, vintage, and appellation (wine label rules), brewhouse stages and the beer loss versus shortage distinction, brewery premises with form 5130.9, designated serving tanks, still and bottle-conditioned cider. The reading, loss event, stage, and premises entities are shaped so these are additions, not changes.

## 3. The questions, mapped to memory

### 3.1 Record questions (answered from PostgreSQL through the records MCP server)

Each row is a question in the actor's words, the entities that answer it, and the slice whose screens answer it. Every question becomes a named MCP tool in Phase 1; the slice is where a screen exists for it.

| # | Question | Entities | Slice |
|---|---|---|---|
| R1 | What is arriving this week, and against which purchase order? | Purchase order, PO line | 2 |
| R2 | Did the delivery match the order? What was short, over, or damaged? | Receipt line, PO line | 2 |
| R3 | What lots came in on that delivery, and do we have the certificate? | Receipt line, Lot, Certificate of analysis | 2 |
| R4 | Is this lot released, or still in quarantine? | Lot, Release decision | 2 |
| R5 | Which open orders are overdue? | Purchase order | 2 |
| R6 | What did we pay per pound for apples this season versus last? | Receipt line, Weigh tag, Supplier | 2 |
| R7 | Which supplier delivers late or short most often? | Supplier, PO, Receipt | 2 |
| R8 | How many pounds of each variety came in this harvest, from which orchards, at what Brix? | Weigh tag, Lot | 2 |
| R9 | How much of X is on hand, by lot and location? | Inventory balance | 3 |
| R10 | How much is available after what the next batches need? | Inventory balance, Allocation | 5 |
| R11 | Which lots should we use first? Which are expiring? | Lot, FEFO rule | 3 |
| R12 | What is below reorder point? | Item, Inventory balance, PO line | 3 |
| R13 | What do the scheduled production orders need that we do not have? | Production order, Recipe version, Inventory balance, PO line | 5 |
| R14 | What adjustments were made this month and why? | Inventory transaction, Reason code | 3 |
| R15 | When was the cold room last counted, and what was the variance? | Count, Count line | 3 |
| R16 | What is our inventory worth, by category, as of a date? | Inventory valuation | 9 |
| R17 | Which items have not moved in six months? | Inventory transaction | 3 |
| R18 | What is the current recipe for product X, at what batch size? | Product, Recipe version | 4 |
| R19 | What changed between recipe versions, and why? | Recipe version | 4 |
| R20 | Which batches were made with version N? | Batch | 6 |
| R21 | Can we make X at this volume with what is on hand? | Recipe version, Inventory balance | 5 |
| R22 | What is the standard cost of a batch of X? | Recipe version, Standard cost, Overhead rate | 4 |
| R23 | What is in every vessel right now, since when, at what stage? | Vessel, Vessel occupancy, Batch, Stage event | 6 |
| R24 | Which batches are in progress and when will each be ready? | Batch, Production order | 6 |
| R25 | What was pressed this week, and what did it yield per ton and per bushel? | Press run | 6 |
| R26 | Which production orders are released but not started? | Production order | 5 |
| R27 | What was consumed in batch B, by lot? | Consumption | 6 |
| R28 | What was added after fermentation (sulfite, nutrient, sweetener)? | Consumption (purpose) | 6 |
| R29 | Which batches were blended, in what proportion? | Blend | 6 |
| R30 | What is the full genealogy of what is in tank 7? | Batch graph (split, blend, transfer), Consumption | 6 |
| R31 | What is the fermentation curve for batch B? | Reading | 6 |
| R32 | What was the yield at each stage against the recipe's expectation? | Stage event, Recipe version, Loss event | 9 |
| R33 | Where did we lose volume on batch B, and why? | Loss event | 6 |
| R34 | How much juice per ton did each variety give this season? | Press run, Weigh tag, Lot | 9 |
| R35 | What was the packaging loss on the last canning run? | Packaging run | 7 |
| R36 | How many cases and kegs of X are ready to sell? | Finished lot, Inventory balance | 7 |
| R37 | What packaging materials do next week's runs need, and do we have them? | Production order, Packaging configuration, Inventory balance | 7 |
| R38 | Which finished lots came from batch B? Which batch is in this can? | Packaging run, Finished lot | 7 |
| R39 | Where are our kegs, how many are out, and for how long? | Keg, Keg movement | 7 |
| R40 | What is the cost of a keg or case of X from batch B? | Batch cost | 9 |
| R41 | What was the last reading on batch B? Is anything out of spec? | Reading, Spec | 8 |
| R42 | Which batches await release? Who released B, on what basis? | Release decision, Reading | 8 |
| R43 | What is the SO2 history of lot or batch W? | Reading | 8 |
| R44 | What did the sensory panel say about batch B? | Sensory record | 8 |
| R45 | What did batch B cost against standard? | Batch cost | 9 |
| R46 | What is the value of bonded versus tax-paid inventory? | Inventory valuation, Location | 9 |
| R47 | How many gallons did we produce, remove tax paid, remove in bond, and lose this period? | Period report, Removal, Loss event | 10 |
| R48 | How many gallons are in bulk versus packaged, by tax class? | Batch, Finished lot, Inventory balance | 10 |
| R49 | Is this cider still inside the hard-cider tax class? | Finished lot, Batch, Tax class rule | 7 |
| R50 | Which products need a formula or label approval? | Product, Formula approval, Label approval | 4 |
| R51 | What did we remove to the taproom last month? | Removal | 10 |
| R52 | Where did the pomace go? | Co-product disposition | 6 |
| R53 | Supplier lot L is bad: which batches, which packages, which customers? | Lot, Consumption, Batch, Packaging run, Finished lot, Removal | 10 |
| R54 | A customer returns a bad can: which batch, which ingredient lots, which other packages? | Reverse of R53 | 10 |

Questions kept from the research for later beverages (brewhouse efficiency, barrel evaporation, varietal label qualification, beer loss versus shortage) are not in scope for the cider slices and get no tools until their premises kind exists.

### 3.2 Activity questions (answered from MaluDB through the activity MCP server)

No screens are built for these. The log must capture: timestamp, actor, action, screen, entity type and id, before and after values, source, session, request id.

| # | Question | What the log must hold |
|---|---|---|
| A1 | Who received that delivery, and when did they enter the lot numbers? | receipt_created, receipt_line_added with actor and time |
| A2 | Who changed recipe X to version N, and what did they look at first? | screen entries before recipe_version_created |
| A3 | When did we start planning this batch? Who created the production order? | production_order_created plus the preceding screen trail |
| A4 | Who adjusted inventory last Tuesday, and what did they do right before? | adjustment_posted with before and after, ordered by session |
| A5 | Who released batch B for packaging, and did anyone override an out-of-spec reading? | release_decided with override flag and basis |
| A6 | Who approved purchase order N and how long did it sit? | po_created, po_approved timestamps |
| A7 | When did the cellar crew last open the tank board? Which screens does the night shift use? | screen_entered per actor |
| A8 | Who last counted the cold room, and how long did it take? | count_started, count_line_recorded, count_approved |
| A9 | Which recipes has nobody opened in a year? | screen_entered for recipe-view, by entity id |
| A10 | What happened on the day batch B lost 40 gallons? | every event touching the batch id on that date |
| A11 | What did the assistant do on my behalf yesterday, and was anything undone? | source = command bar, action_undone |
| A12 | Which client AI tools queried our memory this week, and what did they ask? | MCP tool calls logged with token name |

A11 and A12 are new: the command bar and client-facing MCP endpoints are actors too.

### 3.3 Running the loop

Question to memory: R8 and R34 need variety, orchard, and Brix on the weigh tag and the fruit lot, which the draft model held only as free attributes; they are now named weigh tag facts. R49 needs fruit share, which is now a derived batch fact carried through blends. A11 and A12 need source and token name on every log event.

Memory to question: every entity in section 2 answers at least one question. The weakest are sensory record (R44) and co-product disposition (R52), kept as in the research. Allocation (R10, R13) is kept but lands with production orders, not inventory.

## 4. The feature list, in build order

Each slice is a vertical cut: screens, handlers, activity events, manifest entries, and a mobile check. Entities are introduced where their screens are; the schema for all of them is designed in Phase 1.

| # | Slice | Screens (list, form, detail unless noted) | Questions answered | Model class |
|---|---|---|---|---|
| 1 | **Foundation** | Client settings, premises, locations, units, items, suppliers and supplier items, vessels, users and roles, reason codes | none directly; everything else depends on it | Planning |
| 2 | **Receiving (exemplar)** | Purchase orders, goods receipts with lines, weigh tag entry, lot list and detail with status, CoA attach and values, release decision, putaway | R1 to R8 | Planning |
| 3 | **Inventory** | Balances by item, lot, location; transfer; adjustment with reason; counts; FEFO pick suggestion; reorder report; movement history | R9, R11, R12, R14, R15, R17 | Worker |
| 4 | **Products and recipes** | Products, recipe versions with stages and lines, packaging configurations, specs, standard costs, approvals | R18, R19, R22, R50 | Worker |
| 5 | **Production orders** | Orders with vessel assignment and conflict warnings, allocations, material check | R10, R13, R21, R26 | Worker |
| 6 | **Batch execution** | Press runs, pitch (batch start), tank board, stage moves, consumptions and additions, readings and curve, transfers, splits, blends, losses, yeast lots, pomace disposition | R20, R23 to R25, R27 to R31, R33, R52 | Planning (largest slice) |
| 7 | **Packaging** | Carbonation reading, packaging runs, finished lots with tax class, keg register and movements | R35 to R39, R49 | Worker |
| 8 | **Quality** | Spec evaluation on readings, lab tests, sensory records, batch release with override | R41 to R44 | Worker |
| 9 | **Yield and cost reporting** | Per-stage yield and loss, juice yield by variety, batch cost and variance, cost per keg and case, valuation by tax state | R16, R32, R34, R40, R45, R46 | Worker |
| 10 | **Removals and compliance** | Customers, removals and returns, form 5120.17 with drill-down, excise summary, trace forward and backward | R47, R48, R51, R53, R54 | Planning (compliance judgment) |

Cross-cutting from Phase 2, not slices: activity logging, the AMA page, the command bar. Phase 4 adds the three MCP servers, the assistant, and the client token screen.

## 5. What Phase 1 will produce

1. `db/000_roles.sql` (cluster roles), `db/001_extensions.sql` (maludb_core, the `app` and `memory` schemas), `db/002_common.sql` (helpers, document numbering), `db/003_auth.sql` (users, Google identities, TOTP, recovery codes, login throttling, MCP tokens), `db/004_foundation.sql`, `db/005_purchasing_receiving.sql`, `db/006_ledger.sql` (transactions, balances, interlock triggers, transfers, adjustments, counts), `db/007_products_recipes.sql`, `db/008_production.sql`, `db/009_packaging_kegs.sql`, `db/010_quality.sql`, `db/011_removals_compliance.sql`, `db/012_costing_views.sql`, `db/013_activity_log.sql` (the log plus MaluDB ingestion), `db/020_grants.sql` (read-only MCP roles).
2. The operator registry `db/host/000_host.sql` (`cidery_host` database) and `deploy/provision-client.sh`, which creates a client database from the `db/` files; `deploy/cidery-activity-ingest.timer` ships activity rows into MaluDB every minute.
3. `docs/04-mcp-tool-surface.md`: one named tool per question R1 to R54 and A1 to A12, plus `records_search` and `activity_search`.
4. `docs/05-action-manifest.md`: the screen registry (every screen in section 4 with its canonical URL and "when the user wants" line) and the action registry (every create, update, post, release, move, with undo definitions and confirm flags).
5. `docs/build-specs/{slice}.md`: one build spec per slice 3 to 10, per the slice-build-spec template, so worker models make substitutions only.

**Phase 1 checkpoint:** schema, tool surface, and manifest approved before any PHP.

## 6. Refinements made here that need a yes or no at the checkpoint

These are not in 02-planning-decisions.md. Each has a default so Phase 1 can proceed on silence.

1. **Juice is inventory until pitch; a batch starts at pitch.** Juice lots sit in vessels as item lots. Pitching consumes one or more juice lots into a new batch. Default: yes.
2. **A press run is its own execution record**, not a batch stage: fruit lots in, juice lots and pomace out, yield computed. Default: yes.
3. **Six roles:** owner, production, receiving, quality, compliance, viewer. Release decisions need quality or owner; tax-state moves and report filing need compliance or owner. Default: yes.
4. **Tenancy mechanics:** each client is resolved by subdomain to its own PostgreSQL database and MaluDB memory; users and auth live inside the client database; an operator registry database holds only the client list and provisioning state. Client-facing MCP endpoints are `https://{client}.{domain}/mcp/records` and `/mcp/activity`. Default: yes. The domain name is needed before Phase 2.
5. **Numbering:** lots `L-YYMMDD-NNN`, batches `B-YY-NNN`, purchase orders `PO-NNNNN`, receipts `GR-NNNNN`, packaging runs `PK-NNNNN`, removals `RM-NNNNN`; per client, never reused. Default: yes.
6. **Fruit intake units:** weigh tags entered in pounds, stored in kilograms; bushel is an item-level conversion defaulting to 42 lb; juice volumes entered in gallons, stored in liters. Default: yes.
7. **Tax class is computed, not typed.** The finished lot's tax class is derived from ABV, CO2, and fruit share against the versioned rule, with a compliance-role override that logs. Default: yes.
8. **Application name and client-facing domain.** Needed for the shell, email sender, and MCP URLs. No default; the plan uses "cidery" as the working name.
