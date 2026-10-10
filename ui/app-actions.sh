# Speedtest Tracker's actions, validated by the CGI before they become a request file.
# Free text (a token's name) travels base64url-encoded: the request file allows only a few characters.
b64u() { printf '%s' "$1" | base64 -w0 | tr '+/' '-_' | tr -d '='; }
app_cgi_post() {   # action body → sets $lines, or error
  local a=$1 body=$2 v every server keep down up ping name kind id
  case "$a" in
    runnow|servers|mypw|historynow|refreshcert) lines="ACTION='$a'" ;;
    schedule)
      every=$(param every "$body"); server=$(param server "$body"); keep=$(param keep "$body")
      [[ "$every" =~ ^(1h|3h|6h|12h|24h|off)$ ]] || error "400 Bad Request" "Pick how often."
      [[ "$server" =~ ^[0-9]{0,9}$ ]] || error "400 Bad Request" "Pick a server, or the nearest."
      [[ "$keep" =~ ^(0|30|90|180|365|730)$ ]] || error "400 Bad Request" "Pick how long results are kept."
      lines="ACTION='schedule'
EVERY='$every'
SERVER_ID='$server'
KEEP_DAYS='$keep'" ;;
    limits)
      v=$(param on "$body"); down=$(param down "$body"); up=$(param up "$body"); ping=$(param ping "$body")
      [[ "$v" =~ ^[01]$ ]] || error "400 Bad Request" "On or off."
      [[ "${down:-0}" =~ ^[0-9]{1,5}$ && "${up:-0}" =~ ^[0-9]{1,5}$ ]] || error "400 Bad Request" "Speeds are whole megabits per second, like 100."
      [[ "${ping:-0}" =~ ^[0-9]{1,4}$ ]] || error "400 Bad Request" "Ping is whole milliseconds, like 40."
      [[ "$v" == 1 && "${down:-0}${up:-0}${ping:-0}" =~ ^0+$ ]] && error "400 Bad Request" "Give at least one threshold, or turn them off."
      lines="ACTION='limits'
ON='$v'
LIM_DOWN='${down:-0}'
LIM_UP='${up:-0}'
LIM_PING='${ping:-0}'" ;;
    alerts|public) v=$(param on "$body"); [[ "$v" =~ ^[01]$ ]] || error "400 Bad Request" "On or off."; lines="ACTION='$a'
ON='$v'" ;;
    token)
      name=$(decode "$(param name "$body")"); kind=$(param kind "$body")
      [[ -n "$name" && ${#name} -le 60 ]] || error "400 Bad Request" "Give the token a name, like Homepage."
      [[ "$kind" =~ ^(read|run)$ ]] || error "400 Bad Request" "Pick what it may do."
      lines="ACTION='token'
NAME_B64='$(b64u "$name")'
TOKEN_KIND='$kind'" ;;
    untoken) id=$(param id "$body"); [[ "$id" =~ ^[0-9]{1,9}$ ]] || error "400 Bad Request" "Pick a token."; lines="ACTION='untoken'
TOKEN_ID='$id'" ;;
  esac
}
app_cgi_settings() {   # body → appends TLS to $lines, or errors
  local tls; tls=$(param tls "$1")
  [[ -z "$tls" ]] && return 0
  [[ "$tls" =~ ^(dsm|self|off)$ ]] || error "400 Bad Request" "HTTPS is DSM's certificate, self-signed, or off."
  lines="$lines
TLS='$tls'"
}
