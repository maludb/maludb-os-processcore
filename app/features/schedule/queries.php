<?php
declare(strict_types=1);

require_once __DIR__ . '/../reservations/queries.php';
require_once __DIR__ . '/../vessels/queries.php';
require_once __DIR__ . '/../equipment/queries.php';
require_once __DIR__ . '/../production-orders/queries.php';

// The Equipment schedule (docs/cidery/16-equipment-schedule-design.md §3): resources × days, bookings as bars or chips.

const SCHEDULE_WEEKS = [1 => '1 week', 2 => '2 weeks', 4 => '4 weeks', 8 => '8 weeks', 12 => '12 weeks'];
const SCHEDULE_KINDS = ['vessel' => 'Vessels', 'equipment' => 'Equipment'];

/**
 * Active resources for the schedule, filtered by premises, by kind ("vessel", "equipment", or one vessel or equipment
 * kind such as "fermenter" or "canning_line") and by one resource key. Keyed "vessel:12".
 */
function find_schedule_resources(PDO $pdo, ?int $premisesId, string $kind, ?string $resourceKey): array
{
    $catalog = reservation_resource_catalog($pdo);
    $out = [];
    foreach ($catalog as $key => $r) {
        if ($premisesId !== null && (int) $r['premises_id'] !== $premisesId) { continue; }
        if ($kind !== '' && $kind !== $r['resource_kind'] && $kind !== $r['kind']) { continue; }
        if ($resourceKey !== null && $resourceKey !== $key) { continue; }
        $out[$key] = $r;
    }
    return $out;
}

/** Booked reservations overlapping [startsAt, endsAt), keyed by resource key, each sorted by start. */
function find_schedule_bookings(PDO $pdo, string $startsAt, string $endsAt, array $resourceKeys, ?string $subjectKey = null): array
{
    $statement = $pdo->prepare('SELECT s.* FROM app.v_equipment_schedule s WHERE tstzrange(s.starts_at, s.ends_at) && tstzrange(:s::timestamptz, :e::timestamptz) ORDER BY s.starts_at, s.ends_at DESC, s.id');
    $statement->execute(['s' => $startsAt, 'e' => $endsAt]);
    $by = array_fill_keys($resourceKeys, []);
    foreach ($statement->fetchAll() as $row) {
        $key = $row['resource_kind'] . ':' . (int) $row['resource_id'];
        if (!isset($by[$key])) { continue; }
        if ($subjectKey !== null && ($row['subject_kind'] ?? '') . ':' . (int) ($row['subject_id'] ?? 0) !== $subjectKey) { continue; }
        $by[$key][] = $row;
    }
    return $by;
}

/** What each vessel holds right now: vessel id => ['label', 'production_order_id', 'occupant_kind', 'occupant_id']. */
function find_schedule_occupants(PDO $pdo): array
{
    $rows = $pdo->query("SELECT vb.vessel_id, vb.occupant_kind, vb.occupant_id, vb.occupant_label, b.production_order_id FROM app.v_vessel_board vb LEFT JOIN app.batches b ON vb.occupant_kind = 'batch' AND b.id = vb.occupant_id WHERE vb.occupant_kind IS NOT NULL")->fetchAll();
    $out = [];
    foreach ($rows as $r) {
        $out[(int) $r['vessel_id']] = ['label' => (string) $r['occupant_label'], 'production_order_id' => $r['production_order_id'] === null ? null : (int) $r['production_order_id'], 'occupant_kind' => $r['occupant_kind'], 'occupant_id' => (int) $r['occupant_id']];
    }
    return $out;
}

/** Lanes for one resource's bookings: each lane a list of bookings that do not overlap each other (greedy, by start). */
function schedule_lanes(array $bookings): array
{
    $lanes = [];
    $laneEnds = [];
    foreach ($bookings as $b) {
        $placed = false;
        foreach ($laneEnds as $i => $end) {
            if ($end <= $b['starts_at']) {
                $lanes[$i][] = $b;
                $laneEnds[$i] = $b['ends_at'];
                $placed = true;
                break;
            }
        }
        if (!$placed) {
            $lanes[] = [$b];
            $laneEnds[] = $b['ends_at'];
        }
    }
    return $lanes === [] ? [[]] : $lanes;
}

/** The bar's colour: the run's status colour, or the block's. */
function schedule_bar_color(array $b): string
{
    if ($b['subject_kind'] === null) {
        return ['cleaning' => 'info', 'maintenance' => 'secondary', 'hold' => 'dark'][$b['kind']] ?? 'secondary';
    }
    if ($b['subject_kind'] === 'production_order') {
        return PRODUCTION_ORDER_STATUS_COLORS[$b['subject_status']] ?? 'secondary';
    }
    return status_color((string) $b['subject_status']);
}

/** Where a bar or chip leads: the run, or the reservation for a block. */
function schedule_bar_url(array $b): string
{
    return $b['subject_kind'] !== null ? reservation_subject_url($b['subject_kind'], (int) $b['subject_id']) : '/reservations/' . (int) $b['id'];
}

function schedule_bar_text(array $b): string
{
    return $b['subject_kind'] !== null
        ? $b['subject_number'] . ' · ' . $b['subject_label'] . ' · ' . humanize($b['role'])
        : humanize($b['kind']) . ($b['notes'] ? ' · ' . $b['notes'] : '');
}
