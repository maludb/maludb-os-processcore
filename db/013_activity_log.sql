-- 013_activity_log.sql — the activity log (day one) and its ingestion into MaluDB. Every handler writes a row; a
-- timer job ships rows into the memory schema as episodes plus subject-verb-object edges. Unchanged from the cidery.
SET search_path = app, public;

CREATE TABLE app.activity_log (
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    occurred_at       timestamptz NOT NULL DEFAULT now(),
    actor_id          bigint REFERENCES app.users(id),       -- NULL = system
    actor_label       text NOT NULL,                         -- 'user/12 Jane Doe', 'system/ingest', 'mcp/token:nightly'
    source            text NOT NULL DEFAULT 'screen' CHECK (source IN ('screen','command_bar','ama','mcp','system','agent','cron','api','web')),
    session_hash      text,                                  -- sha256 of the PHP session id
    request_id        text,
    action            text NOT NULL,                         -- 'screen_entered', 'lot_released', 'receipt_posted', ...
    screen            text,                                  -- screen id from the action manifest
    entity_type       text,
    entity_id         bigint,
    entity_label      text,
    before            jsonb,
    after             jsonb,
    details           jsonb NOT NULL DEFAULT '{}'::jsonb,
    ip                inet,
    agent_run_id      bigint,                                -- the kernel's run id when an agent acted (no FK)
    ingested_at       timestamptz,
    memory_episode_id bigint
);
CREATE INDEX activity_log_occurred_idx ON app.activity_log (occurred_at DESC);
CREATE INDEX activity_log_actor_idx    ON app.activity_log (actor_id, occurred_at DESC);
CREATE INDEX activity_log_entity_idx   ON app.activity_log (entity_type, entity_id, occurred_at DESC);
CREATE INDEX activity_log_action_idx   ON app.activity_log (action, occurred_at DESC);
CREATE INDEX activity_log_pending_idx  ON app.activity_log (id) WHERE ingested_at IS NULL;
CREATE TRIGGER activity_log_immutable BEFORE DELETE ON app.activity_log
    FOR EACH ROW EXECUTE FUNCTION app.forbid_change();

-- The PHP helper log_activity() calls this.
CREATE OR REPLACE FUNCTION app.log_activity(
    p_actor_id bigint, p_actor_label text, p_source text, p_session_hash text, p_request_id text,
    p_action text, p_screen text, p_entity_type text, p_entity_id bigint, p_entity_label text,
    p_before jsonb, p_after jsonb, p_details jsonb, p_ip inet)
RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO app.activity_log (actor_id, actor_label, source, session_hash, request_id, action, screen,
                                  entity_type, entity_id, entity_label, before, after, details, ip)
    VALUES (p_actor_id, p_actor_label, p_source, p_session_hash, p_request_id, p_action, p_screen,
            p_entity_type, p_entity_id, p_entity_label, p_before, p_after, COALESCE(p_details, '{}'::jsonb), p_ip)
    RETURNING id;
$$;

-- Ingestion into MaluDB: each activity row becomes an episode (the event with its full payload) and one SVO edge
-- (actor -verb-> entity) in the 'activity' namespace, so both replay and graph questions work. Runs under
-- processcore_app, whose search_path includes the memory schema. Called by the systemd timer every minute.
CREATE OR REPLACE FUNCTION app.activity_ingest_pending(p_limit int DEFAULT 500)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
    r app.activity_log%ROWTYPE;
    v_episode bigint;
    n int := 0;
BEGIN
    FOR r IN SELECT * FROM app.activity_log WHERE ingested_at IS NULL ORDER BY id LIMIT p_limit LOOP
        v_episode := memory.maludb_register_episode(
            p_episode_kind  => r.action,
            p_title         => r.actor_label || ' ' || replace(r.action, '_', ' ')
                               || COALESCE(' ' || r.entity_type || ' ' || r.entity_label, ''),
            p_summary       => COALESCE(r.details->>'summary', NULL),
            p_payload_jsonb => jsonb_build_object(
                'activity_id', r.id, 'actor_id', r.actor_id, 'actor', r.actor_label, 'source', r.source,
                'screen', r.screen, 'entity_type', r.entity_type, 'entity_id', r.entity_id,
                'entity_label', r.entity_label, 'before', r.before, 'after', r.after, 'details', r.details,
                'session_hash', r.session_hash, 'request_id', r.request_id),
            p_occurred_at   => r.occurred_at,
            p_sensitivity   => 'internal',
            p_provenance    => 'provided');
        IF r.entity_type IS NOT NULL THEN
            PERFORM memory.maludb_memory_ingest_edge(
                p_source_kind   => 'episode_object',
                p_source_id     => v_episode,
                p_subject_text  => r.actor_label,
                p_verb_text     => r.action,
                p_predicate     => jsonb_build_array(jsonb_build_object(
                                       'object', r.entity_type || '/' || COALESCE(r.entity_id::text, '') ,
                                       'label', r.entity_label, 'screen', r.screen)),
                p_subject_type  => 'person',
                p_confidence    => 1.0,
                p_provenance    => 'accepted',
                p_namespace     => 'activity',
                p_valid_from    => r.occurred_at);
        END IF;
        UPDATE app.activity_log SET ingested_at = now(), memory_episode_id = v_episode WHERE id = r.id;
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;
