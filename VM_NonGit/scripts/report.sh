#!/usr/bin/env bash
set -u
LOG_FILE="/var/log/agent-app/monitor.log"

echo
echo "====== STATISTICS REPORT ======"
if [[ ! -s "$LOG_FILE" ]]; then
  echo "No monitor data found."
  exit 0
fi

awk '
{
  ts=$1" "$2; gsub(/\[/,"",ts); gsub(/\]/,"",ts)
  for(i=1;i<=NF;i++){
    if($i ~ /^CPU:/){cpu=$i; gsub(/CPU:|%/,"",cpu)}
    if($i ~ /^MEM:/){mem=$i; gsub(/MEM:|%/,"",mem)}
  }
  csum+=cpu; msum+=mem; n++
  if(n==1 || cpu>cmax){cmax=cpu; cmax_t=ts}
  if(n==1 || cpu<cmin){cmin=cpu; cmin_t=ts}
  if(n==1 || mem>mmax){mmax=mem; mmax_t=ts}
  if(n==1 || mem<mmin){mmin=mem; mmin_t=ts}
}
END{
  if(n==0){print "No valid samples."; exit}
  printf "[CPU]\nAverage : %.1f%%\nMaximum : %.1f%% at %s\nMinimum : %.1f%% at %s\n", csum/n, cmax, cmax_t, cmin, cmin_t
  printf "[Memory]\nAverage : %.1f%%\nMaximum : %.1f%% at %s\nMinimum : %.1f%% at %s\n", msum/n, mmax, mmax_t, mmin, mmin_t
  printf "[Samples]\nData Points: %d samples\n", n
}' "$LOG_FILE"
