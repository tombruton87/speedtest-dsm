    echo "ADMIN_EMAIL='$(printf '%s' "${wizard_admin_email:-}" | tr -cd 'A-Za-z0-9._+@-' | head -c 120)'"
    echo "ADMIN_NAME='$(printf '%s' "${wizard_admin_name:-Admin}" | tr -cd 'A-Za-z0-9 ._@-' | sed 's/^ *//; s/ *$//' | tr -s ' ' '+' | head -c 60)'"
    echo "EVERY='$(if [ "${wizard_every_1h:-false}" = true ]; then echo 1h; elif [ "${wizard_every_24h:-false}" = true ]; then echo 24h; elif [ "${wizard_every_off:-false}" = true ]; then echo off; else echo 6h; fi)'"
    echo "TLS='$(if [ "${wizard_tls_dsm:-false}" = true ]; then echo dsm; elif [ "${wizard_tls_self:-false}" = true ]; then echo self; else echo off; fi)'"
