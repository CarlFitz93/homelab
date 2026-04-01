#!/bin/bash
set -e  # Exit on any error

HOSTNAME=$1  # Pass hostname as argument e.g. ./base_provision.sh vm1

# --- Hostname ---
hostnamectl set-hostname "$HOSTNAME"

# --- Updates & packages ---
apt update && apt upgrade -y
apt install -y \
    curl \
    wget \
    git \
    ufw \
    fail2ban \
    htop \
    net-tools \
    unattended-upgrades


# --- UFW ---
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw --force enable

# --- fail2ban ---
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 3
ignoreip = 127.0.0.1/8 ::1 192.168.0.0/24

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
EOF

systemctl enable fail2ban
systemctl start fail2ban

# --- SSH hardening ---
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Drop any cloud-init SSH override
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf

systemctl restart ssh

# --- Timezone ---
timedatectl set-timezone Europe/London

# --- Log rotation script ---
mkdir -p /var/log/homelab/archive

cat > /usr/local/bin/rotate_logs.sh << 'EOF'
#!/bin/bash
set -e

LOGDIR="/var/log/homelab"
ARCHIVE="/var/log/homelab/archive"
DATE=$(date +%Y-%m-%d)

mkdir -p "$ARCHIVE"

find "$LOGDIR" -maxdepth 1 -name "*.log" -mtime +1 | while read -r logfile; do
    gzip -c "$logfile" > "$ARCHIVE/$(basename $logfile)-$DATE.gz"
    > "$logfile"
    echo "$(date): Rotated $logfile" >> /var/log/homelab/rotation.log
done
EOF

chmod +x /usr/local/bin/rotate_logs.sh

# --- Systemd service ---
cat > /etc/systemd/system/log-rotate.service << 'EOF'
[Unit]
Description=Homelab log rotation
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rotate_logs.sh
User=root
EOF

# --- Systemd timer ---
cat > /etc/systemd/system/log-rotate.timer << 'EOF'
[Unit]
Description=Run log rotation nightly
Requires=log-rotate.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable log-rotate.timer
systemctl start log-rotate.timer

echo "Provisioning complete for $HOSTNAME"
