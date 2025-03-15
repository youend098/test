#!/bin/bash

DOMAIN="Domain"  # Ganti dengan domain server kamu
PORT="443"  # Port yang digunakan untuk Xray

# Fungsi untuk melakukan speedtest
speedtest_vps() {
    clear
    echo "====================================="
    echo "         Speedtest VPS               "
    echo "====================================="
    if ! command -v speedtest &> /dev/null; then
        echo "Speedtest CLI belum terinstall. Menginstall sekarang..."
        apt update && apt install -y speedtest-cli
    fi
    speedtest
    read -p "Tekan enter untuk kembali ke menu..." enterKey
}

# Fungsi untuk membuat akun VPN
tambah_akun() {
    clear
    echo "====================================="
    echo "      Pilih Jenis Akun VPN           "
    echo "====================================="
    echo "1. VMess"
    echo "2. VLESS"
    echo "3. Trojan"
    echo "4. Kembali"
    echo "====================================="
    read -p "Pilih opsi [1-4]: " jenis

    case $jenis in
        1) jenis_vpn="vmess"; proto="ws";;
        2) jenis_vpn="vless"; proto="ws";;
        3) jenis_vpn="trojan";;
        4) return ;;
        *) echo "Pilihan tidak valid!"; sleep 2; return ;;
    esac

    read -p "Masukkan username: " user
    uuid=$(cat /proc/sys/kernel/random/uuid)  # Generate UUID
    read -p "Masukkan masa aktif (hari): " masa_aktif

    exp_date=$(date -d "+$masa_aktif days" +"%Y-%m-%d")  # Hitung tanggal kadaluarsa

    # Tambahkan akun ke config Xray
    cat >> /usr/local/etc/xray/config.json <<EOF
        {
            "id": "$uuid",
            "email": "$user",
            "expiry": "$exp_date"
        },
EOF

    systemctl restart xray  # Restart layanan Xray agar akun aktif

    # Buat link akun sesuai jenis VPN
    if [[ $jenis_vpn == "vmess" ]]; then
        config=$(echo -n '{"v":"2","ps":"'"$user"'","add":"'"$DOMAIN"'","port":"'"$PORT"'","id":"'"$uuid"'","aid":"0","net":"ws","path":"/vmess","tls":"tls"}' | base64 -w 0)
        link="vmess://$config"
    elif [[ $jenis_vpn == "vless" ]]; then
        link="vless://$uuid@$DOMAIN:$PORT?path=/vless&security=tls&type=ws#$user"
    elif [[ $jenis_vpn == "trojan" ]]; then
        link="trojan://$uuid@$DOMAIN:$PORT?security=tls&type=ws#$user"
    fi

    # Tampilkan detail akun yang baru dibuat
    clear
    echo "====================================="
    echo "         Akun VPN Berhasil Dibuat    "
    echo "====================================="
    echo "Jenis Akun : $jenis_vpn"
    echo "Username   : $user"
    echo "UUID       : $uuid"
    echo "Masa Aktif : $masa_aktif hari"
    echo "Expire     : $exp_date"
    echo "====================================="
    echo "🔗 Link Konfigurasi Akun:"
    echo "$link"
    echo "====================================="
    echo "📌 Salin dan gunakan link ini di aplikasi VPN"
    read -p "Tekan enter untuk kembali ke menu..." enterKey
}

# Fungsi untuk menghapus akun VPN
hapus_akun() {
    read -p "Masukkan username yang ingin dihapus: " user
    sed -i "/\"email\": \"$user\"/d" /usr/local/etc/xray/config.json  # Hapus akun dari config
    systemctl restart xray
    echo "Akun $user telah dihapus."
    sleep 2
}

# Fungsi untuk menampilkan status Xray
cek_status() {
    systemctl status xray
    read -p "Tekan enter untuk kembali ke menu..." enterKey
}

# Fungsi untuk melihat penggunaan resource
cek_resource() {
    echo "== Penggunaan CPU & RAM =="
    top -b -n1 | head -n 10
    echo "== Penggunaan Disk =="
    df -h
    echo "== Penggunaan Bandwidth =="
    vnstat -i eth0
    read -p "Tekan enter untuk kembali ke menu..." enterKey
}

# Fungsi untuk restart Xray
restart_xray() {
    systemctl restart xray
    echo "Xray telah direstart."
    sleep 2
}

# Loop menu utama
while true; do
    clear
    echo "====================================="
    echo "      VPN PREMIUM By_MF-youend       "
    echo "====================================="
    echo "1. Tambah Akun VPN"
    echo "2. Hapus Akun VPN"
    echo "3. Cek Status VPN"
    echo "4. Cek Penggunaan Resource VPS"
    echo "5. Restart Xray"
    echo "6. Speedtest VPS"
    echo "7. Keluar"
    echo "====================================="
    read -p "Pilih opsi [1-7]: " opsi

    case $opsi in
        1) tambah_akun ;;
        2) hapus_akun ;;
        3) cek_status ;;
        4) cek_resource ;;
        5) restart_xray ;;
        6) speedtest_vps ;;
        7) exit 0 ;;
        *) echo "Pilihan tidak valid, silakan coba lagi." ;;
    esac
    sleep 2
done
