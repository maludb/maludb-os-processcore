"""Pydantic input models for every activity tool (extra='forbid', constrained fields)."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

DATE_HELP = "ISO date (2026-10-01) or datetime (2026-10-01T14:00, client time zone unless an offset is given)"
PERIOD = Field(default=None, max_length=40, description="Shortcut time window instead of dates: today, yesterday, this_week, last_week, "
               "last_7_days, last_30_days, this_month, last_month, this_year, 'tuesday' (most recent), 'last tuesday' (previous week).")


class Base(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")


class Window(Base):
    date_from: str | None = Field(default=None, max_length=40, description=f"Start of the window, inclusive: {DATE_HELP}.")
    date_to: str | None = Field(default=None, max_length=40, description=f"End of the window; a bare date includes that whole day: {DATE_HELP}.")
    period: str | None = PERIOD


class Page(Base):
    limit: int = Field(default=50, ge=1, le=200, description="Rows to return (1-200).")
    offset: int = Field(default=0, ge=0, le=100000, description="Rows to skip, for paging.")


class EntityRef(Base):
    entity: str | None = Field(default=None, min_length=1, max_length=120,
                               description="The record's label as shown in the app: lot number (L-261001-001), batch number (B-26-004), "
                                           "PO number (PO-00001), receipt (GR-00001), work order (WO-00001), count (CNT-00001), "
                                           "recipe version name (Hill Dry Cider v2), supplier or customer name, keg serial...")
    entity_type: str | None = Field(default=None, max_length=40,
                                    description="Record type: lot, finished_lot, batch, purchase_order, goods_receipt, production_order, "
                                                "recipe_version, count, adjustment, removal, packaging_run, press_run, keg, vessel, item, "
                                                "supplier, customer, period_report, user... Aliases like 'po', 'receipt', 'recipe' work.")
    entity_id: int | None = Field(default=None, ge=1, description="Record id (with entity_type) when known instead of the label.")


class RecordHistoryInput(EntityRef, Window, Page):
    include_related: bool = Field(default=True, description="Also include events on other records that mention this label "
                                                            "(lab readings on a lot, removals or counts naming it), flagged relation='mentions'.")
    include_screen_entries: bool = Field(default=True, description="Include screen_entered rows (who opened the record).")

    @model_validator(mode="after")
    def _need_entity(self):
        if not self.entity and self.entity_id is None:
            raise ValueError("Pass entity (the record's label) or entity_type with entity_id.")
        return self


class ActorTimelineInput(Window, Page):
    actor: str = Field(..., min_length=1, max_length=120, description="Person's name (or part of it), a user id, or a non-user actor such as 'mcp/token:nightly'.")
    screen: str | None = Field(default=None, max_length=80, description="Only events on this screen (id such as tank-board, or words such as 'tank board').")
    action: str | None = Field(default=None, max_length=80, description="Only this action (exact name, fragment, or wildcard like 'count_*').")
    include_screen_entries: bool = Field(default=True, description="Include screen_entered rows (screens opened).")
    include_payloads: bool = Field(default=False, description="Include before/after/details on each event.")
    order: Literal["asc", "desc"] = Field(default="asc", description="asc = oldest first (a timeline); desc = newest first (what did they do last).")


class WhoDidInput(Window, Page):
    action: str = Field(..., min_length=2, max_length=80,
                        description="Action name: receipt_created, receipt_posted, lot_released, batch_release_decided, production_order_created, "
                                    "po_created, po_approved, count_started, count_approved, adjustment_posted, recipe_version_created, "
                                    "batch_loss_recorded... A unique fragment or a wildcard ('count_*') also works.")
    entity: str | None = Field(default=None, max_length=120, description="Only on this record (its label: lot number, PO number, batch number...).")
    entity_type: str | None = Field(default=None, max_length=40, description="Only on this record type.")
    actor: str | None = Field(default=None, max_length=120, description="Only by this person.")
    trail_length: int = Field(default=8, ge=0, le=30, description="How many preceding screen entries (same session) to include per event; 0 for none.")
    trail_minutes: int = Field(default=60, ge=1, le=1440, description="How far back the screen trail reaches, in minutes.")


class BeforeAfterInput(Base):
    activity_id: int | None = Field(default=None, ge=1, description="The activity row id of the anchor event (from any other tool's 'id').")
    actor: str | None = Field(default=None, max_length=120, description="With 'at': the person whose event to anchor on.")
    at: str | None = Field(default=None, max_length=40, description="With 'actor': a time; the actor's event nearest to it is the anchor.")
    action: str | None = Field(default=None, max_length=80, description="With actor/at: anchor on the nearest event of this action (e.g. adjustment_posted).")
    window_minutes: int = Field(default=30, ge=1, le=720, description="Minutes before and after the anchor to include.")
    same_session_only: bool = Field(default=True, description="Only events in the anchor's browser session (falls back to the same actor when the session is unknown).")
    limit: int = Field(default=40, ge=1, le=200, description="Maximum events on each side.")

    @model_validator(mode="after")
    def _anchor(self):
        if self.activity_id is None and not (self.actor and self.at):
            raise ValueError("Pass activity_id, or actor together with at.")
        return self


class ElapsedInput(EntityRef, Window, Page):
    start_action: str = Field(..., min_length=2, max_length=80, description="Action that starts the clock (po_created, count_started, receipt_created, production_order_created).")
    end_action: str = Field(..., min_length=2, max_length=80, description="Action that stops it (po_approved, count_approved, receipt_posted, production_order_released).")


class ScreenUsageInput(Window, Page):
    group_by: Literal["actor", "screen", "hour", "role", "day", "actor_screen"] = Field(default="screen", description="How to aggregate screen entries.")
    screen: str | None = Field(default=None, max_length=80, description="Only this screen (id or words, e.g. 'tank board').")
    actor: str | None = Field(default=None, max_length=120, description="Only this person.")
    role: str | None = Field(default=None, max_length=40, description="Only people with this role (owner, cellar, receiving, quality, packaging, viewer...).")
    hour_from: int | None = Field(default=None, ge=0, le=23, description="Only entries at or after this local hour (0-23). With hour_to < hour_from the range wraps midnight (night shift 22 to 6).")
    hour_to: int | None = Field(default=None, ge=0, le=23, description="Only entries before this local hour (exclusive).")


class UntouchedInput(Page):
    entity_type: str = Field(..., min_length=2, max_length=40, description="Record type, e.g. recipe_version, item, supplier, vessel, customer, product.")
    screen: str | None = Field(default=None, max_length=80, description="Screen whose entries count as 'opened' (recipe-view). Default: any screen entry on the record.")
    since_days: int = Field(default=365, ge=1, le=3650, description="Untouched means no screen entry in this many days.")


class DayReplayInput(EntityRef, Page):
    date: str | None = Field(default=None, max_length=40, description=f"The day to replay: {DATE_HELP}, or a period word (yesterday, tuesday). "
                                                                      "Omit with day_of_action to find the day automatically.")
    day_of_action: str | None = Field(default=None, max_length=80,
                                      description="Replay the day of the most recent event of this action on the record, e.g. batch_loss_recorded "
                                                  "('the day batch B lost 40 gallons'), batch_dumped, adjustment_posted.")
    include_screen_entries: bool = Field(default=True, description="Include screen_entered rows.")
    include_episodes: bool = Field(default=True, description="Attach the MaluDB episode (id, kind, title) for each event.")

    @model_validator(mode="after")
    def _need_day(self):
        if not self.date and not self.day_of_action:
            raise ValueError("Pass date, or day_of_action with the record (entity) to find the day.")
        if self.day_of_action and not (self.entity or self.entity_id):
            raise ValueError("day_of_action needs the record: pass entity (its label) or entity_type with entity_id.")
        return self


class AssistantActionsInput(Window, Page):
    actor: str | None = Field(default=None, max_length=120, description="Whose behalf (person's name or id). Default: everyone.")
    include_messages: bool = Field(default=False, description="Also list the assistant_message / ama_question rows (what was asked), not only actions taken.")


class McpUsageInput(Window, Page):
    token: str | None = Field(default=None, max_length=120, description="Only calls made with this access token (its name as created on the AI access tokens screen).")
    tool: str | None = Field(default=None, max_length=80, description="Only this tool name (records_search, activity_who_did, ...).")
    server: Literal["processcore_records_mcp", "processcore_activity_mcp", "processcore_actions_mcp"] | None = Field(default=None, description="Only calls to this server.")
    include_calls: bool = Field(default=True, description="List the individual calls (with arguments) as well as the per-token summary.")


class SearchInput(Window, Page):
    query: str | None = Field(default=None, min_length=2, max_length=200,
                              description="Full-text words over episode titles: actor, action words, record type and label "
                                          "(e.g. 'lot released L-261001-002', 'receipt GR-00001', 'Honour adjustment').")
    subject: str | None = Field(default=None, max_length=120, description="Subject-verb search: who (actor name fragment, e.g. 'Ed Honour') or the episode subject (record label).")
    verb: str | None = Field(default=None, max_length=80, description="Subject-verb search: the action/verb (lot_released, po_approved; fragment allowed).")
    kind: str | None = Field(default=None, max_length=80, description="Only episodes of this kind (the action name).")

    @model_validator(mode="after")
    def _need_something(self):
        if not (self.query or self.subject or self.verb or self.kind):
            raise ValueError("Pass query text, or subject and/or verb, or kind.")
        return self


class SqlInput(Base):
    sql: str = Field(..., min_length=8, max_length=8000,
                     description="Exactly one SELECT (or WITH ... SELECT) over app.activity_log, app.users (id, display_name, role, status) "
                                 "and memory.maludb_* views. No semicolons or comments; at most 200 rows come back.")
