#!/bin/bash

# setup_kali.sh
# Automates the setup of a fresh Kali Linux environment for Red Team operations.
# Usage: sudo ./setup_kali.sh "YourNewPassword"

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root (sudo ./setup_kali.sh \"password\")"
  exit 1
fi

# Check for password argument
if [ -z "$1" ]; then
    echo "[-] ERROR: No password provided."
    echo "Usage: sudo ./setup_kali.sh \"YourNewPassword\""
    exit 1
fi

NEW_PASS="$1"
TMUX_URL="https://raw.githubusercontent.com/rrlocksmith/tmux/refs/heads/main/.tmux2.conf"

echo "[*] Starting Kali Setup..."

# 1. Change Passwords
echo "[*] Changing passwords for 'root' and 'kali'..."
echo "root:$NEW_PASS" | chpasswd
echo "kali:$NEW_PASS" | chpasswd
echo "[+] Passwords updated."

# 2. System Updates & Dependencies
echo "[*] Installing dependencies..."
apt update
apt install -y curl fuse3 xclip docker.io docker-compose
systemctl enable --now docker
usermod -aG docker kali
echo "[+] Dependencies installed."

# 3. Antigravity Setup
echo "[*] Installing Antigravity..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
  gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
  tee /etc/apt/sources.list.d/antigravity.list > /dev/null
apt update
apt install -y antigravity
echo "[+] Antigravity installed."

# 3.5 Chrome Remote Desktop (CRD)
echo "[*] Installing Chrome Remote Desktop..."
CRD_DEB="/tmp/chrome-remote-desktop_current_amd64.deb"
wget -O "$CRD_DEB" https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
apt install -y "$CRD_DEB"
rm -f "$CRD_DEB"
# Ensure service is ready (enabled but waiting for config)
systemctl enable chrome-remote-desktop@kali
echo "[+] Chrome Remote Desktop installed."

# 4. Tmux Configuration (User & Root)
echo "[*] Configuring .tmux.conf for user 'kali'..."
sudo -u kali curl -sL "$TMUX_URL" -o /home/kali/.tmux.conf

echo "[*] Configuring .tmux.conf for user 'root'..."
curl -sL "$TMUX_URL" -o /root/.tmux.conf
echo "[+] Tmux config installed for kali and root."

# 5. Shell Aliases (ll -> ls -la)
echo "[*] Configuring 'll' alias..."
# For Kali User
if ! grep -q "alias ll='ls -la'" /home/kali/.bashrc; then
    echo "alias ll='ls -la'" >> /home/kali/.bashrc
    chown kali:kali /home/kali/.bashrc
fi
# For Root User
if ! grep -q "alias ll='ls -la'" /root/.bashrc; then
    echo "alias ll='ls -la'" >> /root/.bashrc
fi
echo "[+] Aliases updated."

# 5. Nginx Proxy Manager (Docker)
echo "[*] Deploying Nginx Proxy Manager (GUI)..."
NPM_DIR="/home/kali/npm"
mkdir -p "$NPM_DIR"
cat <<EOF > "$NPM_DIR/docker-compose.yml"
version: '3.8'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF
chown -R kali:kali "$NPM_DIR"

# Launch NPM
cd "$NPM_DIR"
docker-compose up -d
echo "[+] Nginx Proxy Manager started."
echo "    - GUI: http://localhost:81"
echo "    - Default Creds: admin@example.com / changeme"

# 6. Rclone (Google Drive)
echo "[*] Installing Rclone..."
curl https://rclone.org/install.sh | bash

echo "[*] Configuring Google Drive (Interactive Auth Required)..."
# Create the config entry as user 'kali' so config is saved in /home/kali/.config/rclone/rclone.conf
# config_is_local false forces Rclone to print a URL and wait for a verification code (Manual Auth).
sudo -u kali rclone config create drive drive scope drive config_is_local false

echo "[*] Mounting Google Drive..."
mkdir -p /home/kali/GoogleDrive
chown kali:kali /home/kali/GoogleDrive

# Mount as user kali.
sudo -u kali rclone mount drive: /home/kali/GoogleDrive --daemon --vfs-cache-mode writes

echo ""
echo "[*] SETUP COMPLETE!"
echo "    - Google Drive configuration initiated."
echo "    - Drive mounted at: /home/kali/GoogleDrive"
echo ""
echo "----------------------------------------------------------------"
echo "NEXT STEPS: Chrome Remote Desktop Authorization"
echo "----------------------------------------------------------------"
echo "1. On your LOCAL/HOST computer, go to:"
echo "   https://remotedesktop.google.com/headless"
echo "2. Sign in, click 'Begin' -> 'Next' -> 'Authorize'."
echo "3. Copy the 'Debian Linux' command (starts with DISPLAY= /opt/...)"
echo "4. Paste it into this terminal as user 'kali':"
echo "   su - kali"
echo "   <PASTE_COMMAND>"
echo "5. Set your PIN when prompted."
echo "----------------------------------------------------------------"
echo ""
