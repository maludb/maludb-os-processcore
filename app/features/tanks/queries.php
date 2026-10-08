<?php
declare(strict_types=1);

// The Tank view (Inventory, docs/cidery/14-tank-view.md): every active vessel with what it holds, laid out as it stands on the
// floor. Positions are grid units on app.vessels (db/022); a vessel never placed is laid out after the placed ones.

const TANK_VIEW_GRID = 20;          // px per grid unit in the screen
const TANK_VIEW_CARD_W = 8;         // card width in grid units (160 px)
const TANK_VIEW_CARD_H = 15;        // card height in grid units (300 px), the auto-layout's row pitch
const TANK_VIEW_COLUMNS = 6;        // auto-layout columns for vessels never placed

/** Stage groups → the liquid's colour class and a short word for what the tank holds. */
const TANK_VIEW_CONTENT = [
    'juice'        => ['class' => 'tank-view-liquid-juice', 'word' => 'Juice'],
    'fermenting'   => ['class' => 'tank-view-liquid-fermenting', 'word' => 'Fermenting'],
    'conditioning' => ['class' => 'tank-view-liquid-conditioning', 'word' => 'Base cider'],
    'finished'     => ['class' => 'tank-view-liquid-finished', 'word' => 'Finished'],
];

function tank_view_content_kind(?string $occupantKind, ?string $stageCode): ?string
{
    if ($occupantKind === null) {
        return null;
    }
    if ($occupantKind === 'lot') {
        return 'juice';
    }
    return match ($stageCode) {
        'pitch', 'primary' => 'fermenting',
        'carbonate', 'package' => 'finished',
        default => 'conditioning',
    };
}

/**
 * Every active vessel on the board (optionally one premises or one kind), with its occupant, fill and position.
 * Vessels with no position get one after the placed ones, row by row, never written back — a drag writes it.
 */
function find_tank_view(PDO $pdo, ?int $premisesId, ?string $kind): array
{
    $statement = $pdo->prepare(<<<'SQL'
        SELECT vb.*, st.name AS stage_name, pr.name AS premises_name, b.status AS batch_status
          FROM app.v_vessel_board vb
          JOIN app.premises pr ON pr.id = vb.premises_id
          LEFT JOIN app.stages st ON st.code = vb.current_stage_code
          LEFT JOIN app.batches b ON vb.occupant_kind = 'batch' AND b.id = vb.occupant_id
         WHERE (:p::bigint IS NULL OR vb.premises_id = :p::bigint) AND (:k::text IS NULL OR vb.vessel_kind = :k::text)
         ORDER BY (vb.board_y IS NULL), vb.board_y, vb.board_x, vb.vessel_kind, vb.vessel_name
    SQL);
    $statement->execute(['p' => $premisesId, 'k' => $kind]);
    $rows = $statement->fetchAll();
    $maxY = -TANK_VIEW_CARD_H;
    foreach ($rows as $r) {
        if ($r['board_y'] !== null) {
            $maxY = max($maxY, (int) $r['board_y']);
        }
    }
    $slot = 0;
    foreach ($rows as &$r) {
        $r['placed'] = $r['board_x'] !== null && $r['board_y'] !== null;
        if (!$r['placed']) {
            $r['board_x'] = ($slot % TANK_VIEW_COLUMNS) * (TANK_VIEW_CARD_W + 1);
            $r['board_y'] = $maxY + TANK_VIEW_CARD_H + 1 + intdiv($slot, TANK_VIEW_COLUMNS) * (TANK_VIEW_CARD_H + 1);
            $slot++;
        }
        $r['content_kind'] = tank_view_content_kind($r['occupant_kind'], $r['current_stage_code']);
        $r['fill_pct'] = $r['occupant_kind'] === null ? 0.0 : (float) $r['fill_pct'];
    }
    unset($r);
    return $rows;
}

function find_tank_view_vessel(PDO $pdo, int $id): ?array
{
    $statement = $pdo->prepare('SELECT id, name, board_x, board_y, premises_id FROM app.vessels WHERE id = :id AND active');
    $statement->execute(['id' => $id]);
    return $statement->fetch() ?: null;
}

/** Where a vessel stands on the board, in grid units. */
function update_vessel_position(PDO $pdo, int $id, int $x, int $y): array
{
    $statement = $pdo->prepare('UPDATE app.vessels SET board_x = :x, board_y = :y WHERE id = :id RETURNING id, name, board_x, board_y');
    $statement->execute(['x' => $x, 'y' => $y, 'id' => $id]);
    $row = $statement->fetch();
    if ($row === false) {
        throw new RuntimeException('Vessel not found.');
    }
    return $row;
}
