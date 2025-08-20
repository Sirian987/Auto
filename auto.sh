# /bin/bash

# Script Auto Setup Cloudflare Tunnel dengan Input User
# Menggunakan screen untuk run tunnel jika service tidak bisa

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fungsi untuk print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_input() {
    echo -e "${BLUE}[INPUT]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Validasi: Cek apakah cloudflared sudah terinstall
check_cloudflared() {
    if ! command -v cloudflared &> /dev/null; then
        print_error "cloudflared tidak ditemukan. Silakan install terlebih dahulu."
        echo "Download dari: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation"
        echo "Untuk Ubuntu/Debian: sudo apt install cloudflared"
        echo "Untuk CentOS/RHEL: sudo yum install cloudflared"
        exit 1
    fi
    print_status "cloudflared ditemukan: $(cloudflared --version)"
}

# Validasi: Cek apakah screen sudah terinstall
check_screen() {
    if ! command -v screen &> /dev/null; then
        print_error "screen tidak ditemukan. Silakan install terlebih dahulu."
        echo "Untuk Ubuntu/Debian: sudo apt install screen"
        echo "Untuk CentOS/RHEL: sudo yum install screen"
        exit 1
    fi
    print_status "screen ditemukan: $(screen --version | head -n1)"
}

# Validasi: Cek apakah sudah login
check_login() {
    print_step "Memeriksa status login Cloudflare..."
    if ! cloudflared tunnel list &> /dev/null; then
        print_error "Anda belum login ke Cloudflare. Silakan login terlebih dahulu."
        echo "Jalankan: cloudflared tunnel login"
        exit 1
    fi
    print_status "Sudah login ke Cloudflare"
}

# Minta input dari user
get_user_input() {
    echo ""
    print_input "Masukkan PORT service lokal (contoh: 3000, 8080, 80):"
    read -r PORT
    
    print_input "Masukkan NAMA TUNNEL (contoh: my-tunnel, web-app):"
    read -r TUNNEL_NAME
    
    print_input "Masukkan DOMAIN utama Anda (contoh: example.com):"
    read -r DOMAIN
    
    print_input "Masukkan jumlah SUBDOMAIN yang ingin dibuat:"
    read -r SUBDOMAIN_COUNT
    
    SUBDOMAINS=()
    for ((i=1; i<=SUBDOMAIN_COUNT; i++)); do
        print_input "Masukkan nama subdomain ke-$i:"
        read -r subdomain
        SUBDOMAINS+=("$subdomain")
    done
    
    print_input "Masukkan path untuk config file (default: /etc/cloudflared/config.yml):"
    read -r CONFIG_FILE
    CONFIG_FILE=${CONFIG_FILE:-/etc/cloudflared/config.yml}
    
    SERVICE_URL="http://localhost:$PORT"
}

# Buat tunnel baru
create_tunnel() {
    print_step "Membuat tunnel baru: $TUNNEL_NAME"
    
    # Cek jika tunnel sudah ada
    if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
        print_warning "Tunnel dengan nama '$TUNNEL_NAME' sudah ada."
        read -p "Gunakan tunnel yang sudah ada? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        else
            print_input "Masukkan nama tunnel yang baru:"
            read -r TUNNEL_NAME
            create_tunnel
            return 0
        fi
    fi
    
    # Buat tunnel baru
    cloudflared tunnel create "$TUNNEL_NAME"
    
    if [ $? -ne 0 ]; then
        print_error "Gagal membuat tunnel."
        exit 1
    fi
    
    print_status "Tunnel '$TUNNEL_NAME' berhasil dibuat"
}

# Buat konfigurasi
create_config() {
    print_step "Membuat konfigurasi di $CONFIG_FILE"
    
    # Buat direktori jika belum ada
    sudo mkdir -p "$(dirname "$CONFIG_FILE")"
    
    # Dapatkan credentials file path
    CREDENTIALS_FILE="/root/.cloudflared/$(cloudflared tunnel list -o json | jq -r ".[] | select(.name == \"$TUNNEL_NAME\") | .credentials_file" 2>/dev/null | head -1)"
    
    if [ -z "$CREDENTIALS_FILE" ] || [ "$CREDENTIALS_FILE" == "null" ]; then
        # Fallback jika jq tidak tersedia
        CREDENTIALS_FILE="/root/.cloudflared/${TUNNEL_NAME}-*.json"
        CREDENTIALS_FILE=$(ls $CREDENTIALS_FILE 2>/dev/null | head -1)
    fi
    
    if [ -z "$CREDENTIALS_FILE" ]; then
        print_error "Tidak dapat menemukan credentials file untuk tunnel $TUNNEL_NAME"
        exit 1
    fi
    
    # Mulai menulis konfigurasi
    sudo tee "$CONFIG_FILE" > /dev/null <<EOF
tunnel: $TUNNEL_NAME
credentials-file: $CREDENTIALS_FILE
ingress:
EOF

    # Tambahkan setiap subdomain ke konfigurasi
    for subdomain in "${SUBDOMAINS[@]}"; do
        full_domain="$subdomain.$DOMAIN"
        print_status "Menambahkan subdomain: $full_domain"
        sudo tee -a "$CONFIG_FILE" > /dev/null <<EOF
  - hostname: $full_domain
    service: $SERVICE_URL
EOF
    done

    # Tambahkan fallback rule
    sudo tee -a "$CONFIG_FILE" > /dev/null <<EOF
  - service: http_status:404
EOF
    
    print_status "Konfigurasi berhasil dibuat di $CONFIG_FILE"
}

# Route traffic untuk semua subdomain
route_traffic() {
    print_step "Membuat route untuk semua subdomain"
    
    for subdomain in "${SUBDOMAINS[@]}"; do
        full_domain="$subdomain.$DOMAIN"
        print_status "Membuat route untuk $full_domain"
        cloudflared tunnel route dns "$TUNNEL_NAME" "$full_domain"
        
        if [ $? -ne 0 ]; then
            print_warning "Gagal membuat route untuk $full_domain, melanjutkan ke subdomain berikutnya..."
        fi
    done
}

# Jalankan tunnel dengan screen
run_tunnel_with_screen() {
    print_step "Menjalankan tunnel dengan screen"
    
    # Cek jika screen session sudah ada
    if screen -list | grep -q "cloudflared_$TUNNEL_NAME"; then
        print_warning "Screen session untuk tunnel '$TUNNEL_NAME' sudah ada."
        read -p "Hentikan dan buat baru? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            screen -S "cloudflared_$TUNNEL_NAME" -X quit
            sleep 2
        else
            return 0
        fi
    fi
    
    # Buat screen session baru
    screen -dmS "cloudflared_$TUNNEL_NAME" cloudflared tunnel run "$TUNNEL_NAME"
    
    if [ $? -eq 0 ]; then
        print_status "Tunnel berhasil dijalankan di screen session: cloudflared_$TUNNEL_NAME"
        echo "Untuk melihat screen session: screen -r cloudflared_$TUNNEL_NAME"
        echo "Untuk detach dari screen: Ctrl+A kemudian D"
    else
        print_error "Gagal menjalankan tunnel dengan screen"
        exit 1
    fi
}

# Coba jalankan sebagai service, fallback ke screen
run_tunnel() {
    print_step "Mencoba menjalankan tunnel sebagai service"
    
    # Coba install service
    if sudo cloudflared service install; then
        sudo systemctl start cloudflared
        sudo systemctl enable cloudflared
        
        print_status "Menunggu tunnel mulai..."
        sleep 5
        
        # Cek status tunnel
        if sudo systemctl is-active --quiet cloudflared; then
            print_status "Tunnel berhasil dijalankan sebagai service"
            return 0
        else
            print_warning "Service cloudflared tidak berjalan, mencoba menggunakan screen..."
        fi
    else
        print_warning "Gagal menginstall service, mencoba menggunakan screen..."
    fi
    
    # Fallback ke screen
    run_tunnel_with_screen
}

# Tampilkan ringkasan konfigurasi
show_summary() {
    echo ""
    echo "=========================================="
    print_status "SETUP SELESAI!"
    echo "=========================================="
    echo "Nama Tunnel: $TUNNEL_NAME"
    echo "Domain: $DOMAIN"
    echo "Port: $PORT"
    echo "Service URL: $SERVICE_URL"
    echo "Config File: $CONFIG_FILE"
    echo ""
    echo "Subdomain yang dikonfigurasi:"
    for subdomain in "${SUBDOMAINS[@]}"; do
        echo "  - $subdomain.$DOMAIN → $SERVICE_URL"
    done
    echo ""
    echo "Perintah untuk monitoring:"
    echo "  cloudflared tunnel list"
    echo "  screen -list"
    echo "  screen -r cloudflared_$TUNNEL_NAME"
    echo ""
    echo "Perintah untuk manajemen screen:"
    echo "  Ctrl+A, D → Detach dari screen"
    echo "  screen -list → Lihat daftar screen"
    echo "  screen -r <nama> → Masuk ke screen"
    echo "  screen -X -S <nama> quit → Keluar dari screen"
    echo ""
    echo "Pastikan DNS record untuk domain Anda di Cloudflare"
    echo "di-set untuk menggunakan CNAME ke domain .cfargotunnel.com"
    echo "=========================================="
}

# Main execution
main() {
    echo "=========================================="
    echo "  Cloudflare Tunnel Auto Setup Script"
    echo "  (Menggunakan Screen untuk Run Tunnel)"
    echo "=========================================="
    
    # Jalankan validasi
    check_cloudflared
    check_screen
    check_login
    
    # Minta input dari user
    get_user_input
    
    # Konfirmasi sebelum melanjutkan
    echo ""
    echo "=========================================="
    echo "Ringkasan Konfigurasi:"
    echo "  Tunnel: $TUNNEL_NAME"
    echo "  Domain: $DOMAIN"
    echo "  Port: $PORT"
    echo "  Jumlah Subdomain: ${#SUBDOMAINS[@]}"
    echo "  Config: $CONFIG_FILE"
    echo "=========================================="
    
    read -p "Lanjutkan setup? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    # Jalankan proses setup
    create_tunnel
    create_config
    route_traffic
    run_tunnel
    
    # Tampilkan ringkasan
    show_summary
}

# Jalankan script utama
main "$@"
