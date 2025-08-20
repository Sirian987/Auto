#!/bin/bash

# Warna
GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"

clear
echo -e "${CYAN}"
echo "=========================================="
echo "   🚀 Auto Subdomain + Nginx + SSL Tool   "
echo "=========================================="
echo -e "${RESET}"

# --- INPUT ---
echo -e "${YELLOW}Masukkan data subdomain:${RESET}"
read -p "👉 Domain utama (contoh: contoh.com) : " domain
read -p "👉 Subdomain (contoh: app)           : " sub
read -p "👉 Port aplikasi (contoh: 3000)      : " port

echo ""
read -p "Gunakan IP otomatis VPS? (y/n): " use_auto_ip

if [ "$use_auto_ip" == "y" ]; then
    IP_SERVER=$(curl -s ifconfig.me)
    echo -e "${GREEN}✔ IP Otomatis terdeteksi: $IP_SERVER${RESET}"
else
    read -p "👉 Masukkan IP manual: " IP_SERVER
fi

# --- CLOUDFLARE ---
CF_API="https://api.cloudflare.com/client/v4"
CF_ZONE_ID="ZONE_ID_KAMU"        # isi dengan Zone ID
CF_API_TOKEN="API_TOKEN_KAMU"    # isi dengan API Token

echo ""
echo -e "${CYAN}⚡ Menambahkan DNS record ke Cloudflare...${RESET}"
curl -s -X POST "$CF_API/zones/$CF_ZONE_ID/dns_records" \
     -H "Authorization: Bearer $CF_API_TOKEN" \
     -H "Content-Type: application/json" \
     --data "{\"type\":\"A\",\"name\":\"$sub.$domain\",\"content\":\"$IP_SERVER\",\"ttl\":120,\"proxied\":false}" \
     | jq

# --- NGINX CONFIG ---
servername="$sub.$domain"
conf_path="/etc/nginx/sites-available/$servername"

cat > $conf_path <<EOF
server {
    listen 80;
    server_name $servername;

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

ln -s $conf_path /etc/nginx/sites-enabled/ 2>/dev/null

nginx -t && systemctl reload nginx

# --- SSL ---
echo ""
echo -e "${CYAN}🔒 Mengaktifkan SSL (Let's Encrypt)...${RESET}"
certbot --nginx -d $servername

echo ""
echo -e "${GREEN}=========================================="
echo "  🎉 Selesai!"
echo "  🌍 Domain : https://$servername"
echo "  🚀 Proxy  : 127.0.0.1:$port"
echo "==========================================${RESET}"
