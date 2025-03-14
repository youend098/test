#!/bin/bash

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
    echo "6. Keluar"
    echo "====================================="
    read -p "Pilih opsi [1-6]: " opsi

    case $opsi in
        1)
            read -p "Masukkan username: " user
            read -p "Masukkan password: " pass
            echo -e "$pass\n$pass" | sudo adduser --gecos "" $user
            echo "Akun VPN untuk $user telah ditambahkan."
            ;;
        2)
            read -p "Masukkan username yang ingin dihapus: " user
            sudo deluser --remove-home $user
            echo "Akun $user telah dihapus."
            ;;
        3)
            sudo systemctl status xray
            read -p "Tekan enter untuk kembali ke menu..." enterKey
            ;;
        4)
            echo "== Penggunaan CPU & RAM =="
            top -b -n1 | head -n 10
            echo "== Penggunaan Disk =="
            df -h
            echo "== Penggunaan Bandwidth =="
            vnstat -i eth0
            read -p "Tekan enter untuk kembali ke menu..." enterKey
            ;;
        5)
            sudo systemctl restart xray
            echo "Xray telah direstart."
            ;;
        6)
            echo "Keluar dari menu."
            exit 0
            ;;
        *)
            echo "Pilihan tidak valid, silakan coba lagi."
            ;;
    esac
    sleep 2
done
