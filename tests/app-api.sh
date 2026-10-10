# Speedtest Tracker's CGI checks (sourced by chassis/tests/test-api.sh).
expect "runnow" 202 "$(post "$me" runnow 'action=runnow')"; request_is "runnow request" "ACTION='runnow'
BY='$me'"
expect "schedule good" 202 "$(post "$me" schedule 'action=schedule&every=3h&server=52523&keep=90')"; request_is "schedule request" "ACTION='schedule'
EVERY='3h'
SERVER_ID='52523'
KEEP_DAYS='90'
BY='$me'"
expect "schedule nearest, off" 202 "$(post "$me" schedule 'action=schedule&every=off&server=&keep=0')"; rm -f "$CHASSIS_VAR/request"
expect "schedule bad every" 400 "$(post "$me" schedule 'action=schedule&every=5m&server=&keep=0')"
expect "schedule bad server" 400 "$(post "$me" schedule 'action=schedule&every=1h&server=1%3Bx&keep=0')"
expect "schedule bad keep" 400 "$(post "$me" schedule 'action=schedule&every=1h&server=&keep=7')"
expect "limits good" 202 "$(post "$me" limits 'action=limits&on=1&down=100&up=20&ping=40')"; request_is "limits request" "ACTION='limits'
ON='1'
LIM_DOWN='100'
LIM_UP='20'
LIM_PING='40'
BY='$me'"
expect "limits on with nothing" 400 "$(post "$me" limits 'action=limits&on=1&down=0&up=0&ping=0')"
expect "limits off" 202 "$(post "$me" limits 'action=limits&on=0&down=&up=&ping=')"; rm -f "$CHASSIS_VAR/request"
expect "limits not a number" 400 "$(post "$me" limits 'action=limits&on=1&down=1e9&up=0&ping=0')"
expect "public on" 202 "$(post "$me" public 'action=public&on=1')"; rm -f "$CHASSIS_VAR/request"
expect "alerts bad" 400 "$(post "$me" alerts 'action=alerts&on=yes')"
expect "token" 202 "$(post "$me" token 'action=token&name=Home%20%22dash%22%20%26%20co&kind=run')"
grep -q "^NAME_B64='SG9tZSAiZGFzaCIgJiBjbw'$" "$CHASSIS_VAR/request" && { (( pass++ )); echo "  ok   the token name travels base64url"; } || { (( fail++ )); echo "  FAIL token request: $(tr '\n' ' ' < "$CHASSIS_VAR/request")"; }
rm -f "$CHASSIS_VAR/request"
expect "token no name" 400 "$(post "$me" token 'action=token&name=&kind=read')"
expect "token bad kind" 400 "$(post "$me" token 'action=token&name=x&kind=admin')"
expect "untoken bad id" 400 "$(post "$me" untoken 'action=untoken&id=1%20OR%201')"
