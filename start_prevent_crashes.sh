#!/bin/bash
# MONITOR LEVE - Usa poucos recursos

check_interval=45  # Segundos
max_log_size=1000  # Linhas

# Criar diretório de logs
log_dir="$HOME/.system_monitor"
log_file="$log_dir/monitor.log"
mkdir -p "$log_dir"

# Função segura para obter valores numéricos
safe_number() {
    echo "$1" | grep -oE '[0-9]+' || echo "0"
}

# Loop principal
while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    log_entry="[$timestamp]"
    
    # 1. Memória
    mem_info=$(free -m 2>/dev/null | awk '/^Mem:/')
    if [ -n "$mem_info" ]; then
        mem_free=$(echo "$mem_info" | awk '{print $7}')
        mem_free=$(safe_number "$mem_free")
        log_entry="$log_entry Mem:${mem_free}MB"
        
        # Ação: se memória muito baixa
        if [ "$mem_free" -lt 100 ]; then
            # Limpar cache de thumbnails do usuário
            rm -f "$HOME/.cache/thumbnails/fail"/* 2>/dev/null
            rm -f "$HOME/.thumbnails"/* 2>/dev/null
            log_entry="$log_entry [LOW_MEM]"
        fi
    fi
    
    # 2. Swap
    swap_info=$(free -m 2>/dev/null | awk '/^Swap:/')
    if [ -n "$swap_info" ]; then
        swap_used=$(echo "$swap_info" | awk '{print $3}')
        swap_used=$(safe_number "$swap_used")
        log_entry="$log_entry Swap:${swap_used}MB"
    fi
    
    # 3. Processos travados (estado D)
    d_count=$(ps -eo stat 2>/dev/null | grep -c 'D' || echo "0")
    if [ "$d_count" -gt 0 ]; then
        log_entry="$log_entry D-procs:${d_count}"
        
        # Tentar recuperar processos travados
        if [ "$EUID" -eq 0 ]; then
            ps -eo pid,stat | awk '$2 ~ /D/ {print $1}' | xargs -r kill -CONT 2>/dev/null
        fi
    fi
    
    # 4. Carga do sistema
    load=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    log_entry="$log_entry Load:$load"
    
    # 5. Temperatura (se disponível)
    if type sensors >/dev/null 2>&1; then
        temp=$(sensors 2>/dev/null | grep -E 'Core 0|Tdie' | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [ -n "$temp" ]; then
            temp_int=$(echo "$temp" | cut -d. -f1)
            log_entry="$log_entry Temp:${temp_int}°C"
        fi
    fi
    
    # Adicionar ao log
    echo "$log_entry" >> "$log_file"
    
    # Manter log pequeno
    if [ $(wc -l < "$log_file") -gt "$max_log_size" ]; then
        tail -500 "$log_file" > "${log_file}.tmp"
        mv "${log_file}.tmp" "$log_file"
    fi
    
    # Esperar
    sleep "$check_interval"
done