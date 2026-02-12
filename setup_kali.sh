#!/bin/bash

# setup_kali.sh
# Automates the setup of a fresh Kali Linux environment for Red Team operations.
# Usage: sudo ./setup_kali.sh "YourNewPassword"

# --- Helper Functions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function info() { echo -e "${BLUE}[*] $1${NC}"; }
function success() { echo -e "${GREEN}[+] $1${NC}"; }
function warn() { echo -e "${YELLOW}[!] $1${NC}"; }
function error() { echo -e "${RED}[-] $1${NC}"; }

# --- Checks ---

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  error "Please run as root (sudo ./setup_kali.sh \"password\")"
  exit 1
fi

# Check for password argument
if [ -z "$1" ]; then
    error "ERROR: No password provided."
    echo "Usage: sudo ./setup_kali.sh \"YourNewPassword\""
    exit 1
fi

NEW_PASS="$1"
TMUX_URL="https://raw.githubusercontent.com/rrlocksmith/tmux/refs/heads/main/.tmux2.conf"

# Suppress interactive prompts during upgrades/installation
export DEBIAN_FRONTEND=noninteractive

# Configure needrestart to automatically restart services if it's installed
if [ -f /etc/needrestart/needrestart.conf ]; then
    sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
fi

# --- Pre-flight Checks ---
info "Checking for port conflicts..."
# Stop containers on port 80 or 443
if docker ps --format '{{.Ports}}' | grep -qE '0.0.0.0:(80|443)'; then
    warn "Ports 80/443 are in use by existing containers. Force removing them..."
    docker rm -f $(docker ps -q --filter "publish=443") > /dev/null 2>&1
    docker rm -f $(docker ps -q --filter "publish=80") > /dev/null 2>&1
    success "Conflicting containers removed."
fi

echo ""
info "Starting Kali Setup..."



# 1. Change Passwords
# 1. Change Passwords
info "Changing passwords for 'root' and 'kali'..."
echo "root:$NEW_PASS" | chpasswd
echo "kali:$NEW_PASS" | chpasswd
success "Passwords updated."

# 2. System Updates & Dependencies
info "Installing dependencies (this may take a while)..."
apt update > /dev/null 2>&1
apt install -y curl fuse3 xclip docker.io docker-compose > /dev/null 2>&1
systemctl enable --now docker > /dev/null 2>&1
usermod -aG docker kali
success "Dependencies installed."

# 3. Antigravity Setup
info "Installing Antigravity..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
  gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg > /dev/null 2>&1
echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
  tee /etc/apt/sources.list.d/antigravity.list > /dev/null
apt update > /dev/null 2>&1
apt install -y antigravity > /dev/null 2>&1
success "Antigravity installed."

# 3.5 Chrome Remote Desktop (CRD)
info "Installing Chrome Remote Desktop..."
CRD_DEB="/tmp/chrome-remote-desktop_current_amd64.deb"
wget -q -O "$CRD_DEB" https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
apt install -y "$CRD_DEB" > /dev/null 2>&1
rm -f "$CRD_DEB"
# Ensure service is ready (enabled but waiting for config)
systemctl enable chrome-remote-desktop@kali > /dev/null 2>&1
success "Chrome Remote Desktop installed."

# 4. Tmux Configuration (User & Root)
info "Configuring .tmux.conf..."
sudo -u kali curl -sL "$TMUX_URL" -o /home/kali/.tmux.conf
curl -sL "$TMUX_URL" -o /root/.tmux.conf
success "Tmux config installed for kali and root."

# 5. Shell Aliases (ll -> ls -la)
info "Configuring 'll' alias..."
# For Kali User
if ! grep -q "alias ll='ls -la'" /home/kali/.bashrc; then
    echo "alias ll='ls -la'" >> /home/kali/.bashrc
    chown kali:kali /home/kali/.bashrc
fi
if [ -f /home/kali/.zshrc ]; then
    if ! grep -q "alias ll='ls -la'" /home/kali/.zshrc; then
        echo "alias ll='ls -la'" >> /home/kali/.zshrc
        chown kali:kali /home/kali/.zshrc
    fi
fi

# For Root User
if ! grep -q "alias ll='ls -la'" /root/.bashrc; then
    echo "alias ll='ls -la'" >> /root/.bashrc
fi
if [ -f /root/.zshrc ]; then
    if ! grep -q "alias ll='ls -la'" /root/.zshrc; then
        echo "alias ll='ls -la'" >> /root/.zshrc
    fi
fi
success "Aliases updated."

# 5. Nginx Proxy Manager (Docker)
info "Deploying Nginx Proxy Manager (GUI)..."
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
docker-compose up -d > /dev/null 2>&1

# Verify NPM Startup
info "Verifying Nginx Proxy Manager startup..."
sleep 5 # Give it a moment to initialize
if curl -s --head http://localhost:81 | grep "200 OK" > /dev/null; then
    success "Nginx Proxy Manager started successfully."
    echo "    - GUI: http://localhost:81"
    echo "    - Default Creds: admin@example.com / changeme"
else
    error "Nginx Proxy Manager failed to start or is not reachable on port 81."
    warn "Checking logs..."
    docker-compose logs --tail=10
fi

# 6. Rclone (Google Drive)
info "Installing Rclone..."
curl -s https://rclone.org/install.sh | bash > /dev/null 2>&1

info "Configuring Google Drive..."
# 1. Create the config entry (this might result in an empty token initially)
sudo -u kali rclone config create drive drive scope drive config_is_local false > /dev/null 2>&1

# 2. Force authentication to get the token (URL + Verification Code)
echo ""
warn "ACTION REQUIRED: Google Drive Authentication"
echo "--------------------------------------------------------"
echo "1. A URL will be displayed below."
echo "2. Open it in your browser and sign in."
echo "3. Copy the verification code."
echo "4. Paste the code here when prompted."
echo "--------------------------------------------------------"
echo ""
sudo -u kali rclone config reconnect drive:

info "Mounting Google Drive..."
mkdir -p /home/kali/GoogleDrive
chown kali:kali /home/kali/GoogleDrive

# Mount as user kali.
sudo -u kali rclone mount drive: /home/kali/GoogleDrive --daemon --vfs-cache-mode writes
success "Drive mounted at: /home/kali/GoogleDrive"

echo ""
echo "================================================================"
success "SETUP COMPLETE!"
echo "================================================================"
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

