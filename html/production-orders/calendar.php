<?php
declare(strict_types=1);
// The Vessel calendar became the Equipment schedule (docs/cidery/15-equipment-schedule-plan.md D7, 2026-10-08): its URL lives on.
require_once dirname(__DIR__, 2) . '/app/bootstrap.php';
require_login();
$target = '/schedule/?kind=vessel';
if (is_htmx_request()) {
    hx_location($target);
}
http_response_code(301);
header('Location: ' . $target);
exit;
