#!/bin/bash
set -e

GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

clear
echo -e "${CYAN}==========================================${RESET}"
echo -e "${GREEN} 🚀 Auto Config Cloudflare Tunnel (Multi Domain) ${RESET}"
echo -e "${CYAN}==========================================${RESET}"

# Pastikan cloudflared sudah ada
if ! command -v cloudflared &> /dev/null; then
    echo -e "${YELLOW}❌ cloudflared belum terinstall!"
    echo -e "➡ Silakan install manual dulu sesuai arsitektur VPS.${RESET}"
    exit 1
fi

# Login Cloudflare
echo -e "${YELLOW}🌐 Login Cloudflare... (ikuti link yang muncul)${RESET}"
cloudflared tunnel login

# Buat tunnel
read -p "👉 Masukkan nama tunnel: " TUNNEL_NAME
cloudflared tunnel create $TUNNEL_NAME

CONFIG_DIR="/etc/cloudflared"
mkdir -p $CONFIG_DIR

# Input domain mapping
read -p "👉 Berapa banyak subdomain yang mau ditambahkan? " TOTAL

# Simpan input dulu
declare -a DOMAINS
declare -a PORTS

for ((i=1; i<=TOTAL; i++)); do
    read -p "🌐 Subdomain #$i (contoh: api.domain.com): " DOMAIN
    read -p "🔌 Port untuk $DOMAIN (contoh: 3000): " PORT
    DOMAINS[$i]=$DOMAIN
    PORTS[$i]=$PORT
done

# --- Generate config.yml dengan indentasi benar ---
cat > $CONFIG_DIR/config.yml <<EOF
tunnel: $TUNNEL_NAME
credentials-file: /root/.cloudflared/${TUNNEL_NAME}.json

ingress:
EOF

for ((i=1; i<=TOTAL; i++)); do
    DOMAIN=${DOMAINS[$i]}
    PORT=${PORTS[$i]}
    cat >> $CONFIG_DIR/config.yml <<EOL
  - hostname: $DOMAIN
    service: http://localhost:$PORT
EOL
done

# fallback 404
cat >> $CONFIG_DIR/config.yml <<EOF
  - service: http_status:404
EOF

echo -e "${GREEN}✔ Config multi-domain dibuat di $CONFIG_DIR/config.yml${RESET}"

# Run tunnel pakai screen
echo -e "${YELLOW}▶ Menjalankan tunnel di screen (session: cf-tunnel)...${RESET}"
screen -dmS cf-tunnel cloudflared tunnel run $TUNNEL_NAME

echo -e "${GREEN}=========================================="
echo "✅ Cloudflare Tunnel '$TUNNEL_NAME' aktif!"
echo "📂 Config : $CONFIG_DIR/config.yml"
echo "🖥 Screen : cf-tunnel  (lihat dengan 'screen -r cf-tunnel')"
echo -e "==========================================${RESET}"
