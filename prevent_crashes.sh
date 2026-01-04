#!/bin/bash
# SCRIPT DE PREVENÇÃO DE TRAVAMENTOS - VERSÃO CORRIGIDA

CONFIG_DIR="$HOME/.config/auto_fix"
LOG_FILE="$CONFIG_DIR/prevent_crashes.log"
mkdir -p $CONFIG_DIR

echo "=== PREVENT CRASHES INICIADO em $(date) ===" >> $LOG_FILE
echo "PID: $$" >> $LOG_FILE

# Função para obter memória livre de forma segura
get_free_memory() {
    free -m | awk '/^Mem:/ {print $7}' 2>/dev/null || echo "0"
}

# Função para obter temperatura de forma segura
get_cpu_temp() {
    local temp
    if command -v sensors &> /dev/null; then
        temp=$(sensors 2>/dev/null | grep -E 'Core 0|Package id 0|Tdie' | head -1 | grep -oE '[0-9]+\.[0-9]+°C' | cut -d. -f1)
        if [ -n "$temp" ]; then
            echo "$temp"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# Função para limpar caches de forma segura
safe_clear_cache() {
    if [ "$EUID" -eq 0 ]; then
        sync && echo 1 > /proc/sys/vm/drop_caches 2>/dev/null
        echo "[$(date)] Caches limpos (root)" >> $LOG_FILE
    else
        echo "[$(date)] Não é possível limpar caches (sem root)" >> $LOG_FILE
    fi
}

# Função para enviar SIGCONT para processos travados
unfreeze_processes() {
    local frozen_pids
    frozen_pids=$(ps -eo pid,stat,comm | awk '/D/ && !/\[.*\]/ {print $1}' 2>/dev/null)
    
    if [ -n "$frozen_pids" ]; then
        echo "[$(date)] Processos travados encontrados: $frozen_pids" >> $LOG_FILE
        for pid in $frozen_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                kill -CONT "$pid" 2>/dev/null
                echo "[$(date)] SIGCONT enviado para PID $pid" >> $LOG_FILE
            fi
        done
    fi
}

# Função para monitorar e matar processos problemáticos
monitor_problematic_processes() {
    # Lista de processos conhecidos por causar travamentos
    PROBLEMATIC_PATTERNS="chrome|firefox|java|cinnamon|mate|evolution|thunderbird"
    
    # Verificar processos consumindo muita CPU (>80% por mais de 30s)
    ps aux | awk 'NR>1 {if($3 > 80.0) print $2, $11}' | while read pid process; do
        if echo "$process" | grep -qE "$PROBLEMATIC_PATTERNS"; then
            echo "[$(date)] Processo $process (PID $pid) usando >80% CPU" >> $LOG_FILE
            # Reduzir prioridade
            renice +10 -p "$pid" 2>/dev/null
        fi
    done
    
    # Verificar processos consumindo muita memória (>1GB)
    ps aux | awk 'NR>1 {if($6 > 1048576) print $2, $11, $6/1024"MB"}' | while read pid process mem; do
        if echo "$process" | grep -qE "$PROBLEMATIC_PATTERNS"; then
            echo "[$(date)] Processo $process (PID $pid) usando $mem" >> $LOG_FILE
        fi
    done
}

# Função para verificar espaço em disco
check_disk_space() {
    local usage
    usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$usage" -gt 90 ]; then
        echo "[$(date)] AVISO: Disco com $usage% de uso" >> $LOG_FILE
        # Limpar cache de pacotes
        apt-get clean 2>/dev/null
        rm -rf ~/.cache/thumbnails/*
    fi
}

# Função para verificar integridade do sistema de arquivos
check_filesystem() {
    # Verificar se /tmp está montado corretamente
    if ! mount | grep -q " /tmp "; then
        echo "[$(date)] AVISO: /tmp não está montado" >> $LOG_FILE
    fi
    
    # Verificar se swap está ativo
    if ! swapon --show | grep -q .; then
        echo "[$(date)] AVISO: Swap não está ativo" >> $LOG_FILE
    fi
}

# Função para otimizar memória
optimize_memory() {
    local mem_free
    mem_free=$(get_free_memory)
    
    # Log do status da memória
    echo "[$(date)] Memória livre: ${mem_free}MB" >> $LOG_FILE
    
    # Se memória muito baixa (<100MB)
    if [ "$mem_free" -lt 100 ] 2>/dev/null; then
        echo "[$(date)] Memória baixa: ${mem_free}MB - Tomando ações..." >> $LOG_FILE
        
        # 1. Limpar caches de página
        safe_clear_cache
        
        # 2. Matar processos Chrome/Firefox se memória muito baixa
        if [ "$mem_free" -lt 50 ] 2>/dev/null; then
            echo "[$(date)] Memória crítica: matando processos pesados..." >> $LOG_FILE
            pkill -f chrome 2>/dev/null
            pkill -f firefox 2>/dev/null
        fi
        
        # 3. Forçar compactação de memória (se zram configurado)
        if [ -f /sys/block/zram0/comp_algorithm ]; then
            echo "[$(date)] Forçando compactação zram..." >> $LOG_FILE
            echo 1 > /sys/block/zram0/memory_compaction 2>/dev/null
        fi
    fi
}

# Função para controle de temperatura
control_temperature() {
    local temp
    temp=$(get_cpu_temp)
    
    if [ -n "$temp" ] && [ "$temp" -gt 0 ] 2>/dev/null; then
        echo "[$(date)] Temperatura CPU: ${temp}°C" >> $LOG_FILE
        
        if [ "$temp" -gt 80 ]; then
            echo "[$(date)] Temperatura ALTA: ${temp}°C - Reduzindo carga" >> $LOG_FILE
            
            # Reduzir frequência da CPU
            if command -v cpufreq-set &> /dev/null; then
                cpufreq-set -g powersave 2>/dev/null
            fi
            
            # Reduzir prioridade de processos pesados
            ps aux | awk '$3 > 30 {print $2}' | xargs -r renice +5 2>/dev/null
        fi
    fi
}

# Função principal de monitoramento
main_monitor_loop() {
    local cycle=0
    
    while true; do
        echo "=== Ciclo $cycle - $(date) ===" >> $LOG_FILE
        
        # Executar verificações
        optimize_memory
        unfreeze_processes
        control_temperature
        check_disk_space
        check_filesystem
        
        # Monitorar processos problemáticos a cada 10 ciclos
        if [ $((cycle % 10)) -eq 0 ]; then
            monitor_problematic_processes
        fi
        
        # Limpar log se muito grande (manter últimos 1000 linhas)
        if [ $(wc -l < "$LOG_FILE") -gt 1000 ]; then
            tail -500 "$LOG_FILE" > "$LOG_FILE.tmp"
            mv "$LOG_FILE.tmp" "$LOG_FILE"
        fi
        
        # Incrementar ciclo e esperar
        cycle=$((cycle + 1))
        sleep 30
    done
}

# Sinal de trap para limpeza ao sair
cleanup() {
    echo "=== PREVENT CRASHES FINALIZADO em $(date) ===" >> $LOG_FILE
    exit 0
}

trap cleanup EXIT INT TERM

# Verificar se já está rodando
if [ -f "/tmp/prevent_crashes.pid" ]; then
    old_pid=$(cat /tmp/prevent_crashes.pid)
    if kill -0 "$old_pid" 2>/dev/null; then
        echo "Script já está rodando com PID $old_pid"
        echo "Matando processo antigo e iniciando novo..."
        kill "$old_pid" 2>/dev/null
        sleep 2
    fi
fi

# Criar arquivo PID
echo $$ > /tmp/prevent_crashes.pid

# Iniciar loop principal
echo "Iniciando prevenção de travamentos..."
echo "Log: $LOG_FILE"
echo "PID: $$"
echo "Pressione Ctrl+C para parar"

main_monitor_loop