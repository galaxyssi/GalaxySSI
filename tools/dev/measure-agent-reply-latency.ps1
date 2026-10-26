param(
    [Parameter(Mandatory=$true)][string]$Token,
    [Parameter(Mandatory=$true)][string]$Serial,
    [string]$Adb = "adb",
    [string]$Backend = "http://127.0.0.1:8765"
)
$ErrorActionPreference = "Stop"
[xml]$snapshot = (& $Adb -s $Serial shell run-as com.galaxyssi.chat cat shared_prefs/galaxyssi_debug_agent.xml) -join "`n"
$test = ($snapshot.map.string | Where-Object name -eq $Token).InnerText | ConvertFrom-Json
if (-not $test) { throw "Debug test token was not found" }
$tasks = (Invoke-RestMethod "$Backend/api/agent/tasks?limit=100").tasks
$task = $tasks | Where-Object { $_.client_conversation_id -eq $test.conversation_id -and $_.client_turn_id -eq $test.turn_id } | Select-Object -First 1
if (-not $task) { throw "Desktop has not received this test turn" }
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($task.task_id))).ToLower()
$desktop = @((Invoke-RestMethod "$Backend/api/agents/latency?include_events=true").events | Where-Object trace_id -eq $hash)
$phone = @(& $Adb -s $Serial shell run-as com.galaxyssi.chat cat no_backup/diagnostics/agent_latency_v1.jsonl | ForEach-Object {
    try { $point = $_ | ConvertFrom-Json; if ($point.trace_id -eq $hash) { $point } } catch {}
})
function Point($events, $stage) { $events | Where-Object stage -eq $stage | Sort-Object monotonic_ns | Select-Object -First 1 }
function Span($events, $start, $end) {
    $a = Point $events $start
    $b = Point $events $end
    if ($a -and $b -and $a.clock_id -eq $b.clock_id) { [math]::Round(($b.monotonic_ns - $a.monotonic_ns) / 1000000.0, 3) }
}
# Cross-device wall times are estimates; retain the sampling uncertainty explicitly.
$clocks = @(1..3 | ForEach-Object {
    $before = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $raw = & $Adb -s $Serial shell date '+%s%3N'
    $after = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    [pscustomobject]@{ offset = [double]$raw.Trim() - ($before + $after) / 2; uncertainty = ($after - $before) / 2 }
})
$clock = $clocks | Sort-Object uncertainty | Select-Object -First 1
$complete = Point $desktop 'desktop_task_completed'
$wire = Point $desktop 'desktop_wire_started'
$received = Point $phone 'phone_final_received'
$visible = Point $phone 'phone_final_output_visible'
[ordered]@{
    token = $Token
    phase = $test.phase
    desktop_task_id = $task.task_id
    request_to_visible_ms = Span $phone 'phone_send_started' 'phone_final_output_visible'
    desktop_execution_ms = Span $desktop 'desktop_agent_started' 'desktop_task_completed'
    desktop_complete_to_send_ms = Span $desktop 'desktop_task_completed' 'desktop_wire_started'
    desktop_queue_ms = Span $desktop 'desktop_transport_queued' 'desktop_transport_dispatched'
    desktop_broker_ack_ms = Span $desktop 'desktop_wire_started' 'desktop_broker_acked'
    phone_consume_ms = Span $phone 'phone_final_consume_started' 'phone_final_accepted'
    phone_finalize_ms = Span $phone 'phone_final_accepted' 'phone_finalized'
    phone_received_to_visible_ms = Span $phone 'phone_final_received' 'phone_final_output_visible'
    downlink_ms_estimate = $(if ($wire -and $received) { $received.wall_clock_ms - $clock.offset - $wire.wall_clock_ms })
    post_completion_ms_estimate = $(if ($complete -and $visible) { $visible.wall_clock_ms - $clock.offset - $complete.wall_clock_ms })
    clock_offset_phone_minus_pc_ms = $clock.offset
    clock_sampling_uncertainty_ms = $clock.uncertainty
    content_included = $false
} | ConvertTo-Json
