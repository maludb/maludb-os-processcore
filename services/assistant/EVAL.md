# Assistant evaluation script (spoken style)

**Purpose:** the Phase 4 check from the chat-actions skill: every manifest screen and every manifest action is reachable by a one-sentence utterance, and every one of the 66 questions (R1 to R54, A1 to A12, docs/03 sections 3.1 and 3.2) is answered by the expected MCP tool. Run it once `ANTHROPIC_API_KEY` is set and the records (8701), activity (8702) and actions (8703) servers are up.

```
cd /var/www/services
.venv/bin/python -m assistant.run_eval                    # everything
.venv/bin/python -m assistant.run_eval --only screens     # or actions, questions
.venv/bin/python -m assistant.run_eval --only actions --ids A001-A020 --no-undo
```

Results go to `services/assistant/eval-results/<timestamp>.jsonl` (one line per utterance: reply, tool calls, directives, pass/fail, latency) and a summary table on stdout. A miss is a tool description, manifest, or prompt bug, not an utterance bug: fix the routing knowledge and rerun.

**Writes are real.** Action utterances execute against the dev database as the eval user (default user 5, Ed Honour, owner). After each action that returns an `undo_id`, the runner sends "undo that" in the same session (which also tests the correction verb); pass `--no-undo` to keep the changes. Actions that need confirmation are never confirmed by the runner: getting `needs_confirmation` is the pass.

**Turns go straight to the service** (`POST 127.0.0.1:8765/message`, a fresh session per utterance, a PHP-minted action token per turn). They are therefore not written to the activity log as `assistant_message` rows; the MCP tool calls and the app actions they cause are.

## How rows are scored

| Expect | Pass when |
|---|---|
| `navigate <screen-id>` | the turn returns a navigate directive whose path matches the screen URL (`{id}` matches digits; query strings ignored), or the `navigate` tool was called with that screen |
| `action <manifest action>` | the actions tool that exposes the action in `config/manifest.json` (`exposed_by`) was called and returned success (`undo_id` or refresh) or `needs_confirmation`; for an action with no voice tool yet, the turn navigates to a screen where the action is done (reported as `navigate-fallback`, a soft pass and a gap to close) |
| `confirm <manifest action>` | as `action`, and the result was `needs_confirmation` (nothing executed) |
| `tools <t1>,<t2>` | at least one of the listed tools was called (any server prefix), and on the AMA surface the reply carries a `Source:` line |
| `ask` | no action tool succeeded and the reply is a question (ends with `?`) |

Context is `screen[:entity:record_id]`, sent as the command bar sends it; `-` means the dashboard.

## 1. Screens (command bar, one utterance each)

Login, two-factor challenge and password reset are full-page auth screens, not navigable while signed in, and are not listed.

| Id | Context | Utterance | Expect |
|---|---|---|---|
| S001 | lots-list | take me to the dashboard | navigate dashboard |
| S002 | - | open ask me anything | navigate ama |
| S003 | - | go to my profile | navigate settings-profile |
| S004 | - | um set up two factor authentication | navigate settings-2fa |
| S005 | - | organization settings please | navigate settings-client |
| S006 | - | where do I make an AI access token | navigate settings-mcp-tokens |
| S007 | - | show me the activity log | navigate activity-list |
| S008 | - | go to premises | navigate premises-list |
| S009 | - | add a new premises called hill processcore annex | navigate premises-add |
| S010 | - | edit the hill processcore bonded winery premises | navigate premises-edit |
| S011 | - | show me the locations | navigate locations-list |
| S012 | - | new location called overflow cooler | navigate location-add |
| S013 | - | edit the cold room location | navigate location-edit |
| S014 | - | go to vessels | navigate vessels-list |
| S015 | - | add a new vessel FV three five hundred gallons | navigate vessel-add |
| S016 | - | edit tank three | navigate vessel-edit |
| S017 | - | open items | navigate items-list |
| S018 | - | create a new item called gala apples | navigate item-add |
| S019 | - | edit the EC eleven eighteen yeast item | navigate item-edit |
| S020 | - | show me golden russet apples | navigate item-view |
| S021 | - | what units do we have go to units | navigate units-list |
| S022 | - | suppliers | navigate suppliers-list |
| S023 | - | new supplier called maple ridge orchard | navigate supplier-add |
| S024 | - | edit valley juice co | navigate supplier-edit |
| S025 | - | open the lallemand supplier | navigate supplier-view |
| S026 | - | go to users | navigate users-list |
| S027 | - | invite a new user | navigate user-add |
| S028 | - | edit the cellar hand user | navigate user-edit |
| S029 | - | show reason codes | navigate reason-codes-list |
| S030 | - | add a reason code | navigate reason-code-add |
| S031 | - | edit the LEES reason code | navigate reason-code-edit |
| S032 | - | purchase orders | navigate purchase-orders-list |
| S033 | - | new purchase order for can supply co | navigate purchase-order-add |
| S034 | - | edit PO one | navigate purchase-order-edit |
| S035 | - | open purchase order PO dash zero zero zero zero one | navigate purchase-order-view |
| S036 | - | go to receipts | navigate receipts-list |
| S037 | - | receive a delivery from hill orchard | navigate receipt-add |
| S038 | - | edit receipt GR four | navigate receipt-edit |
| S039 | - | open receipt GR-00001 | navigate receipt-view |
| S040 | dashboard | go to lots | navigate lots-list |
| S041 | - | open lot L 261001 001 | navigate lot-view |
| S042 | - | edit lot L-261001-002 | navigate lot-edit |
| S043 | lot-view:lot:2 | attach a certificate of analysis to this lot | navigate lot-coa-add |
| S044 | lot-view:lot:2 | I want to release this lot | navigate lot-release |
| S045 | receipt-view:receipt:1 | put this receipt away | navigate putaway |
| S046 | - | show me inventory | navigate inventory-materials |
| S047 | - | inventory movements for mcintosh apples | navigate inventory-movements |
| S048 | - | what needs reordering go to reorder | navigate reorder-list |
| S049 | - | stock transfers | navigate transfers-list |
| S050 | - | new transfer from the receiving dock to the cold room | navigate transfer-add |
| S051 | - | open the latest transfer | navigate transfer-view |
| S052 | - | adjustments | navigate adjustments-list |
| S053 | - | new adjustment in the cellar | navigate adjustment-add |
| S054 | - | open adjustment ADJ 00001 | navigate adjustment-view |
| S055 | - | counts | navigate counts-list |
| S056 | - | start a count of the cold room | navigate count-add |
| S057 | - | open count CNT-00001 | navigate count-view |
| S058 | - | products | navigate products-list |
| S059 | - | add a new product called hill semi sweet | navigate product-add |
| S060 | - | edit hill dry cider | navigate product-edit |
| S061 | - | open the hill dry cider product | navigate product-view |
| S062 | product-view:product:1 | new recipe version for this product at five hundred gallons | navigate recipe-add |
| S063 | - | edit the draft recipe for hill dry cider | navigate recipe-edit |
| S064 | - | show me recipe version two of hill dry cider | navigate recipe-view |
| S065 | - | packaging configurations | navigate packaging-configs-list |
| S066 | - | new packaging configuration for hill dry cider cans | navigate packaging-config-add |
| S067 | - | edit the dry half barrel packaging | navigate packaging-config-edit |
| S068 | - | specs for hill dry cider | navigate specs-list |
| S069 | product-view:product:1 | add a spec for pH at fermentation | navigate spec-add |
| S070 | - | edit the first spec on hill dry cider | navigate spec-edit |
| S071 | - | standard costs | navigate standard-costs-list |
| S072 | - | set a standard cost for EC-1118 | navigate standard-cost-add |
| S073 | - | approvals | navigate approvals-list |
| S074 | - | record a label approval for hill dry cider | navigate approval-add |
| S075 | - | edit the hill dry cider formula approval | navigate approval-edit |
| S076 | - | production orders | navigate production-orders-list |
| S077 | - | plan a batch of hill dry cider five hundred gallons | navigate production-order-add |
| S078 | - | edit work order WO-00002 | navigate production-order-edit |
| S079 | - | open WO one | navigate production-order-view |
| S080 | - | show the vessel calendar | navigate production-calendar |
| S081 | - | press runs | navigate press-runs-list |
| S082 | - | record a press run | navigate press-run-add |
| S083 | - | edit press run PR 2 | navigate press-run-edit |
| S084 | - | open press run PR-00001 | navigate press-run-view |
| S085 | - | what's in the tanks show me the tank board | navigate tank-board |
| S086 | - | batches | navigate batches-list |
| S087 | - | pitch a new batch of hill dry cider in FV two | navigate batch-add |
| S088 | - | open batch B 26 001 | navigate batch-view |
| S089 | - | edit batch B-26-004 notes | navigate batch-edit |
| S090 | batch-view:batch:2 | open the reading form for this batch | navigate batch-reading-add |
| S091 | batch-view:batch:2 | I want to add an ingredient to this batch | navigate batch-addition-add |
| S092 | batch-view:batch:2 | go to move stage for this batch | navigate batch-stage-move |
| S093 | batch-view:batch:2 | transfer screen for this batch | navigate batch-transfer |
| S094 | batch-view:batch:2 | split this batch | navigate batch-split |
| S095 | - | blend some batches | navigate batch-blend-add |
| S096 | batch-view:batch:2 | record a loss on this batch | navigate batch-loss-add |
| S097 | batch-view:batch:2 | open the dump screen for this batch | navigate batch-dump |
| S098 | batch-view:batch:2 | harvest yeast from this batch | navigate yeast-harvest-add |
| S099 | - | record where the pomace went | navigate pomace-disposition-add |
| S100 | - | packaging runs | navigate packaging-runs-list |
| S101 | - | package batch B-26-001 in cans | navigate packaging-run-add |
| S102 | - | edit packaging run PK-00004 | navigate packaging-run-edit |
| S103 | - | open PK one | navigate packaging-run-view |
| S104 | - | finished goods | navigate finished-lots-list |
| S105 | - | open finished lot L-261001-009 | navigate finished-lot-view |
| S106 | - | kegs | navigate kegs-list |
| S107 | - | register a new keg | navigate keg-add |
| S108 | - | edit keg KEG-0002 | navigate keg-edit |
| S109 | - | open keg zero zero zero one | navigate keg-view |
| S110 | - | keg returns | navigate keg-return |
| S111 | - | the lab | navigate lab-list |
| S112 | - | new lab reading on B-26-004 | navigate lab-reading-add |
| S113 | - | sensory panel records | navigate sensory-list |
| S114 | - | record a sensory panel for B-26-001 | navigate sensory-add |
| S115 | - | what's waiting for release open the release queue | navigate release-queue |
| S116 | batch-view:batch:2 | release this batch | navigate batch-release |
| S117 | - | yield report | navigate report-yields |
| S118 | - | juice yield by variety for this season | navigate report-juice-yield |
| S119 | - | batch cost report | navigate report-batch-costs |
| S120 | - | inventory valuation as of today | navigate report-valuation |
| S121 | - | customers | navigate customers-list |
| S122 | - | add a customer called the hill taproom | navigate customer-add |
| S123 | - | edit north bonded winery | navigate customer-edit |
| S124 | - | open green mountain distributors | navigate customer-view |
| S125 | - | removals | navigate removals-list |
| S126 | - | new removal to green mountain distributors | navigate removal-add |
| S127 | - | edit removal RM-00005 | navigate removal-edit |
| S128 | - | open removal RM 2 | navigate removal-view |
| S129 | - | record a return from green mountain | navigate return-add |
| S130 | - | TTB reports | navigate ttb-reports-list |
| S131 | - | generate the TTB report for september | navigate ttb-report-add |
| S132 | - | open RPT-00001 | navigate ttb-report-view |
| S133 | - | trace lot L-261001-003 | navigate trace |

## 2. Actions (command bar, one utterance each)

Ids, labels and quantities are from the dev database. The runner resolves each action to its voice tool through `config/manifest.json`.

| Id | Context | Utterance | Expect |
|---|---|---|---|
| A001 | premises-list | add a premises called hill processcore annex a bonded winery registry BWN NY 99999 filing quarterly | action premises_create |
| A002 | - | change the hill processcore bonded winery filing frequency to monthly | action premises_update |
| A003 | locations-list | create a location called overflow cooler in bond at hill processcore bonded winery | action location_create |
| A004 | - | rename the taproom location to taproom bar | action location_update |
| A005 | vessels-list | add a vessel FV three a fermenter five hundred gallons in the cellar | action vessel_create |
| A006 | - | change tote one capacity to two seventy five gallons | action vessel_update |
| A007 | - | mark FV two as cleaning | action vessel_set_status |
| A008 | items-list | new item gala apples fruit in pounds lot controlled | action item_create |
| A009 | - | set the reorder point for fermaid K to ten kilograms | action item_update |
| A010 | item-view:item:5 | add a unit for this item a sachet is half a kilo | action item_unit_add |
| A011 | suppliers-list | add a supplier called maple ridge orchard an orchard | action supplier_create |
| A012 | - | update lallemand's contact to orders at lallemand dot com | action supplier_update |
| A013 | supplier-view:supplier:4 | this supplier sells EC-1118 yeast by the kilo at eighty dollars lead time ten days | action supplier_item_add |
| A014 | users-list | invite sam at example dot com as production named sam | action user_invite |
| A015 | - | make the cellar hand a viewer | confirm user_set_role |
| A016 | - | disable the cellar hand user | confirm user_disable |
| A017 | reason-codes-list | add reason code SPILL named spill for losses | action reason_code_create |
| A018 | - | rename reason code LEES to lees and sediment | action reason_code_update |
| A019 | settings-client | show volumes in liters | action client_settings_update |
| A020 | settings-mcp-tokens | create a records token named claude desktop | action mcp_token_create |
| A021 | settings-mcp-tokens | revoke the claude desktop token | confirm mcp_token_revoke |
| A022 | - | order fifty kilos of potassium metabisulfite from lallemand for next friday | action po_create |
| A023 | purchase-order-view:purchase_order:1 | add ten cases of cans to this order | action po_update |
| A024 | - | approve PO one | action po_approve |
| A025 | purchase-order-view:purchase_order:1 | close this order short the rest isn't coming | confirm po_close_short |
| A026 | - | cancel purchase order PO-00001 | confirm po_cancel |
| A027 | - | received from hill orchard two thousand pounds of golden russet lot HO-26-77 | action receipt_create |
| A028 | receipt-view:receipt:4 | change the supplier lot on this receipt to HO-26-78 | action receipt_update |
| A029 | receipt-view:receipt:4 | add a line five hundred pounds mcintosh supplier lot HO-26-79 | action receipt_line_add |
| A030 | receipt-view:receipt:4 | weigh tag gross twenty four hundred tare four hundred pounds four bins brix twelve point five | action weigh_tag_record |
| A031 | - | post receipt GR-00004 | action receipt_post |
| A032 | receipt-view:receipt:4 | put it all away in the cold room | action putaway_record |
| A033 | lot-view:lot:3 | this lot expires december thirty first | action lot_update |
| A034 | lot-view:lot:3 | set brix on this lot to eleven point eight | action lot_attribute_set |
| A035 | lot-view:lot:3 | record a CoA from lallemand issued today viability ninety five percent | action coa_record |
| A036 | - | put lot L-261001-002 on hold pending CoA | action lot_release |
| A037 | - | move two bags of EC-1118 from the receiving dock to the cold room | action transfer_create |
| A038 | - | post the latest draft transfer | action transfer_post |
| A039 | - | adjust fermaid K in the cold room down half a kilo reason SAMPLE | action adjustment_create |
| A040 | - | approve adjustment ADJ-00003 | action adjustment_approve |
| A041 | - | post adjustment ADJ-00003 | action adjustment_post |
| A042 | - | start a cycle count of the cold room | action count_start |
| A043 | count-view:counts:1 | counted twelve kilos of fermaid K | action count_line_record |
| A044 | count-view:counts:1 | submit this count | action count_submit |
| A045 | - | approve count CNT-00001 | confirm count_approve |
| A046 | - | cancel count CNT-00001 | confirm count_cancel |
| A047 | products-list | add a product hill semi sweet a cider six point five percent | action product_create |
| A048 | - | set hill dry cider target ABV to six point eight | action product_update |
| A049 | - | retire the temp product | confirm product_retire |
| A050 | product-view:product:1 | create a new draft recipe at five hundred gallons copied from the active one | action recipe_create_draft |
| A051 | recipe-view:recipe_version:3 | in this draft change the yeast to two hundred fifty grams | action recipe_update_draft |
| A052 | recipe-view:recipe_version:3 | activate this recipe | action recipe_activate |
| A053 | - | new packaging config hill dry cider twelve ounce can case of twenty four | action packaging_config_create |
| A054 | - | change the dry half barrel expected loss to two percent | action packaging_config_update |
| A055 | product-view:product:1 | add a spec pH between three point two and three point six at fermentation | action spec_create |
| A056 | - | widen the hill dry cider pH spec max to three point seven | action spec_update |
| A057 | - | set the standard cost of EC-1118 to ninety dollars a kilo from today | action standard_cost_set |
| A058 | - | set the overhead rate to one fifty a gallon from october first | action overhead_rate_set |
| A059 | - | record the COLA label approval for hill dry cider number 26-001 approved today | action approval_record |
| A060 | - | mark the hill dry cider formula approval as submitted | action approval_update |
| A061 | - | plan five hundred gallons of hill dry cider pitching october tenth in FV two | action production_order_create |
| A062 | - | move WO-00002 pitch date to october twelfth | action production_order_update |
| A063 | - | release work order WO-00002 | action production_order_release |
| A064 | - | close WO-00001 | action production_order_close |
| A065 | - | cancel WO-00003 | confirm production_order_cancel |
| A066 | - | record a press run today two thousand pounds golden russet into one forty gallons juice in tote one | action press_run_create |
| A067 | - | on PR-00005 pomace was six hundred pounds | action press_run_update |
| A068 | - | post press run PR-00005 | action press_run_post |
| A069 | - | pitch hill dry cider in FV two with one forty gallons of the latest juice and five hundred grams EC-1118 | action batch_pitch |
| A070 | batch-view:batch:2 | uh SG one point zero one two | action batch_reading_record |
| A071 | batch-view:batch:2 | add two hundred grams of fermaid K nutrient | action batch_addition_record |
| A072 | batch-view:batch:2 | move this batch to conditioning one forty gallons out | action batch_stage_move |
| A073 | batch-view:batch:2 | transfer this batch to tank three with two gallons loss | action batch_transfer |
| A074 | batch-view:batch:2 | split this into FV two seventy gallons and tote one seventy gallons | action batch_split |
| A075 | - | blend B-26-001 and B-26-004 fifty fifty into tank three | action batch_blend |
| A076 | batch-view:batch:2 | we lost three gallons racking | action batch_loss_record |
| A077 | batch-view:batch:2 | dump this batch it's infected | confirm batch_dump |
| A078 | batch-view:batch:2 | override the tax class to wine over seven percent because of the chaptalization | confirm batch_tax_class_override |
| A079 | batch-view:batch:2 | note on this batch smells a little reductive | action batch_update |
| A080 | batch-view:batch:2 | harvested two liters of yeast generation three | action yeast_harvest_record |
| A081 | - | six hundred pounds of pomace from PR-00005 went to the farm down the road for feed | action pomace_disposition_record |
| A082 | - | package B-26-001 into cans today one twenty gallons in fifty cases out | action packaging_run_create |
| A083 | - | on PK-00006 units out were forty eight | action packaging_run_update |
| A084 | - | post packaging run PK-00006 | action packaging_run_post |
| A085 | - | override the tax class on finished lot L-261001-009 to still wine | confirm finished_lot_tax_class_override |
| A086 | - | register keg KEG-0101 half barrel ours | action keg_register |
| A087 | - | change KEG-0002 deposit to thirty dollars | action keg_update |
| A088 | - | filled KEG-0001 from L-261001-016 | action keg_fill |
| A089 | - | kegs zero zero zero two and zero zero zero three came back from green mountain | action keg_return |
| A090 | - | KEG-0002 is clean | action keg_clean |
| A091 | - | KEG-0003 is lost | confirm keg_mark_lost |
| A092 | - | we found KEG-0003 | action keg_found |
| A093 | - | retire KEG-0003 | confirm keg_retire |
| A094 | - | lab pH three point four on B-26-004 | action lab_reading_record |
| A095 | - | sensory panel on B-26-001 pass clean apple a bit dry | action sensory_record |
| A096 | - | release B-26-001 for packaging based on today's readings | action batch_release |
| A097 | - | add customer the hill taproom a taproom | action customer_create |
| A098 | - | north bonded winery permit is BWN-NY-12345 | action customer_update |
| A099 | - | ship ten cases of L-261001-009 to green mountain distributors today | action removal_create |
| A100 | - | on RM-00005 make it twelve cases | action removal_update |
| A101 | - | post removal RM-00005 | confirm removal_post |
| A102 | - | reverse removal RM-00002 they never took it | confirm removal_reverse |
| A103 | - | green mountain returned two cases of L-261001-009 | action return_create |
| A104 | - | post the return from green mountain | confirm return_post |
| A105 | - | generate the TTB report for september for hill processcore bonded winery | action ttb_report_generate |
| A106 | - | regenerate RPT-00003 | action ttb_report_regenerate |
| A107 | - | finalize RPT-00003 | confirm ttb_report_finalize |
| A108 | - | mark RPT-00001 filed today | confirm ttb_report_mark_filed |
| A109 | batch-view:batch:2 | record a reading | ask |
| A110 | - | log three gallons | ask |

## 3. Questions (AMA page)

| Id | Context | Utterance | Expect |
|---|---|---|---|
| R1 | ama | what's arriving this week and on which purchase order | tools receiving_open_orders |
| R2 | ama | did GR-00002 match the order anything short over or damaged | tools receiving_receipt_vs_order |
| R3 | ama | what lots came in on GR-00001 and do we have the CoA | tools receiving_receipt_lots |
| R4 | ama | is lot L-261001-002 released or still in quarantine | tools receiving_lot_status |
| R5 | ama | which open orders are overdue | tools receiving_open_orders |
| R6 | ama | what did we pay per pound for apples this season versus last | tools receiving_price_history |
| R7 | ama | which supplier delivers late or short most often | tools receiving_supplier_performance |
| R8 | ama | how many pounds of each variety came in this harvest from which orchards and at what brix | tools receiving_fruit_intake |
| R9 | ama | how much fermaid K do we have by lot and location | tools inventory_on_hand |
| R10 | ama | how much EC-1118 is available after what the next batches need | tools inventory_available_after_orders |
| R11 | ama | which lots of apple juice should we use first and are any expiring | tools inventory_pick_order |
| R12 | ama | what's below reorder point | tools inventory_below_reorder |
| R13 | ama | what do the scheduled production orders need that we don't have | tools production_order_shortages |
| R14 | ama | what adjustments were made this month and why | tools inventory_adjustments,inventory_movements |
| R15 | ama | when was the cold room last counted and what was the variance | tools inventory_last_count |
| R16 | ama | what's our inventory worth by category as of today | tools cost_inventory_valuation |
| R17 | ama | which items haven't moved in six months | tools inventory_slow_movers |
| R18 | ama | what's the current recipe for hill dry cider at five hundred gallons | tools recipe_current |
| R19 | ama | what changed between recipe versions one and two of hill dry cider and why | tools recipe_diff |
| R20 | ama | which batches were made with version one of hill dry cider | tools recipe_batches_made |
| R21 | ama | can we make five hundred gallons of hill dry cider with what's on hand | tools recipe_can_make |
| R22 | ama | what's the standard cost of a batch of hill dry cider | tools recipe_standard_cost |
| R23 | ama | what's in every vessel right now since when and at what stage | tools production_tank_board |
| R24 | ama | which batches are in progress and when will each be ready | tools production_batches_in_progress |
| R25 | ama | what was pressed this week and what did it yield per ton and per bushel | tools production_press_runs |
| R26 | ama | which production orders are released but not started | tools production_orders_by_status |
| R27 | ama | what was consumed in batch B-26-001 by lot | tools batch_consumptions |
| R28 | ama | what was added to B-26-001 after fermentation sulfite nutrient or sweetener | tools batch_consumptions |
| R29 | ama | which batches were blended and in what proportion | tools batch_blends |
| R30 | ama | what's the full genealogy of what's in tank three | tools batch_genealogy |
| R31 | ama | show me the fermentation curve for B-26-004 | tools batch_readings |
| R32 | ama | what was the yield at each stage of B-26-002 against the recipe | tools cost_stage_yields,batch_stage_history |
| R33 | ama | where did we lose volume on B-26-002 and why | tools batch_losses |
| R34 | ama | how much juice per ton did each variety give this season | tools cost_juice_yield_by_variety |
| R35 | ama | what was the packaging loss on the last canning run | tools packaging_run_losses |
| R36 | ama | how many cases and kegs of hill dry cider are ready to sell | tools packaging_finished_stock |
| R37 | ama | what packaging materials do next week's runs need and do we have them | tools packaging_material_needs |
| R38 | ama | which finished lots came from B-26-002 | tools packaging_lots_for_batch |
| R39 | ama | where are our kegs how many are out and for how long | tools keg_fleet,keg_history |
| R40 | ama | what does a keg of hill dry cider from B-26-002 cost | tools cost_batch |
| R41 | ama | what was the last reading on B-26-004 and is anything out of spec | tools batch_readings,quality_out_of_spec |
| R42 | ama | which batches await release and who released B-26-002 on what basis | tools quality_release_queue,quality_release_history |
| R43 | ama | what's the SO2 history of B-26-002 | tools batch_readings |
| R44 | ama | what did the sensory panel say about B-26-002 | tools quality_sensory |
| R45 | ama | what did B-26-002 cost against standard | tools cost_batch |
| R46 | ama | what's the value of bonded versus tax paid inventory | tools cost_inventory_valuation |
| R47 | ama | how many gallons did we produce remove tax paid remove in bond and lose in september | tools compliance_period_summary,compliance_report |
| R48 | ama | how many gallons are in bulk versus packaged by tax class | tools compliance_bulk_vs_bottled |
| R49 | ama | is L-261001-009 still inside the hard cider tax class | tools packaging_tax_class_check |
| R50 | ama | which products need a formula or label approval | tools product_approvals_needed |
| R51 | ama | what did we remove to the taproom last month | tools compliance_removals |
| R52 | ama | where did the pomace go | tools co_product_dispositions |
| R53 | ama | supplier lot from lallemand on L-261001-004 is bad which batches packages and customers got it | tools trace_forward |
| R54 | ama | a customer returned a bad can from L-261001-009 which batch which ingredient lots and which other packages | tools trace_backward |
| A1 | ama | who received GR-00001 and when did they enter the lot numbers | tools activity_record_history,activity_who_did |
| A2 | ama | who changed hill dry cider to recipe version two and what did they look at first | tools activity_who_did,activity_before_and_after,activity_record_history |
| A3 | ama | when did we start planning WO-00002 and who created it | tools activity_who_did,activity_record_history |
| A4 | ama | who adjusted inventory last tuesday and what did they do right before | tools activity_who_did,activity_before_and_after,activity_actor_timeline |
| A5 | ama | who released B-26-002 for packaging and did anyone override an out of spec reading | tools activity_who_did,activity_record_history |
| A6 | ama | who approved PO-00001 and how long did it sit | tools activity_who_did,activity_elapsed |
| A7 | ama | when did the cellar hand last open the tank board and which screens do they use | tools activity_actor_timeline,activity_screen_usage |
| A8 | ama | who last counted the cold room and how long did it take | tools activity_who_did,activity_elapsed |
| A9 | ama | which recipes has nobody opened in a year | tools activity_untouched |
| A10 | ama | what happened on the day B-26-002 lost the most volume | tools activity_day_replay,batch_losses |
| A11 | ama | what did the assistant do on my behalf yesterday and was anything undone | tools activity_assistant_actions |
| A12 | ama | which client AI tools queried our memory this week and what did they ask | tools activity_mcp_usage |
