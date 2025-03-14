#!/bin/bash

# Menonaktifkan IPv6 untuk menghindari konflik jaringan
echo "Menonaktifkan IPv6..."
echo 'net.ipv6.conf.all.disable_ipv6 = 1' | tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.default.disable_ipv6 = 1' | tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.lo.disable_ipv6 = 1' | tee -a /etc/sysctl.conf
sysctl -p

# Mengaktifkan dan mengatur firewall UFW
apt update && apt install -y ufw
systemctl enable ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 22/tcp
ufw allow from 192.168.1.0/24 to any port 10000:20000 proto tcp
ufw allow from 192.168.1.0/24 to any port 10000:20000 proto udp
ufw enable
ufw reload

# Instalasi paket yang dibutuhkan
apt install -y curl wget sudo jq lsb-release vnstat unzip zip bzip2 gzip coreutils screen nginx xray-core trojan-go socat gnupg apt-transport-https certbot

# Fungsi untuk menginstal Xray-Core secara otomatis
install_xray() {
    echo "Menginstal Xray-Core..."
    mkdir -p /etc/xray
    curl -Lo /usr/local/bin/xray https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
    unzip -o /usr/local/bin/xray -d /usr/local/bin/
    chmod +x /usr/local/bin/xray
    systemctl enable xray
    systemctl restart xray
    echo "Xray-Core berhasil diinstal."
}

# Fungsi untuk menginstal Trojan-Go secara otomatis
install_trojan_go() {
    echo "Menginstal Trojan-Go..."
    mkdir -p /etc/trojan-go
    curl -Lo /usr/local/bin/trojan-go https://github.com/p4gefau1t/trojan-go/releases/latest/download/trojan-go-linux-amd64.zip
    unzip -o /usr/local/bin/trojan-go -d /usr/local/bin/
    chmod +x /usr/local/bin/trojan-go
    systemctl enable trojan-go
    systemctl restart trojan-go
    echo "Trojan-Go berhasil diinstal."
}

# Instalasi otomatis layanan VPN
install_xray
install_trojan_go

# Pastikan layanan dapat dieksekusi
[[ -f /usr/local/bin/xray ]] && chmod +x /usr/local/bin/xray
[[ -f /usr/local/bin/trojan-go ]] && chmod +x /usr/local/bin/trojan-go

# Pastikan layanan berjalan
systemctl enable nginx xray trojan-go vnstat
systemctl restart nginx xray trojan-go vnstat

# Instalasi Speedtest
if ! command -v speedtest &>/dev/null; then
    echo "Menginstal speedtest-cli..."
    apt install -y speedtest-cli
fi
speedtest

# Pastikan vnstat memiliki database
IFACE=$(ip -o -4 route show to default | awk '{print $5}')
if ! vnstat -i "$IFACE" &>/dev/null; then
    vnstat --create -i "$IFACE"
fi
systemctl restart vnstat

# Meminta domain setelah instalasi
domain=""
while [[ -z "$domain" ]]; do
    read -p "Masukkan domain untuk server: " domain
    if [[ -z "$domain" ]]; then
        echo "Domain tidak boleh kosong!"
        continue
    fi
    if ! ping -c 1 -W 2 "$domain" &>/dev/null; then
        echo "Domain tidak dapat diakses! Pastikan sudah diarahkan ke server."
        exit 1
    fi
done
echo "$domain" > /etc/xray/domain

# Memasang SSL otomatis menggunakan Certbot
systemctl stop nginx
certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m admin@$domain
systemctl start nginx

if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
    ln -sf /etc/letsencrypt/live/$domain/fullchain.pem /etc/xray/xray.crt
    ln -sf /etc/letsencrypt/live/$domain/privkey.pem /etc/xray/xray.key
    echo "SSL berhasil dipasang untuk $domain"
else
    echo "Gagal memasang SSL!"
    exit 1
fi

# Menjadwalkan pembaruan SSL otomatis
(crontab -l 2>/dev/null; echo "0 0 * * 0 certbot renew --quiet && systemctl restart xray nginx trojan-go") | crontab -

# Verifikasi instalasi layanan
if ! command -v xray &>/dev/null || ! command -v trojan-go &>/dev/null || ! command -v nginx &>/dev/null; then
    echo "Ada kesalahan dalam instalasi Xray, Trojan-Go, atau Nginx. Silakan periksa log."
    exit 1
fi

# Informasi setup selesai
echo "Semua paket dan layanan telah berhasil diinstal dan dijalankan."

# Otomatis menjalankan menu setelah reboot
echo "/root/script.sh" >> /etc/profile
screen -dmS vpnmenu /root/script.sh

cat > /etc/systemd/system/vpn-menu.service <<EOF
[Unit]
Description=VPN Menu Auto Start
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /root/script.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl enable vpn-menu.service
systemctl start vpn-menu.service

# Buat layanan systemd untuk Xray dan Trojan-Go
cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xray run -c /etc/xray/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/trojan-go.service << EOF
[Unit]
Description=Trojan-Go Service
After=network.target

[Service]
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray trojan-go
systemctl restart xray trojan-go

# Fungsi untuk menyimpan akun ke file JSON
save_account() {
    echo "{\"username\": \"$1\", \"uuid\": \"$2\", \"quota\": \"$3\", \"limit_ip\": \"$4\", \"expired\": \"$5\"}" >> /etc/xray/accounts.json
}

# Fungsi pembuatan akun VPN
function buat_akun() {
    read -p "Pilih jenis akun (1: Vmess, 2: Vless, 3: Trojan-Go): " jenis
    read -p "Masukkan username: " username
    read -p "Masa aktif (hari): " masa_aktif
    read -p "Limit kuota (GB): " kuota
    read -p "Limit IP: " limit_ip
    
    uuid=$(cat /proc/sys/kernel/random/uuid)
    exp_date=$(date -d "+$masa_aktif days" +%Y-%m-%d)
    save_account "$username" "$uuid" "$kuota" "$limit_ip" "$exp_date"
    
    echo "\nAKUN BERHASIL DIBUAT\n"
    echo "Remarks          : $username"
    echo "Host/IP          : $DOMAIN"
    echo "Key              : $uuid"
    echo "Quota            : $kuota GB"
    echo "Limit IP         : $limit_ip"
    echo "Expired          : $exp_date"
    if [[ $jenis -eq 1 ]]; then
        link_tls="vmess://$(echo -n '{\"id\":\"'$uuid'\",\"aid\":0,\"host\":\"'$DOMAIN'\",\"path\":\"/'$username'-ws\",\"tls\":\"tls\"}' | base64)"
        link_non_tls="vmess://$(echo -n '{\"id\":\"'$uuid'\",\"aid\":0,\"host\":\"'$DOMAIN'\",\"path\":\"/'$username'-ws\",\"tls\":\"none\"}' | base64)"
        echo "Link TLS         : $link_tls"
        echo "Link Non-TLS     : $link_non_tls"
    elif [[ $jenis -eq 2 ]]; then
        link_tls="vless://$uuid@$DOMAIN:443?path=/$username-ws&security=tls&type=ws"
        link_non_tls="vless://$uuid@$DOMAIN:80?path=/$username-ws&security=none&type=ws"
        echo "Link TLS         : $link_tls"
        echo "Link Non-TLS     : $link_non_tls"
    else
        link_tls="trojan://$uuid@$DOMAIN:443?path=%2Ftrojan-ws&security=tls&type=ws"
        echo "Link TLS         : $link_tls"
    fi
    echo "Berakhir Pada    : $exp_date"
    echo "Press [ Enter ] to back on menu"
    read
}

# Fungsi untuk restart layanan
restart_service() {
    local service_name=$1
    echo "Restarting $service_name..."
    systemctl restart $service_name
    if systemctl is-active --quiet $service_name; then
        echo "$service_name berhasil direstart!"
    else
        echo "Gagal merestart $service_name! Periksa log di /var/log/vpn_script.log"
    fi
    systemctl status $service_name --no-pager -l | tee -a /var/log/vpn_script.log
}

while true; do
    clear
    echo "VPN PREMIUM By_MF-youend"
    echo
    echo "System OS      = $(lsb_release -ds)"
    echo "Core Cpu       = $(nproc)"
    echo "Server RAM     = $(free -m | awk 'NR==2{printf "%s/%s MB\n", $3, $2}')"
    echo "Uptime Server  = $(uptime -p)"
    echo "Domain         = $domain"
    echo "IP VPS         = $(curl -s ifconfig.me)"
    echo "ISP            = $(curl -s ipinfo.io/org)"
    echo "City           = $(curl -s ipinfo.io/city)"
    echo "Cpu Usage      = $(top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}')%"
    echo
    echo "1. Buat Akun Vmess Xray"
    echo "2. Hapus Akun Vmess Xray"
    echo "3. Perpanjang Akun Vmess Xray"
    echo "4. Cek Akun Vmess Xray"
    echo "5. Buat Akun Vless Xray"
    echo "6. Hapus Akun Vless Xray"
    echo "7. Perpanjang Akun Vless Xray"
    echo "8. Cek Akun Vless Xray"
    echo "9. Buat Akun Trojan Go"
    echo "10. Hapus Akun Trojan Go"
    echo "11. Perpanjang Akun Trojan Go"
    echo "12. Cek Akun Trojan Go"
    echo "13. Restart Xray"
    echo "14. Restart Trojan Go"
    echo "15. Ganti Domain"
    echo "16. Speed Test"
    echo "17. Cek Bandwidth"
    echo "18. Reboot VPS"
    echo "19. Keluar"
    echo 
    read -p "Pilih menu [1-19]: " pilihan

    case $pilihan in
        1) echo "Membuat Akun Vmess Xray..." ;;
        2) echo "Menghapus Akun Vmess Xray..." ;;
        3) echo "Memperpanjang Akun Vmess Xray..." ;;
        4) echo "Cek Akun Vmess Xray..." ;;
        5) echo "Membuat Akun Vless Xray..." ;;
        6) echo "Menghapus Akun Vless Xray..." ;;
        7) echo "Memperpanjang Akun Vless Xray..." ;;
        8) echo "Cek Akun Vless Xray..." ;;
        9) echo "Membuat Akun Trojan Go..." ;;
        10) echo "Menghapus Akun Trojan Go..." ;;
        11) echo "Memperpanjang Akun Trojan Go..." ;;
        12) echo "Cek Akun Trojan Go..." ;;
        13) restart_service "xray" ;;
        14) restart_service "trojan-go" ;;
        15) 
        read -p "Masukkan domain baru: " new_domain
if ! ping -c 1 -W 2 "$new_domain" &>/dev/null; then
    echo "Domain tidak valid atau tidak bisa diakses!"
else
    echo "$new_domain" > /etc/xray/domain
    if certbot certonly --standalone -d "$new_domain" --non-interactive --agree-tos -m admin@$new_domain; then
        systemctl restart nginx xray trojan-go
        echo "Domain berhasil diubah menjadi $new_domain"
    else
        echo "Gagal memperbarui SSL untuk domain baru!"
    fi
    ;;
        16) 
    if ! command -v speedtest &>/dev/null; then
        echo "Menginstal speedtest-cli..."
        apt update && apt install -y speedtest-cli
    fi
    speedtest
    ;;
    esac
    read -p "Tekan ENTER untuk kembali ke menu..."
done
