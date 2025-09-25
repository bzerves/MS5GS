#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

clear

cat << "EOF"

  __  __ ____  ____   ____ ____
|  \/  / ___|| ___| / ___/ ___|
| |\/| \___ \|___ \| |  _\___ \
| |  | |___) |___) | |_| |___) |
|_|  |_|____/|____/ \____|____/

EOF

# Main menu
while true; do
    echo -e "\n${GREEN}=== MS5GS Menu de Instalação ===${NC}"
    echo ""
    echo "1. 🔍 Checar requisitos"
    echo "2. ⚙️  Configurar instalação"
    echo "3. 🗄️  Instalar MongoDB"
    echo "4. 💻 Instalar NodeJS"
    echo "5. 📡 Instalar Open5GS"
    echo "6. 🌐 Instalar Open5GS Web UI"
    echo "7. 🏥 Health Check"
    echo "8. 🔄 Reboot Services"
    echo "9. 👋 Sair"
    echo ""
    echo -e "${YELLOW}Nota: Versão PRO com suporte em https://meusys.com.br${NC}"
    echo ""
    read -p "Escolha uma opção (1-9) e pressione enter: " choice

    case $choice in
        1)
            echo -e "\n${YELLOW}Checando...${NC}"
            sudo bash scripts/check_requirements.sh
            ;;
        2)
            echo -e "\n${YELLOW}Rodando configuração...${NC}"
            sudo bash scripts/configure_installation.sh
            ;;
        3)
            echo -e "\n${YELLOW}Instalando MongoDB...${NC}"
            sudo bash scripts/install_mongodb.sh
            ;;
        4)
            echo -e "\n${YELLOW}Instalando NodeJS...${NC}"
            sudo bash scripts/install_nodejs.sh
            ;;
        5)
            echo -e "\n${YELLOW}Instalando Open5GS...${NC}"
            sudo bash scripts/install_open5gs.sh
            ;;
        6)
            echo -e "\n${YELLOW}Instalando Open5GS Web UI...${NC}"
            sudo bash scripts/install_webui.sh
            ;;
        7)
            echo -e "\n${YELLOW}Rodando health check...${NC}"
            sudo bash scripts/health_check.sh
            ;;
        8)
            echo -e "\n${YELLOW}Rebooting Open5GS services...${NC}"
            sudo bash scripts/reboot_services.sh
            ;;
        9)
            echo -e "\n${GREEN}Saindo...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please select 1-9.${NC}"
            ;;
    esac
done
