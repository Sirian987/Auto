#!/bin/bash
set -e

GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

clear
echo -e "${CYAN}==========================================${RESET}"
echo -e "${GREEN} 🚀 Auto Installer Cloudflare Tunnel (Multi Domain) ${RESET}"
echo -e "${CYAN}==========================================${RESET}"

# 1. Install cloudflared
echo -e "${YELLOW}🔧 Menginstall cloudflared...${RESET}"
apt update -y
apt install -y wget screen

wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared-linux-amd64.deb || apt -f install -y

# 2. Login Cloudflare
echo -e "${YELLOW}🌐 Login Cloudflare... (ikuti link yang muncul)${RESET}"
cloudflared tunnel login

# 3. Buat tunnel
read -p "👉 Masukkan nama tunnel: " TUNNEL_NAME
cloudflared tunnel create $TUNNEL_NAME

CONFIG_DIR="/etc/cloudflared"
mkdir -p $CONFIG_DIR

# 4. Input domain mapping
read -p "👉 Berapa banyak subdomain yang mau ditambahkan? " TOTAL

INGRESS_RULES=""
for ((i=1; i<=TOTAL; i++))
do
    read -p "🌐 Subdomain #$i (contoh: api.domain.com): " DOMAIN
    read -p "🔌 Port untuk $DOMAIN (contoh: 3000): " PORT
    INGRESS_RULES+="  - hostname: $DOMAIN\n    service: http://localhost:$PORT\n"
done

# Tambahkan fallback rule
INGRESS_RULES+="  - service: http_status:404"

# 5. Generate config.yml
cat > $CONFIG_DIR/config.yml <<EOF
tunnel: $TUNNEL_NAME
credentials-file: /root/.cloudflared/${TUNNEL_NAME}.json

ingress:
$INGRESS_RULES
EOF

echo -e "${GREEN}✔ Config multi-domain dibuat di $CONFIG_DIR/config.yml${RESET}"

# 6. Run tunnel pakai screen
echo -e "${YELLOW}▶ Menjalankan tunnel di screen (session: cf-tunnel)...${RESET}"
screen -dmS cf-tunnel cloudflared tunnel run $TUNNEL_NAME

echo -e "${GREEN}=========================================="
echo "✅ Cloudflare Tunnel '$TUNNEL_NAME' aktif!"
echo "📂 Config : $CONFIG_DIR/config.yml"
echo "🖥 Screen : cf-tunnel  (lihat dengan 'screen -r cf-tunnel')"
echo -e "==========================================${RESET}"
