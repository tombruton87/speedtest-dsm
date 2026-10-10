# Speedtest Tracker's steps for the chassis harness (chassis/tests/e2e.sh <appdir> act).
# Runs one real speed test (about half a minute, over this box's internet line).
app_e2e_answers() { printf "ADMIN_EMAIL='ada@example.com'\nADMIN_NAME='Ada+Admin'\nEVERY='6h'\nTLS='off'\n"; }
wait_for() { local i; for i in $(seq 1 "$2"); do touch "$VAR/watching"; jq -e "$1" "$VAR/status.json" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }
b64u() { printf '%s' "$1" | base64 -w0 | tr '+/' '-_' | tr -d '='; }
pw_ok() {   # email password → 0 when Speedtest Tracker's own hash check accepts them (the password on stdin)
  printf '%s\n%s' "$1" "$2" | docker exec -i -u abc -w /app/www speedtest-app php -r '
    require "vendor/autoload.php"; $app = require "bootstrap/app.php"; $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    [$e, $p] = explode("\n", stream_get_contents(STDIN), 2); $u = App\Models\User::where("email", $e)->first();
    exit($u && Illuminate\Support\Facades\Hash::check($p, $u->password) ? 0 : 1);' 2>/dev/null
}
secret() { local s; s=$(jq -r 'select(.kind == "account") | .password' "$VAR/secret.json" 2>/dev/null); rm -f "$VAR/secret.json"; printf '%s' "$s"; }
cenv() { docker exec speedtest-app printenv "$1" 2>/dev/null; }
app_e2e_act() {
  local fail=0 url="http://127.0.0.1:$PORT" pw pw2 tok code mon
  log "speedtest"
  echo "  (health: HTTP $(curl -s -o /dev/null -w '%{http_code}' "$url/api/healthcheck"), version $(jq -r .version "$VAR/status.json"))"
  # Your account: the default admin@example.com is gone, and the one-time password signs in.
  pw=$(secret)
  [[ ${#pw} -ge 20 ]] && echo "  ok   a one-time password was left for the window" || { echo "  FAIL no password secret"; fail=1; }
  pw_ok ada@example.com "$pw" && echo "  ok   it's the password of ada@example.com" || { echo "  FAIL password doesn't match"; fail=1; }
  pw_ok admin@example.com password && { echo "  FAIL the default admin@example.com / password still works"; fail=1; } || echo "  ok   the default login no longer works"
  jq -e '.app.me.email == "ada@example.com" and .app.me.name == "Ada Admin"' "$VAR/status.json" >/dev/null && echo "  ok   the window shows your account" || { echo "  FAIL me: $(jq -c .app.me "$VAR/status.json")"; fail=1; }
  [[ "$(cenv SPEEDTEST_SCHEDULE)" =~ ^[0-9]+\ \*/6\ \*\ \*\ \*$ ]] && echo "  ok   the wizard's every 6 hours: $(cenv SPEEDTEST_SCHEDULE)" || { echo "  FAIL schedule: $(cenv SPEEDTEST_SCHEDULE)"; fail=1; }
  # Thresholds no line meets, then a real test: it comes in below them, and DSM is told.
  request "ACTION='limits'" "ON='1'" "LIM_DOWN='99999'" "LIM_UP='0'" "LIM_PING='0'" || fail=1
  wait_for '.app.limits.on == true and .app.limits.down == 99999' 20 && echo "  ok   thresholds saved" || { echo "  FAIL limits: $(jq -c .app.limits "$VAR/status.json")"; fail=1; }
  local i; for i in $(seq 1 90); do [[ -s "$VAR/.alert-seen" ]] && break; touch "$VAR/watching"; sleep 1; done   # the alerts have their starting point
  request "ACTION='runnow'" || fail=1
  request "ACTION='runnow'" >/dev/null && { echo "  FAIL a second test started while one runs"; fail=1; } || echo "  ok   one test at a time: $(jq -r .last.message "$VAR/status.json")"
  if wait_for '.app.recent[0].status == "completed" or .app.recent[0].status == "failed"' 180; then
    jq -e '.app.recent[0] | .status == "completed" and .down > 0 and .up > 0 and .ping > 0 and .healthy == false' "$VAR/status.json" >/dev/null \
      && echo "  ok   a real test: $(jq -r '.app.recent[0] | "\(.down / 1e6 | floor) Mbps down, \(.up / 1e6 | floor) up, \(.ping) ms, \(.server)"' "$VAR/status.json"), below the thresholds" \
      || { echo "  FAIL result: $(jq -c '.app.recent[0]' "$VAR/status.json")"; fail=1; }
  else echo "  FAIL no result in 3 minutes: $(jq -c '.app.recent[0]' "$VAR/status.json")"; fail=1; fi
  jq -e '.app.avg.d1.n == 1 and .app.avg.d1.down > 0' "$VAR/status.json" >/dev/null && echo "  ok   averages" || { echo "  FAIL avg: $(jq -c .app.avg "$VAR/status.json")"; fail=1; }
  for i in $(seq 1 90); do grep -qE "told DSM: speedslow|notification \(speedslow\)" "$VAR/package.log" && break; touch "$VAR/watching"; sleep 1; done
  grep -qE "told DSM: speedslow|a DSM notification \(speedslow\)" "$VAR/package.log" && echo "  ok   the slow result went to DSM's notifications (no DSM here, so it was only attempted)" || { echo "  FAIL no DSM notification attempt"; fail=1; }
  request "ACTION='limits'" "ON='0'" "LIM_DOWN='0'" "LIM_UP='0'" "LIM_PING='0'" >/dev/null || fail=1
  # The month's results as a CSV in the shared folder.
  request "ACTION='historynow'" || fail=1; mon=$(date +%Y-%m)
  [[ "$(head -n 1 "$APP/Speed history/$mon.csv" 2>/dev/null)" == time,download_mbps,* && "$(wc -l < "$APP/Speed history/$mon.csv")" -ge 2 ]] \
    && echo "  ok   Speed history/$mon.csv: $(sed -n 2p "$APP/Speed history/$mon.csv" | cut -c1-80)…" || { echo "  FAIL csv: $(ls -la "$APP/Speed history" 2>&1 | tr '\n' ' ')"; fail=1; }
  # Schedule, server list, keep, public dashboard: Speedtest Tracker's environment.
  request "ACTION='servers'" || fail=1
  jq -e 'length > 0 and (.[0].id | type == "number")' "$VAR/servers.json" >/dev/null 2>&1 && echo "  ok   servers near here: $(jq -r '.[0] | "\(.name), \(.location)"' "$VAR/servers.json")…" || { echo "  FAIL servers"; fail=1; }
  local sid; sid=$(jq -r '.[0].id' "$VAR/servers.json" 2>/dev/null)
  request "ACTION='schedule'" "EVERY='1h'" "SERVER_ID='$sid'" "KEEP_DAYS='90'" || fail=1
  [[ "$(cenv SPEEDTEST_SCHEDULE)" =~ ^[0-9]+\ \*\ \*\ \*\ \*$ && "$(cenv SPEEDTEST_SERVERS)" == "$sid" && "$(cenv PRUNE_RESULTS_OLDER_THAN)" == 90 ]] \
    && echo "  ok   every hour, server $sid, 90 days — in Speedtest Tracker's environment" || { echo "  FAIL schedule env: $(cenv SPEEDTEST_SCHEDULE) / $(cenv SPEEDTEST_SERVERS) / $(cenv PRUNE_RESULTS_OLDER_THAN)"; fail=1; }
  request "ACTION='schedule'" "EVERY='off'" "SERVER_ID=''" "KEEP_DAYS='0'" >/dev/null || fail=1
  [[ -z "$(cenv SPEEDTEST_SCHEDULE)" ]] && echo "  ok   only when asked: no schedule" || { echo "  FAIL off: $(cenv SPEEDTEST_SCHEDULE)"; fail=1; }
  code=$(curl -s -o /dev/null -w '%{http_code}' "$url/")
  request "ACTION='public'" "ON='1'" || fail=1
  [[ "$(cenv PUBLIC_DASHBOARD)" == true && "$(curl -s -o /dev/null -w '%{http_code}' "$url/")" == 200 && "$code" != 200 ]] && echo "  ok   public dashboard: / answers without a sign-in (was $code)" || { echo "  FAIL public: $(cenv PUBLIC_DASHBOARD) $code → $(curl -s -o /dev/null -w '%{http_code}' "$url/")"; fail=1; }
  request "ACTION='public'" "ON='0'" >/dev/null || fail=1
  # API tokens: shown once, limited to what they may do, and removable.
  request "ACTION='token'" "NAME_B64='$(b64u 'Home "dash" & co')'" "TOKEN_KIND='read'" || fail=1
  tok=$(secret)
  [[ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $tok" -H 'Accept: application/json' "$url/api/v1/results/latest")" == 200 ]] && echo "  ok   a read token reads results" || { echo "  FAIL token read"; fail=1; }
  [[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $tok" -H 'Accept: application/json' "$url/api/v1/speedtests/run")" == 403 ]] && echo "  ok   …and can't start tests" || { echo "  FAIL read token ran a test"; fail=1; }
  wait_for '.app.tokens | map(.name) | index("Home \"dash\" & co")' 20 && echo "  ok   listed with its name intact" || { echo "  FAIL tokens: $(jq -c .app.tokens "$VAR/status.json")"; fail=1; }
  request "ACTION='untoken'" "TOKEN_ID='$(jq -r '.app.tokens[0].id' "$VAR/status.json")'" || fail=1
  [[ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $tok" -H 'Accept: application/json' "$url/api/v1/results/latest")" == 401 ]] && echo "  ok   removed: it no longer works" || { echo "  FAIL removed token still works"; fail=1; }
  # A new password, shown once.
  request "ACTION='mypw'" || fail=1; pw2=$(secret)
  pw_ok ada@example.com "$pw2" && ! pw_ok ada@example.com "$pw" && echo "  ok   new password works, the old one doesn't" || { echo "  FAIL mypw"; fail=1; }
  # HTTPS through the container's own nginx.
  request "ACTION='settings'" "TLS='self'" || fail=1
  [[ "$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1:$PORT/api/healthcheck")" == 200 ]] && echo "  ok   HTTPS self: https answers" || { echo "  FAIL https"; fail=1; }
  jq -e '.app.tls.cert.self_signed == true' "$VAR/status.json" >/dev/null && echo "  ok   the certificate is shown" || { echo "  FAIL cert info"; fail=1; }
  request "ACTION='settings'" "TLS='off'" || fail=1
  [[ "$(curl -s -o /dev/null -w '%{http_code}' "$url/api/healthcheck")" == 200 ]] && echo "  ok   back to plain HTTP" || { echo "  FAIL http again"; fail=1; }
  (( fail )) && { echo "  speedtest: something FAILED"; return 1; }; echo "  speedtest: all passed"
}
