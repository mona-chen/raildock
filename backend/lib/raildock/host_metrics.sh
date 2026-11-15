#!/bin/sh
# One bounded read of kernel counters, no package install or persistent process.
set -eu
export LC_ALL=C
cpu() { awk '/^cpu / {idle=$5+$6; total=0; for(i=2;i<=9;i++)total+=$i; printf "%.0f %.0f\n",total,idle; exit}' /proc/stat; }
first=$(cpu)
sleep 1
second=$(cpu)
printf 'cpu '
printf '%s %s\n' "$first" "$second" | awk '{d=$3-$1; if(d<=0)exit 1; printf "%.4f\n",100*(d-($4-$2))/d}'
printf 'memory '
awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2; found=1} END{if(t<=0 || !found)exit 1; printf "%.4f\n",100*(t-a)/t}' /proc/meminfo
printf 'disk '
df -Pk / | awk 'NR==2{gsub(/%/,"",$5); print $5}'
printf 'load '
awk '{print $1}' /proc/loadavg
printf 'uptime_seconds '
awk '{print $1}' /proc/uptime
printf 'network_rx '
awk -F ':' 'NR>2 {gsub(/[[:space:]]/,"",$1); if($1!="lo"){split($2,a," "); n+=a[1]}} END{printf "%.0f\n",n}' /proc/net/dev
printf 'network_tx '
awk -F ':' 'NR>2 {gsub(/[[:space:]]/,"",$1); if($1!="lo"){split($2,a," "); n+=a[9]}} END{printf "%.0f\n",n}' /proc/net/dev
