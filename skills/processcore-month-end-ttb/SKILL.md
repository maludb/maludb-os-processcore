---
name: processcore-month-end-ttb
description: The runbook for month end at ProcessCore — closing production and removals for the period, reconciling bulk and bottled wine (cider) gallons, building the TTB report (5120.17 or the brewery forms) per premises, and what needs a person before it is finalized.
kind: runbook
---

# Month end and the TTB report

1. **Is the period complete?** `production_batches_in_progress` and `compliance_removals` for the period: every removal
   of the month is posted; every packaging run of the month is posted; every batch loss is recorded. List what is not,
   by document number, for the person who owns it. Never post it yourself to close the month.
2. **Reconcile.** `compliance_bulk_vs_bottled` for the period and premises: bulk gallons in, bottled gallons out, losses,
   and the closing balance must agree with `inventory_on_hand` in bonded locations. A difference is an open question
   for compliance, with the numbers side by side.
3. **Build the report.** `compliance_period_summary` then `compliance_report` for the premises and period. Read every
   line against the line map's meaning; a line that looks wrong is reported as a question, not changed.
4. **Hand it over.** The report is finalized by a person (`ttb_report_finalize` pauses for approval when an agent asks).
   Give compliance the summary, the open questions, and where the figures came from.
5. **After filing.** `activity_day_replay` for the filing day records who finalized and when; note the next period's
   start.
