#!/bin/bash
# Long-term verification monitor for skillmango (RailDock)
# Checks every 60s: core file presence, dompdf integrity, index.php/.htaccess
# backdoor markers, site health, OOM. Appends one line per check.
C=skillmango-wordpress.web.1
VOL=/var/lib/docker/volumes/f7e2ef34c60b69a2e4a005045f3facd66b060b8002e264a852be993cc4896a73/_data
INDEX_MD5=926dd0f95df723f9ed934eb058882cc8
HTACCESS_MD5=1a29d38aa42fa9e1e5a9db0a6eda69bb
CHECK_FILES="wp-includes/compat-utf8.php wp-includes/class-wp-block-processor.php wp-includes/IXR/class-IXR-server.php wp-includes/html-api/class-wp-html-doctype-info.php wp-includes/html-api/class-wp-html-processor.php"
DOM_FILES="lib/Cpdf.php src/Adapter/CPDF.php src/Adapter/PDFLib.php"
DOM_BASE=/var/lib/dokku/data/storage/wordpress-content/plugins/woocommerce-pdf-invoices-packing-slips/vendor/strauss/dompdf/dompdf

while true; do
  ts=$(date +%Y-%m-%dT%H:%M:%S)
  problems=""

  for f in $CHECK_FILES; do
    [ -f "$VOL/$f" ] || problems="$problems MISSING_CORE:$f"
  done

  for f in $DOM_FILES; do
    [ -f "$DOM_BASE/$f" ] || problems="$problems MISSING_DOMPDF:$f"
  done

  idx=$(md5sum "$VOL/index.php" 2>/dev/null | cut -d" " -f1)
  [ "$idx" = "$INDEX_MD5" ] || problems="$problems INDEX_CHANGED:$idx"

  ht=$(md5sum /var/lib/dokku/data/storage/wordpress-content/.htaccess 2>/dev/null | cut -d" " -f1)
  [ "$ht" = "$HTACCESS_MD5" ] || problems="$problems HTACCESS_CHANGED:$ht"

  code=$(curl -4 -s -o /dev/null -w "%{http_code}" -H "Host: skillmango.co" http://127.0.0.1/ --max-time 15 2>/dev/null)
  [ "$code" = "200" ] || problems="$problems HTTP:$code"

  oom=$(dmesg 2>/dev/null | grep -c "Killed process.*apache2")

  if [ -z "$problems" ]; then
    echo "$ts STATUS:OK oom_total=$oom"
  else
    echo "$ts STATUS:ALERT oom_total=$oom$problems"
  fi
  sleep 60
done
