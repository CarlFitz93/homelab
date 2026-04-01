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

echo "Provisioning complete for $HOSTNAME"
