# Speedtest Tracker's hooks for the chassis core (sourced by run-core.sh). The
# core gives: say, env_get/env_set, rand, compose, in_volume, cname, svc_up,
# leave_secret, notify, fresh, now, for_window, wait_ready, MSG, VAR, APP, LOG,
# PKG_NAME, PKG_TITLE, HOST_UID/HOST_GID, and the tls_* helpers (chassis tls.sh).
#
# Everything goes through Speedtest Tracker itself: its own models and actions
# (setup/st.php, piped to PHP inside its container with the app booted;
# passwords on stdin). It ships with a well-known admin (admin@example.com /
# password): the first start makes it yours. Settings it reads from its
# environment (schedule, server, pruning, public dashboard) live in .env.

SA=""; STPHP=/pkg/setup/st.php
HISTORY_DIR="Speed history"

app_validate() {   # key value → 0 if the value has the key's shape
  case "$1" in
    ADMIN_EMAIL) [[ "$2" =~ ^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] ;;
    ADMIN_NAME)  [[ "$2" =~ ^[A-Za-z0-9._@+-]+$ ]] && (( ${#2} <= 60 )) ;;   # spaces arrive as +
    TLS)         [[ "$2" =~ ^(dsm|self|off)$ ]] ;;
    EVERY)       [[ "$2" =~ ^(1h|3h|6h|12h|24h|off)$ ]] ;;
    SERVER_ID)   [[ "$2" =~ ^[0-9]{0,9}$ ]] ;;
    KEEP_DAYS)   [[ "$2" =~ ^(0|30|90|180|365|730)$ ]] ;;
    LIM_DOWN|LIM_UP) [[ "$2" =~ ^[0-9]{1,5}$ ]] ;;
    LIM_PING)    [[ "$2" =~ ^[0-9]{1,4}$ ]] ;;
    TOKEN_ID)    [[ "$2" =~ ^[0-9]{1,9}$ ]] ;;
    TOKEN_KIND)  [[ "$2" =~ ^(read|run)$ ]] ;;
    NAME_B64)    [[ "$2" =~ ^[A-Za-z0-9_-]*$ ]] && (( ${#2} <= 200 )) ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------ talking to Speedtest Tracker
b64d() { local s=${1//-/+}; s=${s//_//}; while (( ${#s} % 4 )); do s="$s="; done; printf '%s' "$s" | base64 -d 2>/dev/null; }   # base64url → text
env_set_q() { local v=${2//\\/\\\\}; v=${v//\"/\\\"}; v=${v//\$/\$\$}; env_set "$1" "\"$v\""; }   # a value compose reads literally
env_get_q() { local v; v=$(env_get "$1"); v=${v#\"}; v=${v%\"}; v=${v//\$\$/\$}; v=${v//\\\"/\"}; printf '%s' "${v//\\\\/\\}"; }
st_php() {   # action [arg-json] → st.php's JSON line in ST_OUT; 0 when it says ok
  local a=$1 arg=${2:-"{}"}
  ST_OUT=$({ printf '<?php $ACT = %s; $ARG_B64 = %s; ?>' "$(jq -Rn --arg v "$a" '$v')" "$(jq -Rn --arg v "$(printf '%s' "$arg" | base64 -w0)" '$v')"; cat "$STPHP"; } \
    | docker exec -i -u abc -w /app/www "$SA" php 2>>"$LOG" | tail -n 1)
  jq -e '.ok == true' <<< "$ST_OUT" >/dev/null 2>&1
}
st_msg() { jq -r '.msg // empty' <<< "${ST_OUT:-}" 2>/dev/null | head -c 300; }
me() { jq -cn --arg e "$(env_get ADMIN_EMAIL)" '{email: $e}'; }
scheme() { [[ "$(env_get TLS_SOURCE)" =~ ^(dsm|self)$ ]] && echo https || echo http; }
st_url() { echo "$(scheme)://127.0.0.1:$(env_get HTTP_PORT)"; }
strong_password() { echo "$(rand 5)-$(rand 5)-$(rand 5)-$(rand 5)"; }
unplus() { tr '+' ' ' <<< "$1"; }
mbps() { awk -v b="${1:-0}" 'BEGIN { printf "%.1f", b / 1000000 }'; }
cron_for() {   # every → the cron Speedtest Tracker reads; tests start at this install's own minute, not all at :00
  local m; m=$(env_get SCHED_MIN); m=${m:-17}
  case "$1" in 1h) echo "$m * * * *" ;; 3h) echo "$m */3 * * *" ;; 6h) echo "$m */6 * * *" ;; 12h) echo "$m */12 * * *" ;; 24h) echo "$m 3 * * *" ;; *) echo "" ;; esac
}

# ------------------------------------------------------------ lifecycle hooks
app_first_env() {
  env_set ST_IMAGE lscr.io/linuxserver/speedtest-tracker:latest
  env_set APP_KEY "base64:$(openssl rand -base64 32)"
  env_set ADMIN_EMAIL "${ADMIN_EMAIL:-admin@example.com}"; env_set ADMIN_NAME "${ADMIN_NAME:-Admin}"
  env_set SCHED_MIN $(( RANDOM % 50 + 5 )); env_set EVERY "${EVERY:-6h}"; env_set_q SPEEDTEST_SCHEDULE "$(cron_for "${EVERY:-6h}")"
  env_set SPEEDTEST_SERVERS ""; env_set KEEP_DAYS 0; env_set PUBLIC_DASHBOARD false; env_set DSM_ALERTS 1
  env_set TLS "${TLS:-off}"
  tls_fix_scheme || true
  touch "$VAR/.needs-admin"
}
app_load_env() { SA=$(cname app); }
app_before_up() {
  [[ -n "$(env_get TLS)" ]] || env_set TLS off
  env_set FORCE_HTTPS "$([[ "$(env_get SSL_PROXY)" == 1 ]] && echo true || echo false)"
  setup_tls || say "✗ HTTPS couldn't be set up: $MSG"
}
setup_tls() {   # the certificate where the container's nginx looks (/config/keys), and which of its ports is published
  tls_fix_scheme || true
  tls_prepare config || return 1
  if [[ "$(env_get TLS_SOURCE)" =~ ^(dsm|self)$ ]]; then
    in_volume config rw -- 'mkdir -p /vol/keys && cp /vol/tls/fullchain.pem /vol/keys/cert.crt && cp /vol/tls/privkey.pem /vol/keys/cert.key && chown -R 1000:1000 /vol/keys' </dev/null 2>>"$LOG" \
      || { MSG="The certificate couldn't be put in place for Speedtest Tracker."; return 1; }
    env_set INNER_PORT 443
  else env_set INNER_PORT 80; fi
}
app_health() { [[ "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "$(st_url)/api/healthcheck" 2>/dev/null)" == 200 ]]; }
app_version() { docker inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "$SA" 2>/dev/null | sed -E 's/-ls[0-9]+$//' | tr -cd '0-9A-Za-z.-' | head -c 30; }
app_after_up() { make_admin 120; }
make_admin() {   # [tries] — the first time: the default admin@example.com becomes your account
  [[ -f "$VAR/.needs-admin" ]] || return 0
  local i pw email name; email=$(env_get ADMIN_EMAIL); name=$(unplus "$(env_get ADMIN_NAME)")
  for i in $(seq 1 "${1:-1}"); do app_health && break; sleep 2; done
  app_health || { say "Speedtest Tracker isn't answering yet — your account is made when it does"; return 0; }
  pw=$(strong_password)
  if st_php firstadmin "$(jq -cn --arg n "$name" --arg e "$email" --arg p "$pw" '{name: $n, email: $e, password: $p}')"; then
    leave_secret "Speedtest Tracker ($email)" "$pw" account; say "first start: the default admin@example.com is now $email; the password is shown once in the window"
  elif [[ "$(st_msg)" == nodefault ]]; then say "Speedtest Tracker has no default admin@example.com any more — left as it is"
  else say "✗ your Speedtest Tracker account couldn't be made: $(st_msg) — trying again shortly"; return 0; fi
  rm -f "$VAR/.needs-admin"
}

# ------------------------------------------------------------ what the window shows
app_status() {
  svc_up app || { echo '{"up": false}'; return 0; }
  local data='{}'
  st_php status "$(me)" && data=$ST_OUT
  [[ -s "$VAR/cert.json" ]] || tls_info config
  jq -c --arg url "$(env_get APP_URL)" --arg every "$(env_get EVERY)" --arg cron "$(env_get_q SPEEDTEST_SCHEDULE)" --arg server "$(env_get SPEEDTEST_SERVERS)" \
     --argjson servers "$(cat "$VAR/servers.json" 2>/dev/null || echo null)" --arg keep "$(env_get KEEP_DAYS)" --arg public "$(env_get PUBLIC_DASHBOARD)" --arg alerts "$(env_get DSM_ALERTS)" \
     --arg hdir "$HISTORY_DIR" --arg hat "$(stat -c %Y "$VAR/.history" 2>/dev/null || echo 0)" \
     --arg tls "$(env_get TLS)" --arg tls_source "$(env_get TLS_SOURCE)" --argjson cert "$(cat "$VAR/cert.json" 2>/dev/null || echo null)" \
     'del(.ok) + {up: true, url: $url, every: $every, cron: $cron, server: $server, servers: $servers, keep: ($keep | tonumber? // 0), public: ($public == "true"), alerts: ($alerts == "1"),
                  history: {dir: $hdir, at: ($hat | tonumber)}, tls: {mode: $tls, source: $tls_source, cert: $cert}}' <<< "$data" 2>/dev/null || echo '{"up": true}'
}

# ------------------------------------------------------------ alerts and the history in File Station
check_results() {   # new finished results → DSM notifications (failed, or below the thresholds)
  local seen rows n bad
  seen=$(cat "$VAR/.alert-seen" 2>/dev/null)
  if ! [[ "$seen" =~ ^[0-9]+$ ]]; then   # a new install or a restore: start from the newest result, so old ones aren't news
    st_php since '{"id": 0}' && jq -r '.last' <<< "$ST_OUT" > "$VAR/.alert-seen"; return 0
  fi
  st_php since "$(jq -cn --argjson id "$seen" '{id: $id}')" || return 0
  rows=$(jq -c '.rows' <<< "$ST_OUT"); n=$(jq 'length' <<< "$rows")
  (( n )) || return 0
  jq -r '.rows | last | .id' <<< "$ST_OUT" > "$VAR/.alert-seen"
  [[ "$(env_get DSM_ALERTS)" == 1 ]] || return 0
  bad=$(jq -c '[.[] | select(.status == "failed" or .healthy == false)]' <<< "$rows")
  if (( $(jq 'length' <<< "$bad") > 3 )); then notify speedmany 0 "$(jq 'length' <<< "$bad")"; return 0; fi
  jq -c '.[]' <<< "$bad" | while read -r r; do
    if [[ "$(jq -r .status <<< "$r")" == failed ]]; then notify speedfailed 0 "$(jq -r '.message // "no reason given"' <<< "$r")"
    else notify speedslow 0 "$(mbps "$(jq -r '.down // 0' <<< "$r")")" "$(mbps "$(jq -r '.up // 0' <<< "$r")")" "$(jq -r '.ping // 0' <<< "$r")"; fi
  done
  true
}
write_history() {   # [month…] → "$HISTORY_DIR/YYYY-MM.csv" in the share, one row per test (this month and last, by default)
  local dir="$APP/$HISTORY_DIR" mon tz months; tz=$(env_get TZ); tz=${tz:-UTC}
  months="${*:-$(date +%Y-%m) $(date -d "$(date +%Y-%m-01) -1 day" +%Y-%m)}"
  mkdir -p "$dir"
  for mon in $months; do
      st_php month "$(jq -cn --arg m "$mon" --arg tz "$tz" '{month: $m, tz: $tz}')" || { say "✗ the history for $mon couldn't be read: $(st_msg)"; continue; }
      (( $(jq '.rows | length' <<< "$ST_OUT") )) || continue
      { echo "time,download_mbps,upload_mbps,ping_ms,jitter_ms,packet_loss_pct,server,isp,status,healthy,scheduled,result_url"
        jq -r '.rows[] | [.local, ((.down // 0) / 1000000 * 10 | round / 10), ((.up // 0) / 1000000 * 10 | round / 10), .ping, .jitter, .loss, .server, .isp, .status,
               (if .healthy == null then "" else (.healthy | tostring) end), .scheduled, .url] | @csv' <<< "$ST_OUT"; } > "$dir/.$mon.csv.tmp" \
        && mv "$dir/.$mon.csv.tmp" "$dir/$mon.csv"
  done
  printf 'One file per month, one row per speed test, written by the Speedtest Tracker package in DSM.\nSpeeds in megabits per second; times in %s. Last written: %s\n' "$tz" "$(date '+%Y-%m-%d %H:%M')" > "$dir/README.txt"
  chown -R "$HOST_UID:$HOST_GID" "$dir" 2>/dev/null || true
  touch "$VAR/.history"
}
app_tick() {
  make_admin 1
  svc_up app || return 0
  fresh "$VAR/.alert-check" 50 || { touch "$VAR/.alert-check"; check_results || true; }
  fresh "$VAR/.history" 3600 || write_history || true
  fresh "$VAR/.cert-check" 86400 && return 0; touch "$VAR/.cert-check"
  tls_refresh_dsm config
  [[ "$CERT_REFRESH" == changed ]] && { setup_tls && docker restart "$SA" >> "$LOG" 2>&1; } || true
  return 0
}

# ------------------------------------------------------------ settings, logs, storage, backups, report
app_settings() {   # HTTPS, and Laravel told it's behind HTTPS when DSM's reverse proxy does it
  [[ -n "${TLS:-}" ]] && env_set TLS "$TLS"
  env_set FORCE_HTTPS "$([[ "$(env_get SSL_PROXY)" == 1 ]] && echo true || echo false)"
  setup_tls || return 1
  return 0
}
app_logs() { :; }
app_storage() {
  in_volume config ro -- 'printf "database\t%s\n" "$(du -sm /vol/database.sqlite 2>/dev/null | cut -f1)"; printf "logs\t%s\n" "$(du -sm /vol/log 2>/dev/null | cut -f1)"; true' </dev/null 2>/dev/null \
    | jq -R -s -c --arg h "$(du -sm "$APP/$HISTORY_DIR" 2>/dev/null | cut -f1)" 'split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1] | tonumber? // 0)}) | from_entries | . + {history: ($h | tonumber? // 0)}' 2>/dev/null || echo "{}"
}
app_backup() {   # dir — a consistent copy of the SQLite database, and the rest of /config
  in_volume config ro -- 'sqlite3 -readonly /vol/database.sqlite ".backup /tmp/db.sqlite" && gzip -c /tmp/db.sqlite' > "$1/database.sqlite.gz" 2>>"$LOG" </dev/null \
    && gzip -t "$1/database.sqlite.gz" 2>/dev/null || { say "✗ the database couldn't be copied"; return 1; }
  in_volume config ro -- 'tar -C /vol -czf - --exclude=./log --exclude=./database.sqlite --exclude=./database.sqlite-journal .' > "$1/config.tar.gz" 2>>"$LOG" </dev/null \
    && tar -tzf "$1/config.tar.gz" >/dev/null 2>&1 || { say "✗ Speedtest Tracker's files didn't tar"; return 1; }
}
app_restore() {   # dir — the core has stopped the containers
  [[ -s "$1/database.sqlite.gz" && -f "$1/config.tar.gz" ]] || { MSG="That backup has no database or files."; return 1; }
  in_volume config rw -- 'find /vol -mindepth 1 -delete && tar -C /vol -xzf -' < "$1/config.tar.gz" 2>>"$LOG" || { MSG="Speedtest Tracker's files didn't unpack."; return 1; }
  in_volume config rw -- 'gzip -dc > /vol/database.sqlite && chown 1000:1000 /vol/database.sqlite' < "$1/database.sqlite.gz" 2>>"$LOG" || { MSG="The database didn't unpack."; return 1; }
  rm -f "$VAR/.alert-seen" "$VAR/.history"   # set again from the restored results, so old ones aren't news
}
app_report() {
  local s; st_php status "$(me)" && s=$ST_OUT || s='{}'
  echo "== results: $(jq -r '.total // "?"' <<< "$s") in all, $(jq -r '.failed7 // "?"' <<< "$s") failed in the last 7 days"
  echo "== averages (7 days): $(jq -r '.avg.d7 | "\(.n) tests, down \(.down / 1000000 | floor) Mbps, up \(.up / 1000000 | floor) Mbps, ping \(.ping) ms"' <<< "$s" 2>/dev/null)"
  echo "== schedule: $(env_get EVERY) ($(env_get_q SPEEDTEST_SCHEDULE)), server: $(env_get SPEEDTEST_SERVERS || true), keep: $(env_get KEEP_DAYS) days, public dashboard: $(env_get PUBLIC_DASHBOARD)"
  echo "== thresholds: $(jq -c '.limits' <<< "$s" 2>/dev/null), DSM alerts: $(env_get DSM_ALERTS)"
  echo "== API tokens: $(jq -r '.tokens | length' <<< "$s" 2>/dev/null)"
  echo; echo "== HTTPS"; echo "mode $(env_get TLS), in use: $(env_get TLS_SOURCE)"; jq -c 'del(.names)' "$VAR/cert.json" 2>/dev/null
  echo; echo "== recent results"; jq -r '.recent[]? | "\(.at | todate)  \(.status)  down \((.down // 0) / 1000000 | floor)  up \((.up // 0) / 1000000 | floor)  ping \(.ping)  \(.server)"' <<< "$s" 2>/dev/null
  :
}

# ------------------------------------------------------------ the window's actions
recreate() { compose up -d >> "$LOG" 2>&1 && wait_ready 180; }   # Speedtest Tracker reads these settings from its environment
app_act() {   # action (request vars are set)
  local name kind ab
  case "$1" in
    runnow)
      st_php run "$(jq -cn --arg e "$(env_get ADMIN_EMAIL)" --arg s "$(env_get SPEEDTEST_SERVERS)" '{email: $e, server: $s}')" || { MSG=$(st_msg); MSG=${MSG:-"The test couldn't be started."}; return 1; }
      MSG="A speed test is running — it takes about half a minute." ;;
    schedule)
      env_set EVERY "${EVERY:-6h}"; env_set_q SPEEDTEST_SCHEDULE "$(cron_for "${EVERY:-6h}")"
      env_set SPEEDTEST_SERVERS "${SERVER_ID:-}"; env_set KEEP_DAYS "${KEEP_DAYS:-0}"
      recreate || { MSG="Speedtest Tracker didn't come back — see the log."; return 1; }
      MSG="Saved: $(case "${EVERY:-6h}" in 1h) echo "a test every hour" ;; 3h) echo "a test every 3 hours" ;; 6h) echo "a test every 6 hours" ;; 12h) echo "tests twice a day" ;; 24h) echo "a test once a day" ;; *) echo "tests only when you ask" ;; esac), $([[ -n "${SERVER_ID:-}" ]] && echo "server $SERVER_ID" || echo "the nearest server"), $([[ "${KEEP_DAYS:-0}" == 0 ]] && echo "results kept for good" || echo "results kept for $KEEP_DAYS days")." ;;
    servers)
      st_php servers || { MSG=$(st_msg); return 1; }
      jq -c '.servers' <<< "$ST_OUT" > "$VAR/servers.json"; MSG="$(jq '.servers | length' <<< "$ST_OUT") servers near this Synology." ;;
    limits)
      st_php limits "$(jq -cn --argjson on "${ON:-0}" --argjson d "${LIM_DOWN:-0}" --argjson u "${LIM_UP:-0}" --argjson p "${LIM_PING:-0}" '{on: ($on == 1), down: $d, up: $u, ping: $p}')" || { MSG=$(st_msg); return 1; }
      MSG=$([[ "${ON:-0}" == 1 ]] && echo "Results now have to reach ${LIM_DOWN:-0} Mbps down, ${LIM_UP:-0} Mbps up and ${LIM_PING:-0} ms ping or better (0 isn't checked)." || echo "Thresholds are off: every result counts as fine.") ;;
    alerts) env_set DSM_ALERTS "${ON:-0}"; MSG=$([[ "${ON:-0}" == 1 ]] && echo "DSM tells administrators when a test fails or misses the thresholds." || echo "No DSM notifications about results.") ;;
    public)
      env_set PUBLIC_DASHBOARD "$([[ "${ON:-0}" == 1 ]] && echo true || echo false)"
      recreate || { MSG="Speedtest Tracker didn't come back — see the log."; return 1; }
      MSG=$([[ "${ON:-0}" == 1 ]] && echo "Anyone who can reach Speedtest Tracker can see the dashboard now, without signing in." || echo "The dashboard needs a sign-in again.") ;;
    mypw)
      local pw; pw=$(strong_password)
      st_php mypw "$(jq -cn --arg e "$(env_get ADMIN_EMAIL)" --arg p "$pw" '{email: $e, password: $p}')" || { MSG=$(st_msg); return 1; }
      leave_secret "Speedtest Tracker ($(env_get ADMIN_EMAIL))" "$pw" account; MSG="Your new password is shown below, once." ;;
    token)
      name=$(b64d "${NAME_B64:-}" | tr -d '\000-\037' | cut -c1-60); [[ -n "$name" ]] || name="DSM token"
      kind=${TOKEN_KIND:-read}; ab=$([[ "$kind" == run ]] && echo '["results:read","speedtests:run","ookla:list-servers"]' || echo '["results:read"]')
      st_php token "$(jq -cn --arg e "$(env_get ADMIN_EMAIL)" --arg n "$name" --argjson a "$ab" '{email: $e, name: $n, abilities: $a}')" || { MSG=$(st_msg); return 1; }
      leave_secret "API token \"$name\"" "$(jq -r .token <<< "$ST_OUT")" account; MSG="The token \"$name\" is shown below, once." ;;
    untoken)
      st_php untoken "$(jq -cn --arg e "$(env_get ADMIN_EMAIL)" --argjson id "${TOKEN_ID:-0}" '{email: $e, id: $id}')" || { MSG=$(st_msg); return 1; }
      MSG="The token was removed; anything using it stops working." ;;
    historynow) write_history || true; MSG="The history in the speedtest shared folder → $HISTORY_DIR is up to date." ;;
    refreshcert)
      tls_refresh_dsm config; setup_tls || return 1; docker restart "$SA" >> "$LOG" 2>&1; wait_ready 120
      MSG=$([[ "$(env_get TLS_SOURCE)" == dsm ]] && echo "DSM's certificate was read again." || echo "A new self-signed certificate is in use.") ;;
    *) MSG="Unknown request."; return 1 ;;
  esac
}
