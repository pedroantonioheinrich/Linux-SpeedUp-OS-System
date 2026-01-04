#!/bin/bash

# ============================================================================
# SCRIPT DE OTIMIZAÇÃO PARA LINUX MINT - MELHORIA DE DESEMPENHO GLOBAL
# ============================================================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Funções de utilidade
print_header() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Este script requer privilégios sudo!${NC}"
        echo -e "Execute: sudo $0"
        exit 1
    fi
}

# ============================================================================
# 1. DIAGNÓSTICO INICIAL DO SISTEMA
# ============================================================================

diagnosticar_sistema() {
    print_header "DIAGNÓSTICO DO SISTEMA"
    
    echo -e "\n${PURPLE}=== INFORMAÇÕES DO SISTEMA ===${NC}"
    inxi -Fxxxz
    
    echo -e "\n${PURPLE}=== MEMÓRIA DISPONÍVEL ===${NC}"
    free -h
    
    echo -e "\n${PURPLE}=== USO DE DISCO ===${NC}"
    df -h
    
    echo -e "\n${PURPLE}=== TOP 10 PROCESSOS (CPU) ===${NC}"
    ps aux --sort=-%cpu | head -11
    
    echo -e "\n${PURPLE}=== TOP 10 PROCESSOS (MEMÓRIA) ===${NC}"
    ps aux --sort=-%mem | head -11
    
    echo -e "\n${PURPLE}=== TEMPERATURA DA CPU ===${NC}"
    sensors 2>/dev/null || echo "Instale lm-sensors: sudo apt install lm-sensors"
    
    echo -e "\n${PURPLE}=== LOGS DE ERROS RECENTES ===${NC}"
    journalctl -p 3 -xb --no-pager | tail -20
    
    echo -e "\n${PURPLE}=== SWAP USAGE ===${NC}"
    swapon --show
}

# ============================================================================
# 2. OTIMIZAÇÃO DE MEMÓRIA E SWAP
# ============================================================================

otimizar_memoria() {
    print_header "OTIMIZAÇÃO DE MEMÓRIA E SWAP"
    
    # Limpar caches de memória (seguro)
    print_info "Limpando caches de memória..."
    sync && echo 3 > /proc/sys/vm/drop_caches
    print_status "Caches limpos"
    
    # Verificar se já existe swap file
    if swapon --show | grep -q "/swapfile"; then
        print_info "Swap file já existe"
    else
        print_info "Criando swap file de 4GB..."
        
        # Desativar swap atual se existir
        swapoff -a
        
        # Criar swap file
        fallocate -l 4G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        
        # Adicionar ao fstab
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        
        print_status "Swap file de 4GB criado e ativado"
    fi
    
    # Otimizar parâmetros de swap
    print_info "Otimizando parâmetros de swap..."
    
    # Swappiness (0-100): menor valor = menos uso de swap
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    
    # Cache pressure (0-100): menor valor = mantém mais cache em memória
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
    
    # Dirty ratios (para escrita em disco)
    echo "vm.dirty_background_ratio=5" >> /etc/sysctl.conf
    echo "vm.dirty_ratio=10" >> /etc/sysctl.conf
    
    # Aplicar mudanças
    sysctl -p
    
    print_status "Parâmetros de swap otimizados"
    
    # Instalar e configurar zRAM (compressão de memória em RAM)
    print_info "Configurando zRAM (compressão de memória)..."
    apt install -y zram-tools
    
    # Configurar zRAM para usar 50% da RAM
    TOTAL_MEM=$(free -b | grep Mem: | awk '{print $2}')
    ZRAM_SIZE=$((TOTAL_MEM / 2))
    
    cat > /etc/default/zramswap << EOF
# Tamanho do zRAM (em bytes)
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF
    
    systemctl restart zramswap
    print_status "zRAM configurado"
}

# ============================================================================
# 3. OTIMIZAÇÃO DO SISTEMA DE ARQUIVOS
# ============================================================================

otimizar_filesystem() {
    print_header "OTIMIZAÇÃO DO SISTEMA DE ARQUIVOS"
    
    # Habilitar TRIM para SSDs
    print_info "Habilitando TRIM automático para SSDs..."
    systemctl enable fstrim.timer
    systemctl start fstrim.timer
    fstrim -av
    print_status "TRIM habilitado"
    
    # Otimizar montagens no fstab
    print_info "Otimizando opções de montagem no /etc/fstab..."
    
    # Backup do fstab atual
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d)
    
    # Para ext4: noatime,nodiratime,commit=60
    # Para SSD: discard
    sed -i '/ext4/s/defaults/defaults,noatime,nodiratime,commit=60,discard/' /etc/fstab
    
    print_status "Opções de montagem otimizadas"
    
    # Limpar logs antigos
    print_info "Limpando logs antigos..."
    journalctl --vacuum-time=7d
    print_status "Logs com mais de 7 dias removidos"
    
    # Limpar cache do pacote
    print_info "Limpando cache de pacotes..."
    apt clean
    apt autoclean
    print_status "Cache de pacotes limpo"
}

# ============================================================================
# 4. OTIMIZAÇÃO DE PROCESSOS E SERVIÇOS
# ============================================================================

otimizar_processos() {
    print_header "OTIMIZAÇÃO DE PROCESSOS E SERVIÇOS"
    
    # Identificar e desabilitar serviços desnecessários
    print_info "Analisando serviços em execução..."
    
    # Lista de serviços que podem ser desabilitados (dependendo do uso)
    SERVICES_TO_DISABLE="
    bluetooth.service
    cups.service
    cups-browsed.service
    avahi-daemon.service
    ModemManager.service
    teamviewerd.service
    "
    
    for service in $SERVICES_TO_DISABLE; do
        if systemctl is-active --quiet $service 2>/dev/null; then
            print_warning "Desativando serviço não essencial: $service"
            systemctl stop $service
            systemctl disable $service
        fi
    done
    
    # Otimizar prioridades de processos
    print_info "Otimizando prioridades de processos..."
    
    # Configurar nice value para processos críticos
    # Valores mais baixos = maior prioridade (-20 a 19)
    
    # Configurar ionice para I/O
    cat > /usr/local/bin/optimize_priorities << 'EOF'
#!/bin/bash
# Script para ajustar prioridades durante a inicialização

# Processos críticos (alta prioridade)
renice -n -5 -p $(pgrep Xorg) 2>/dev/null
renice -n -5 -p $(pgrep cinnamon) 2>/dev/null
renice -n -5 -p $(pgrep gnome-terminal) 2>/dev/null

# Processos em background (baixa prioridade)
renice -n 10 -p $(pgrep backup) 2>/dev/null
renice -n 10 -p $(pgrep tracker) 2>/dev/null
EOF
    
    chmod +x /usr/local/bin/optimize_priorities
    
    # Adicionar ao rc.local
    echo "/usr/local/bin/optimize_priorities" >> /etc/rc.local
    chmod +x /etc/rc.local
    
    print_status "Prioridades otimizadas"
    
    # Limitar uso de memória para processos problemáticos
    print_info "Configurando limites de recursos..."
    
    cat > /etc/security/limits.d/limits.conf << EOF
# Limites de recursos por usuário
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
* soft memlock unlimited
* hard memlock unlimited
EOF
    
    print_status "Limites de recursos configurados"
}

# ============================================================================
# 5. OTIMIZAÇÃO DE REDE
# ============================================================================

otimizar_rede() {
    print_header "OTIMIZAÇÃO DE REDE"
    
    print_info "Otimizando parâmetros de rede TCP..."
    
    cat >> /etc/sysctl.conf << 'EOF'
# Otimizações de rede
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 30000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
EOF
    
    sysctl -p
    print_status "Parâmetros de rede otimizados"
    
    # Otimizar DNS
    print_info "Configurando DNS rápido (Cloudflare + Google)..."
    
    cat > /etc/systemd/resolved.conf << EOF
[Resolve]
DNS=1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4
FallbackDNS=9.9.9.9 208.67.222.222
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
Cache=yes
DNSStubListener=yes
ReadEtcHosts=yes
EOF
    
    systemctl restart systemd-resolved
    print_status "DNS otimizado"
}

# ============================================================================
# 6. OTIMIZAÇÃO GRÁFICA (CINNAMON/MATE)
# ============================================================================

otimizar_graficos() {
    print_header "OTIMIZAÇÃO GRÁFICA"
    
    # Verificar se está usando Cinnamon
    if pgrep -x "cinnamon" > /dev/null; then
        print_info "Otimizando Cinnamon..."
        
        # Desativar efeitos visuais pesados
        gsettings set org.cinnamon.desktop.interface enable-animations false
        gsettings set org.cinnamon enable-animations false
        gsettings set org.cinnamon desktop-effects false
        
        # Otimizar trabalhos
        gsettings set org.cinnamon.desktop.background picture-options 'none'
        gsettings set org.cinnamon background-transition 'none'
        
        # Desativar thumbnails grandes
        gsettings set org.nemo.preferences show-image-thumbnails 'local-only'
        
        print_status "Cinnamon otimizado"
    fi
    
    # Otimizar drivers gráficos
    print_info "Otimizando configurações gráficas..."
    
    # Para Intel Graphics
    if lspci | grep -i "VGA" | grep -i "Intel"; then
        cat > /etc/X11/xorg.conf.d/20-intel.conf << 'EOF'
Section "Device"
    Identifier "Intel Graphics"
    Driver "intel"
    Option "TearFree" "true"
    Option "DRI" "3"
    Option "TripleBuffer" "true"
    Option "AccelMethod" "sna"
EndSection
EOF
        print_status "Driver Intel otimizado"
    fi
    
    # Para AMD
    if lspci | grep -i "VGA" | grep -i "AMD"; then
        cat > /etc/X11/xorg.conf.d/20-amd.conf << 'EOF'
Section "Device"
    Identifier "AMD Graphics"
    Driver "amdgpu"
    Option "TearFree" "true"
    Option "DRI" "3"
    Option "AccelMethod" "glamor"
EndSection
EOF
        print_status "Driver AMD otimizado"
    fi
    
    # Para NVIDIA (se instalado)
    if command -v nvidia-settings &> /dev/null; then
        print_info "Otimizando NVIDIA..."
        nvidia-settings --assign CurrentMetaMode="$(xrandr | grep connected | awk '{print $1}') : nvidia-auto-select"
        print_status "NVIDIA otimizado"
    fi
}

# ============================================================================
# 7. LIMPEZA E MANUTENÇÃO
# ============================================================================

executar_limpeza() {
    print_header "LIMPEZA E MANUTENÇÃO DO SISTEMA"
    
    print_info "Removendo pacotes desnecessários..."
    apt autoremove -y
    apt purge -y $(dpkg -l | grep '^rc' | awk '{print $2}')
    
    print_info "Limpando cache do usuário..."
    rm -rf ~/.cache/*
    rm -rf /tmp/*
    
    print_info "Limpando thumbnails..."
    rm -rf ~/.thumbnails
    rm -rf ~/.cache/thumbnails
    
    print_info "Limpando antigos kernels (mantendo apenas 2 mais recentes)..."
    apt install -y byobu
    sudo purge-old-kernels --keep 2
    
    print_info "Limpando arquivos de configuração órfãos..."
    deborphan | xargs apt purge -y
    
    print_info "Corrigindo permissões..."
    chown -R $SUDO_USER:$SUDO_USER /home/$SUDO_USER
    find /home/$SUDO_USER -type d -exec chmod 755 {} \;
    find /home/$SUDO_USER -type f -exec chmod 644 {} \;
    
    print_status "Limpeza concluída"
}

# ============================================================================
# 8. INSTALAÇÃO DE FERRAMENTAS ÚTEIS
# ============================================================================

instalar_ferramentas() {
    print_header "INSTALAÇÃO DE FERRAMENTAS DE MONITORAMENTO"
    
    print_info "Instalando ferramentas de diagnóstico..."
    apt update
    apt install -y \
        htop \
        iotop \
        nmon \
        nethogs \
        bpytop \
        ncdu \
        smartmontools \
        lm-sensors \
        psensor \
        inxi \
        neofetch \
        powertop \
        preload \
        earlyoom
    
    print_status "Ferramentas instaladas"
    
    # Configurar earlyoom (kill processos que consomem muita memória)
    print_info "Configurando earlyoom..."
    systemctl enable earlyoom
    systemctl start earlyoom
    
    # Configurar preload (pré-carregamento de aplicativos frequentes)
    systemctl enable preload
    systemctl start preload
    
    print_status "Serviços de otimização configurados"
}

# ============================================================================
# 9. MONITORAMENTO EM TEMPO REAL
# ============================================================================

configurar_monitoramento() {
    print_header "CONFIGURAÇÃO DE MONITORAMENTO"
    
    # Script de monitoramento personalizado
    cat > /usr/local/bin/monitor_system << 'EOF'
#!/bin/bash
# Monitor do sistema em tempo real

while true; do
    clear
    echo "=== MONITOR DO SISTEMA ==="
    echo "Data: $(date)"
    echo ""
    
    # CPU
    echo "CPU:"
    echo "  Uso: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
    echo "  Temp: $(sensors | grep Core | head -1 | awk '{print $3}')"
    echo ""
    
    # Memória
    echo "MEMÓRIA:"
    free -h | awk '/^Mem:/ {print "  Total: " $2 " | Usada: " $3 " | Livre: " $4 " | Swap: " $7}'
    echo ""
    
    # Disco
    echo "DISCO:"
    df -h / | tail -1 | awk '{print "  Uso: " $5 " | Disponível: " $4}'
    echo ""
    
    # Top processos
    echo "TOP PROCESSOS (CPU):"
    ps aux --sort=-%cpu | head -6 | tail -5 | awk '{print "  " $11 " (" $3 "%)"}'
    echo ""
    
    echo "TOP PROCESSOS (MEM):"
    ps aux --sort=-%mem | head -6 | tail -5 | awk '{print "  " $11 " (" $4 "%)"}'
    
    sleep 2
done
EOF
    
    chmod +x /usr/local/bin/monitor_system
    
    # Criar atalho no desktop
    cat > ~/Desktop/monitor.desktop << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Monitor do Sistema
Comment=Monitor em tempo real do sistema
Exec=gnome-terminal -- /usr/local/bin/monitor_system
Icon=utilities-system-monitor
Terminal=false
Categories=System;
EOF
    
    chmod +x ~/Desktop/monitor.desktop
    
    print_status "Monitoramento configurado"
    print_info "Execute 'monitor_system' para ver estatísticas em tempo real"
}

# ============================================================================
# 10. CRIAR SCRIPT DE MANUTENÇÃO AUTOMÁTICA
# ============================================================================

criar_script_manutencao() {
    print_header "CRIANDO SCRIPT DE MANUTENÇÃO AUTOMÁTICA"
    
    cat > /usr/local/bin/manutencao_diaria << 'EOF'
#!/bin/bash
# Script de manutenção diária automática

LOG_FILE="/var/log/manutencao.log"
echo "=== MANUTENÇÃO DIÁRIA - $(date) ===" >> $LOG_FILE

# Atualizar sistema
echo "Atualizando pacotes..." >> $LOG_FILE
apt update >> $LOG_FILE 2>&1
apt upgrade -y >> $LOG_FILE 2>&1

# Limpar cache
echo "Limpando caches..." >> $LOG_FILE
apt autoclean >> $LOG_FILE 2>&1
apt autoremove -y >> $LOG_FILE 2>&1

# Limpar logs antigos
echo "Limpando logs..." >> $LOG_FILE
journalctl --vacuum-time=3d >> $LOG_FILE 2>&1

# Verificar discos
echo "Verificando saúde do disco..." >> $LOG_FILE
df -h >> $LOG_FILE

# Verificar memória
echo "Verificando memória..." >> $LOG_FILE
free -h >> $LOG_FILE

echo "Manutenção concluída!" >> $LOG_FILE
echo "" >> $LOG_FILE
EOF
    
    chmod +x /usr/local/bin/manutencao_diaria
    
    # Agendar no cron
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/manutencao_diaria") | crontab -
    
    print_status "Script de manutenção automática criado"
    print_info "Executando diariamente às 2:00 AM"
}

# ============================================================================
# FUNÇÃO PRINCIPAL
# ============================================================================

main() {
    clear
    echo -e "${PURPLE}"
    echo "══════════════════════════════════════════════════════════════"
    echo "      OTIMIZADOR DE DESEMPENHO - LINUX MINT"
    echo "══════════════════════════════════════════════════════════════"
    echo -e "${NC}"
    
    # Verificar sudo
    check_sudo
    
    # Menu interativo
    echo -e "${YELLOW}Selecione as otimizações a aplicar:${NC}"
    echo "1) Diagnóstico do sistema"
    echo "2) Otimização completa (recomendado)"
    echo "3) Otimizar apenas memória"
    echo "4) Otimizar apenas gráficos"
    echo "5) Executar limpeza"
    echo "6) Instalar ferramentas"
    echo "7) Sair"
    echo ""
    
    read -p "Opção [1-7]: " choice
    
    case $choice in
        1)
            diagnosticar_sistema
            ;;
        2)
            echo -e "\n${RED}ATENÇÃO:${NC} Esta operação pode levar alguns minutos."
            read -p "Continuar? (s/N): " confirm
            if [[ $confirm == [sS] ]]; then
                otimizar_memoria
                otimizar_filesystem
                otimizar_processos
                otimizar_rede
                otimizar_graficos
                executar_limpeza
                instalar_ferramentas
                configurar_monitoramento
                criar_script_manutencao
                print_header "OTIMIZAÇÃO COMPLETA CONCLUÍDA"
                echo -e "${GREEN}Reinicie o sistema para aplicar todas as mudanças!${NC}"
            fi
            ;;
        3)
            otimizar_memoria
            ;;
        4)
            otimizar_graficos
            ;;
        5)
            executar_limpeza
            ;;
        6)
            instalar_ferramentas
            ;;
        7)
            echo "Saindo..."
            exit 0
            ;;
        *)
            echo "Opção inválida!"
            exit 1
            ;;
    esac
    
    # Finalização
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}       OTIMIZAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Ações recomendadas:${NC}"
    echo "1. Reinicie o sistema para aplicar todas as mudanças"
    echo "2. Execute 'monitor_system' para ver estatísticas em tempo real"
    echo "3. Verifique o log: /var/log/manutencao.log"
    echo ""
    echo -e "${YELLOW}Para desfazer as otimizações:${NC}"
    echo "1. Restaure backups em /etc/fstab.backup.*"
    echo "2. Remova arquivos em /etc/X11/xorg.conf.d/"
    echo "3. Execute: sudo swapoff /swapfile && sudo rm /swapfile"
    echo ""
}

# Executar função principal
main