#!/usr/bin/env bash

# Config Options

SSH_PORT=1200

WANT_PKGS=(
  curl
  dnsutils
  file
  htop
  iputils-ping
  nano
)

LOCALES=(
  en_AU
  en_US
)


# Implementation

# add required packages
WANT_PKGS+=(
  grub-pc
  nftables
  locales
  apparmor
  apt-utils
  bash-completion
  bsdmainutils
  ca-certificates # Security
  cloud-init
  console-setup   # Sets up the console
  dbus            # IPC
  discover        # Hardware iteration
  dmidecode       # Hardware iteration
  ifupdown        # Internet access
  isc-dhcp-client # Internet access
  libnss-systemd  # User accounting
  libpam-systemd  # User accounting
  ntp             # Security
  openssh-server
  publicsuffix    # Security
  rdnssd          # Internet access
  readline-common # Dialog
  resolvconf
  tzdata 
  unattended-upgrades
  whiptail        # Dialogs
  xdg-user-dirs
)

# Stubbon package needs forced rm
HATE_PKGS=(
  ufw
)

# Locale Setup
grep -E '^('"$(IFS=\|;echo "${LOCALES[*]}")"')\b' < /usr/share/i18n/SUPPORTED > /etc/locale.gen
locale-gen

# SSH Setup
mkdir -p /etc/ssh/
cat > /etc/ssh/sshd_config << EOF
AcceptEnv *
AuthenticationMethods publickey
ClientAliveInterval 10
DebianBanner no
HostKeyAlgorithms ssh-ed25519
PermitRootLogin yes
Port $SSH_PORT
PrintMotd no
UsePAM yes
EOF
systemctl daemon-reload
ssh-keygen -lvf /etc/ssh/ssh_host_ed25519_key >> /etc/issue

# Apt setup

cat > /etc/apt/apt.conf.d/90no-additional-packages << 'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::AutoRemove::RecommendsImportant "false";
APT::AutoRemove::SuggestsImportant "false";
EOF
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Origins-Pattern {
        "o=${distro_id},a=stable";
        "o=${distro_id},a=stable-updates";
};
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "false";
Unattended-Upgrade::Remove-New-Unused-Dependencies "false";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
EOF

apt-get -q --yes update
apt-get -q --yes upgrade
dpkg-query -Wf '${Essential}\t${Package}\n' | grep ^no | cut -f2 | xargs apt-mark auto
apt-get -q --yes purge "${HATE_PKGS[@]}"
apt-get -q --yes install "${WANT_PKGS[@]}"
apt-get -q --yes --purge autoremove

# Firewall
cat > /etc/nftables.conf << EOF
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
	chain input {
		type filter hook input priority 0; policy drop;
		iif lo accept
		ct state invalid drop
		ct state { established, related } accept
		icmpv6 type { nd-neighbor-solicit, nd-router-advert, nd-neighbor-advert } accept
		# SSH
		ct state new tcp dport $SSH_PORT accept
		# HTTP/S
		# ct state new tcp dport { 80, 443 } accept
	}
}
EOF
systemctl enable --now nftables

# Console Setup
mkdir /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --login-pause --noclear %I $TERM
EOF
systemctl daemon-reload
systemctl restart getty@tty1
