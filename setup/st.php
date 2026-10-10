<?php
// Runs inside the Speedtest Tracker container for the DSM package: piped to `php`
// (as the web user) with one line in front setting $ACT and $ARG_B64 (base64
// JSON) — so passwords travel on stdin, never in argv or env. Speedtest Tracker
// is booted and its own models and actions do the work. Prints one JSON line:
// {"ok":…, "msg":…, …}.
require '/app/www/vendor/autoload.php';
$app = require '/app/www/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\Result;
use App\Models\User;
use App\Settings\ThresholdSettings;

function out(array $o) { echo json_encode($o, JSON_UNESCAPED_SLASHES), "\n"; exit(!empty($o['ok']) ? 0 : 1); }
$arg = json_decode(base64_decode($ARG_B64), true) ?: [];
const BUSY = ['waiting', 'started', 'checking', 'running', 'benchmarking'];

function row(Result $r): array {   // a result as the window shows it: bits per second, ms, the server
    $d = $r->data ?? [];
    return [
        'id' => $r->id, 'at' => $r->created_at?->timestamp, 'status' => $r->status?->value,
        'down' => $r->download ? (int) $r->download * 8 : null, 'up' => $r->upload ? (int) $r->upload * 8 : null,
        'ping' => $r->ping !== null ? round((float) $r->ping, 1) : null, 'jitter' => isset($d['ping']['jitter']) ? round((float) $d['ping']['jitter'], 1) : null,
        'loss' => isset($d['packetLoss']) ? round((float) $d['packetLoss'], 1) : null,
        'server' => trim(($d['server']['name'] ?? '') . (isset($d['server']['location']) ? ', ' . $d['server']['location'] : ''), ', '),
        'isp' => $d['isp'] ?? '', 'url' => $d['result']['url'] ?? '', 'healthy' => $r->healthy, 'scheduled' => (bool) $r->scheduled,
        'message' => $r->status?->value === 'failed' ? mb_substr((string) ($d['message'] ?? 'the test failed'), 0, 200) : '',
    ];
}
function averages(int $days): array {
    $q = Result::where('status', 'completed')->where('created_at', '>=', now()->subDays($days));
    return ['n' => (clone $q)->count(), 'down' => (int) round(((clone $q)->avg('download') ?? 0) * 8), 'up' => (int) round(((clone $q)->avg('upload') ?? 0) * 8),
            'ping' => round((float) ((clone $q)->avg('ping') ?? 0), 1)];
}

try {
    switch ($ACT) {
        case 'firstadmin':   // the well-known admin@example.com / password becomes yours
            $u = User::where('email', 'admin@example.com')->first();
            if (!$u) out(['ok' => false, 'msg' => 'nodefault']);
            $u->forceFill(['name' => $arg['name'], 'email' => $arg['email'], 'password' => $arg['password']])->save();   // the model hashes it
            out(['ok' => true, 'id' => $u->id]);

        case 'mypw':         // a new password for the package's account (yours)
            $u = User::where('email', $arg['email'])->first();
            if (!$u) out(['ok' => false, 'msg' => "There's no account " . $arg['email'] . ' in Speedtest Tracker any more.']);
            $u->forceFill(['password' => $arg['password']])->save();
            out(['ok' => true]);

        case 'status':       // everything the window shows, in one go
            $me = User::where('email', $arg['email'] ?? '')->first();
            $t = app(ThresholdSettings::class);
            out(['ok' => true,
                'recent' => Result::orderByDesc('id')->limit(15)->get()->map(fn ($r) => row($r))->all(),
                'avg' => ['d1' => averages(1), 'd7' => averages(7), 'd30' => averages(30)],
                'running' => Result::whereIn('status', BUSY)->where('created_at', '>=', now()->subHour())->exists(),
                'total' => Result::count(), 'failed7' => Result::where('status', 'failed')->where('created_at', '>=', now()->subDays(7))->count(),
                'limits' => ['on' => $t->absolute_enabled, 'down' => $t->absolute_download, 'up' => $t->absolute_upload, 'ping' => $t->absolute_ping],
                'me' => $me ? ['name' => $me->name, 'email' => $me->email] : null,
                'tokens' => $me ? $me->tokens()->orderBy('id')->get()->map(fn ($k) => ['id' => $k->id, 'name' => $k->name, 'abilities' => $k->abilities,
                    'created' => $k->created_at?->timestamp, 'used' => $k->last_used_at?->timestamp])->all() : [],
                'users' => User::count()]);

        case 'since':        // finished results after an id, for alerts
            out(['ok' => true, 'rows' => Result::where('id', '>', (int) $arg['id'])->whereNotIn('status', BUSY)->orderBy('id')->limit(50)->get()->map(fn ($r) => row($r))->all(),
                 'last' => (int) (Result::whereNotIn('status', BUSY)->max('id') ?? 0)]);

        case 'month':        // a month's results, for the CSV in the shared folder (times in the NAS's zone)
            $from = Carbon\Carbon::createFromFormat('Y-m-d H:i:s', $arg['month'] . '-01 00:00:00', $arg['tz'] ?? 'UTC');
            $rows = Result::where('created_at', '>=', $from->copy()->utc())->where('created_at', '<', $from->copy()->addMonth()->utc())->orderBy('id')->get()
                ->map(fn ($r) => array_merge(row($r), ['local' => $r->created_at?->copy()->setTimezone($arg['tz'] ?? 'UTC')->format('Y-m-d H:i')]))->all();
            out(['ok' => true, 'rows' => $rows]);

        case 'run':          // a speed test now (queued; the container's worker runs it)
            if (Result::whereIn('status', BUSY)->where('created_at', '>=', now()->subMinutes(10))->exists()) out(['ok' => false, 'msg' => 'A speed test is already running.']);
            $me = User::where('email', $arg['email'] ?? '')->first();
            App\Actions\Ookla\RunSpeedtest::run(scheduled: false, serverId: !empty($arg['server']) ? (int) $arg['server'] : null, dispatchedBy: $me?->id);
            out(['ok' => true]);

        case 'limits':       // the thresholds a result has to meet to count as healthy
            $t = app(ThresholdSettings::class);
            $t->absolute_enabled = (bool) $arg['on'];
            $t->absolute_download = $arg['down'] > 0 ? (float) $arg['down'] : null;
            $t->absolute_upload = $arg['up'] > 0 ? (float) $arg['up'] : null;
            $t->absolute_ping = $arg['ping'] > 0 ? (float) $arg['ping'] : null;
            $t->save();
            out(['ok' => true]);

        case 'servers':      // Ookla's servers near this Synology
            $list = App\Actions\GetOoklaSpeedtestServers::forApi();
            if (!$list) out(['ok' => false, 'msg' => "Ookla's server list couldn't be fetched — is this Synology online?"]);
            out(['ok' => true, 'servers' => array_values(array_map(fn ($s) => ['id' => (int) $s['id'], 'name' => $s['name'], 'location' => $s['location'], 'country' => $s['country']], $list))]);

        case 'token':        // an API token for another app (Homepage, Home Assistant…), shown once
            $u = User::where('email', $arg['email'])->first();
            if (!$u) out(['ok' => false, 'msg' => 'Your account was not found.']);
            out(['ok' => true, 'token' => $u->createToken($arg['name'], $arg['abilities'])->plainTextToken]);

        case 'untoken':
            $u = User::where('email', $arg['email'])->first();
            $n = $u ? $u->tokens()->where('id', (int) $arg['id'])->delete() : 0;
            out($n ? ['ok' => true] : ['ok' => false, 'msg' => 'That token was not found.']);

        default:
            out(['ok' => false, 'msg' => 'unknown action']);
    }
} catch (Throwable $e) {
    out(['ok' => false, 'msg' => mb_substr($e->getMessage(), 0, 300)]);
}
