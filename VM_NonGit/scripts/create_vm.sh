#!/usr/bin/env bash
set -euo pipefail

VM_NAME=${VM_NAME:-ubuntu-intel}
IMAGE=${IMAGE:-ubuntu:noble}
ARCH=${ARCH:-amd64}

SSH_PORT=${SSH_PORT:-20022}
AGENT_PORT=${AGENT_PORT:-15034}

HOST_PROJECT_DIR=${HOST_PROJECT_DIR:-"$HOME/Linux-Monitoring_LEAK/VM_NonGit"}
AGENT_HOME=/home/agent-admin/agent-app-leak
AGENT_ADMIN_PASSWORD=${AGENT_ADMIN_PASSWORD:-1234}


if ! command -v orb >/dev/null 2>&1; then
  echo "[ERROR] orb command not found."
  exit 1
fi

if orb list | awk '{print $1}' | grep -qx "$VM_NAME"; then
  echo "[INFO] VM already exists: $VM_NAME"
else
  echo "[INFO] Creating VM: $VM_NAME"
  orb create --arch "$ARCH" "$IMAGE" "$VM_NAME"
fi

orb -m "$VM_NAME" sudo bash -lc "
set -euo pipefail

apt update
apt install -y \
  cron \
  openssh-server \
  ufw \
  procps \
  net-tools \
  iproute2 \
  gzip \
  logrotate
apt clean

groupadd -f agent-common
groupadd -f agent-core

if ! id agent-admin >/dev/null 2>&1; then
  useradd -m -s /bin/bash -g agent-common -G agent-core agent-admin
else
  usermod -g agent-common -aG agent-core agent-admin
fi

echo "agent-admin:${AGENT_ADMIN_PASSWORD}" | chpasswd

if ! id agent-dev >/dev/null 2>&1; then
  useradd -m -s /bin/bash -g agent-common -G agent-core agent-dev
else
  usermod -g agent-common -aG agent-core agent-dev
fi

if ! id agent-test >/dev/null 2>&1; then
  useradd -m -s /bin/bash -g agent-common agent-test
else
  usermod -g agent-common agent-test
fi

mkdir -p '$AGENT_HOME'/{app,bin,api_keys,upload_files}
mkdir -p /var/log/agent-app-leak
mkdir -p /var/log/monitor/agent-app-leak/archive

chown agent-admin:agent-core /home/agent-admin
chmod 750 /home/agent-admin

chown -R agent-admin:agent-core '$AGENT_HOME'
chmod 750 '$AGENT_HOME'

chown agent-test:agent-common '$AGENT_HOME/upload_files'
chmod 770 '$AGENT_HOME/upload_files'

chown -R agent-admin:agent-core '$AGENT_HOME/api_keys'
chmod 770 '$AGENT_HOME/api_keys'

chown -R agent-admin:agent-core /var/log/agent-app-leak
chmod 770 /var/log/agent-app-leak

chown -R agent-admin:agent-common /var/log/monitor
chmod -R 770 /var/log/monitor
"

orb -m "$VM_NAME" sudo bash -lc "
tee /etc/profile.d/agent-app-leak.sh >/dev/null <<EOF
export AGENT_HOME=$AGENT_HOME
export AGENT_PORT=$AGENT_PORT
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys
export AGENT_LOG_DIR=/var/log/agent-app-leak
export LOG_FILE=/var/log/agent-app-leak/monitor.log
export APP_NAME=agent-app-leak
export APP_PORT="15034"

export MEMORY_LIMIT=256
export CPU_MAX_OCCUPY=50
export MULTI_THREAD_ENABLE=True
export CPU_THRESHOLD=${CPU_THRESHOLD:-80}
export MEM_THRESHOLD=${MEM_THRESHOLD:-80}
export DISK_THRESHOLD=${DISK_THRESHOLD:-80}
export SYS_CPU_THRESHOLD=${SYS_CPU_THRESHOLD:-80}
export SYS_MEM_THRESHOLD=${SYS_MEM_THRESHOLD:-80}

EOF

chown agent-admin:agent-common /etc/profile.d/agent-app-leak.sh
chmod 644 /etc/profile.d/agent-app-leak.sh
"

orb -m "$VM_NAME" sudo bash -lc "
sed -i 's/^#\\?Port .*/Port $SSH_PORT/' /etc/ssh/sshd_config
sed -i 's/^#\\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#\\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config

systemctl daemon-reload || true
systemctl stop ssh.socket || true
systemctl disable ssh.socket || true
systemctl restart ssh || systemctl restart sshd

ufw allow '${SSH_PORT}/tcp' || true
ufw allow '${AGENT_PORT}/tcp' || true
ufw --force enable || true

cat > /etc/logrotate.d/agent-app-leak <<EOF
/var/log/agent-app-leak/monitor.log {
    size 10M
    rotate 10
    compress
    missingok
    notifempty
    copytruncate
}
EOF

chmod 644 /etc/logrotate.d/agent-app-leak

systemctl enable cron || true
systemctl restart cron || true
"

# agent-admin 에게 ufw 사용 권한 부여(sudo)
orb -m "$VM_NAME" sudo bash -lc "
cat > /etc/sudoers.d/agent-admin-ufw <<'EOF'
agent-admin ALL=(root) NOPASSWD: /usr/sbin/ufw status, /usr/sbin/ufw status verbose, /usr/sbin/ufw status numbered
EOF

chmod 440 /etc/sudoers.d/agent-admin-ufw
visudo -cf /etc/sudoers.d/agent-admin-ufw
"

# IP 파싱
VM_IP="$(orb -m "$VM_NAME" hostname -I | awk '{print $1}')"

echo "[INFO] Removing old SSH host key..."
ssh-keygen -R "[$VM_IP]:$SSH_PORT" >/dev/null 2>&1 || true

echo "[INFO] Copying files by scp..."

scp -P "$SSH_PORT" "$HOST_PROJECT_DIR/app/agent-app-leak" \
  agent-admin@"$VM_IP":"$AGENT_HOME/app/agent-app-leak"

scp -P "$SSH_PORT" "$HOST_PROJECT_DIR/app/agent-app-leak" \
  agent-admin@"$VM_IP":"$AGENT_HOME/app/agent-app-leak"

scp -P "$SSH_PORT" "$HOST_PROJECT_DIR/scripts/monitor.sh" \
  agent-admin@"$VM_IP":"$AGENT_HOME/bin/monitor.sh"

scp -P "$SSH_PORT" "$HOST_PROJECT_DIR/scripts/report.sh" \
  agent-admin@"$VM_IP":"$AGENT_HOME/bin/report.sh"

scp -P "$SSH_PORT" "$HOST_PROJECT_DIR/scripts/log_archive.sh" \
  agent-admin@"$VM_IP":"$AGENT_HOME/bin/log_archive.sh"

scp -P "$SSH_PORT" "$HOST_PROJECT_DIR/scripts/setup_agent-admin.sh" \
  agent-admin@"$VM_IP":"$AGENT_HOME/bin/setup_agent-admin.sh"

echo "[INFO] Fixing permissions after scp..."

orb -m "$VM_NAME" sudo bash -lc "
chmod +x '$AGENT_HOME/app/agent-app-leak'
chmod +x '$AGENT_HOME/bin/'*.sh
chown -R agent-admin:agent-core '$AGENT_HOME/app' '$AGENT_HOME/bin'
"

cat <<MSG

VM setup completed.

Next command:

  ssh agent-admin@${VM_IP} -p ${SSH_PORT}

Then run:

  cd ~/agent-app-leak/bin
  ./setup_agent-admin.sh

MSG