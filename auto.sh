#!/bin/bash

# Script Auto Setup Cloudflare Tunnel dengan Screen
# Memastikan screen running untuk tunnel

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variabel global
TUNNEL_NAME=""
SCREEN_NAME=""

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

# Cek jika screen session untuk tunnel sudah running
is_screen_running() {
    screen -list | grep -q "$SCREEN_NAME"
}

# Hentikan screen session
stop_screen() {
    if is_screen_running; then
        print_status "Menghentikan screen session: $SCREEN_NAME"
        screen -S "$SCREEN_NAME" -X quit
        sleep 2
    fi
}

# Jalankan tunnel dengan screen
run_tunnel_with_screen() {
    print_step "Menjalankan tunnel dengan screen"
    
    # Hentikan screen session lama jika ada
    stop_screen
    
    # Buat screen session baru
    print_status "Memulai screen session: $SCREEN_NAME"
    screen -dmS "$SCREEN_NAME" cloudflared tunnel run "$TUNNEL_NAME"
    
    # Tunggu sebentar
    sleep 3
    
    # Verifikasi screen running
    if is_screen_running; then
        print_status "✓ Screen session berhasil dibuat: $SCREEN_NAME"
        print_status "✓ Tunnel sedang berjalan di background"
        
        # Tampilkan info screen
        echo ""
        print_status "Daftar screen session yang aktif:"
        screen -list | grep "$SCREEN_NAME"
        
    else
        print_error "✗ Gagal menjalankan tunnel dengan screen"
        print_error "Coba jalankan manual: screen -dmS $SCREEN_NAME cloudflared tunnel run $TUNNEL_NAME"
        exit 1
    fi
}

# Cek status tunnel
check_tunnel_status() {
    print_step "Memeriksa status tunnel..."
    
    # Cek screen session
    if is_screen_running; then
        print_status "✓ Screen session '$SCREEN_NAME' sedang running"
    else
        print_error "✗ Screen session '$SCREEN_NAME' tidak running"
        return 1
    fi
    
    # Cek tunnel status
    local tunnel_status=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $4}')
    if [ "$tunnel_status" = "ACTIVE" ] || [ "$tunnel_status" = "healthy" ]; then
        print_status "✓ Tunnel '$TUNNEL_NAME' status: $tunnel_status"
        return 0
    else
        print_warning "? Tunnel '$TUNNEL_NAME' status: $tunnel_status"
        return 1
    fi
}

# Menu utama untuk manage tunnel
manage_tunnel_menu() {
    while true; do
        echo ""
        echo "=========================================="
        print_status "MANAJEMENT TUNNEL: $TUNNEL_NAME"
        echo "=========================================="
        echo "1. Lihat status tunnel"
        echo "2. Masuk ke screen session (monitor)"
        echo "3. Restart tunnel"
        echo "4. Hentikan tunnel"
        echo "5. Lihat daftar screen sessions"
        echo "6. Keluar"
        echo "=========================================="
        
        read -p "Pilih opsi (1-6): " choice
        
        case $choice in
            1)
                check_tunnel_status
                ;;
            2)
                print_step "Masuk ke screen session: $SCREEN_NAME"
                echo "Untuk keluar dari screen: Ctrl+A kemudian D"
                echo "Untuk force quit: Ctrl+A kemudian K"
                sleep 2
                screen -r "$SCREEN_NAME"
                ;;
            3)
                print_step "Restarting tunnel..."
                stop_screen
                sleep 2
                run_tunnel_with_screen
                check_tunnel_status
                ;;
            4)
                print_step "Menghentikan tunnel..."
                stop_screen
                if is_screen_running; then
                    print_error "Gagal menghentikan screen session"
                else
                    print_status "Tunnel berhasil dihentikan"
                fi
                ;;
            5)
                print_status "Daftar screen sessions:"
                screen -list
                ;;
            6)
                print_status "Keluar dari management menu"
                break
                ;;
            *)
                print_error "Pilihan tidak valid"
                ;;
        esac
    done
}

# Buat tunnel baru
create_tunnel() {
    print_step "Membuat/Menggunakan tunnel: $TUNNEL_NAME"
    
    # Cek jika tunnel sudah ada
    if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
        print_warning "Tunnel '$TUNNEL_NAME' sudah ada, menggunakan yang existing"
        return 0
    fi
    
    # Buat tunnel baru
    print_status "Membuat tunnel baru..."
    if cloudflared tunnel create "$TUNNEL_NAME"; then
        print_status "✓ Tunnel '$TUNNEL_NAME' berhasil dibuat"
    else
        print_error "✗ Gagal membuat tunnel '$TUNNEL_NAME'"
        exit 1
    fi
}

# Buat konfigurasi
create_config() {
    local CONFIG_FILE="/home/$(whoami)/.cloudflared/config.yml"
    print_step "Membuat konfigurasi di $CONFIG_FILE"
    
    # Buat direktori jika belum ada
    mkdir -p "$(dirname "$CONFIG_FILE")"
    
    # Cari credentials file
    local CREDENTIALS_FILE=$(find /home/$(whoami)/.cloudflared -name "*${TUNNEL_NAME}*.json" | head -1)
    
    if [ -z "$CREDENTIALS_FILE" ]; then
        print_error "Tidak dapat menemukan credentials file untuk tunnel $TUNNEL_NAME"
        print_error "Cek: ls -la /home/$(whoami)/.cloudflared/"
        exit 1
    fi
    
    # Buat config
    cat > "$CONFIG_FILE" <<EOF
tunnel: $TUNNEL_NAME
credentials-file: $CREDENTIALS_FILE
ingress:
  - hostname: test.$TUNNEL_NAME.example.com
    service: http://localhost:8080
  - service: http_status:404
EOF
    
    print_status "✓ Konfigurasi berhasil dibuat di $CONFIG_FILE"
}

# Main execution
main() {
    echo "=========================================="
    echo "  Cloudflare Tunnel Manager dengan Screen"
    echo "=========================================="
    
    # Jalankan validasi
    check_cloudflared
    check_screen
    
    # Minta input tunnel name
    print_input "Masukkan NAMA TUNNEL (contoh: my-tunnel):"
    read -r TUNNEL_NAME
    
    # Set screen name
    SCREEN_NAME="cf_$TUNNEL_NAME"
    
    # Buat tunnel
    create_tunnel
    
    # Buat config
    create_config
    
    # Jalankan tunnel dengan screen
    run_tunnel_with_screen
    
    # Cek status
    if check_tunnel_status; then
        print_status "✓ Setup berhasil! Tunnel sedang berjalan."
    else
        print_warning "! Tunnel dibuat tetapi perlu dimonitor"
    fi
    
    # Tampilkan informasi
    echo ""
    print_status "INFORMASI SCREEN:"
    echo "  Nama Screen Session: $SCREEN_NAME"
    echo "  Perintah monitor: screen -r $SCREEN_NAME"
    echo "  Perintah list: screen -list"
    echo "  Detach: Ctrl+A kemudian D"
    
    # Tampilkan menu management
    manage_tunnel_menu
}

# Jalankan script utama
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
