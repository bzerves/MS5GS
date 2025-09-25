#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source the logo
source scripts/logo.sh

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

function draw_menu() {
    clear
    draw_logo
    echo -e "\n${GREEN}=== MS5GS Control Panel ===${NC}"
    echo ""
    echo "1. 📊 Ver EPC Throughput"
    echo "2. 📶 Ver eNB Status"
    echo "3. 📱 Ver UE Status"
    echo "4. 📝 Live Tail MME (Mobile Management Entity)"
    echo "5. 📝 Live Tail SMF (Session Management Function)"
    echo "6. 👋 Sair"
    echo ""
    echo -e "${YELLOW}Nota: Versão PRO com suporte disponível em https://meusys.com.br${NC}"
    echo ""
}

# Initial draw
draw_menu

# Main menu
while true; do
    read -p "Escolha uma opção (1-6) e pressione enter: " choice

    case $choice in
        1)
            sudo bash scripts/speedometer.sh
            draw_menu
            ;;
        2)
            sudo bash scripts/monitor_enbs.sh
            draw_menu
            ;;
        3)
            sudo bash scripts/monitor_ues.sh
            draw_menu
            ;;
        4)
            sudo journalctl -u open5gs-mmed -f
            draw_menu
            ;;
        5)
            sudo journalctl -u open5gs-smfd -f
            draw_menu
            ;;
        6)
            echo -e "\n${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Inválido, escolha de 1-6.${NC}"
            ;;
    esac
done 
