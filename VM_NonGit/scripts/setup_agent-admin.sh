#!/usr/bin/env bash

# =========================
# agent-admin Check
# =========================
# This script must be run as agent-admin.
# It performs:
# - cron registration
# - agent-app execution

set -euo pipefail

if [[ "$(id -un)" != "agent-admin" ]]; then
  echo "[ERROR] setup_agent-admin.sh must be run as agent-admin."
  exit 1
fi

# =========================
# Load Environment Variables
# =========================

source /etc/profile.d/agent-app.sh

# =========================
# Permission Setup
# =========================

chmod +x "$AGENT_HOME/app/agent-app"
chmod +x "$AGENT_HOME/bin/"*.sh

# =========================
# API Key Setup
# =========================

echo 'agent_api_key_test' > "$AGENT_HOME/api_keys/t_secret.key"

chmod 660 "$AGENT_HOME/api_keys/t_secret.key"

# =========================
# Runtime Log Setup
# =========================

touch /tmp/agent_app.log
chmod 664 /tmp/agent_app.log

# =========================
# Cron Registration
# =========================
# monitor.sh:
#   every minute
#
# log_archive.sh:
#   every day at 03:00

(
  crontab -l 2>/dev/null | grep -v monitor.sh || true
  echo "* * * * * . /etc/profile.d/agent-app.sh; $AGENT_HOME/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1"
) | crontab -

(
  crontab -l 2>/dev/null | grep -v log_archive.sh || true
  echo "0 3 * * * . /etc/profile.d/agent-app.sh; $AGENT_HOME/bin/log_archive.sh >> /var/log/agent-app/archive.log 2>&1"
) | crontab -

# =========================
# Start agent-app
# =========================

if ! pgrep -f "$AGENT_HOME/app/agent-app" >/dev/null 2>&1; then

  cd "$AGENT_HOME/app"

  nohup ./agent-app >> /tmp/agent_app.log 2>&1 < /dev/null &

fi

# =========================
# Setup Complete
# =========================

cat <<MSG

setup_agent-admin.sh completed.

Check process:

  ps -ef | grep agent-app

Check monitor:

  $AGENT_HOME/bin/monitor.sh

MSG