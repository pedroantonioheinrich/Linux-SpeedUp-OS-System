#!/bin/bash
# SCRIPT DE PREVENÇÃO DE TRAVAMENTOS

CONFIG_DIR="$HOME/.config/auto_fix"
mkdir -p $CONFIG_DIR

# Monitorar em segundo plano
while true; do
    # Verificar uso de memória
    MEM_FREE=$(free -m | awk '/^Mem:/ {print $7}')
    
    if [ $MEM_FREE -lt 100 ]; then
        echo "[$(date)] Memória baixa: ${MEM_FREE}MB - Limpando caches"
        sync && echo 1 > /proc/sys/vm/drop_caches
    fi
    
    # Verificar processos travados
    if ps aux | grep -q "D\s\+[0-9]"; then
        echo "[$(date)] Processo travado detectado - Enviando SIGCONT"
        ps aux | awk '/D\s+[0-9]/ {print $2}' | xargs kill -CONT 2>/dev/null
    fi
    
    # Verificar temperatura
    TEMP=$(sensors | grep 'Core 0' | awk '{print $3}' | sed 's/+//;s/°C//')
    if [ ${TEMP%.*} -gt 80 ]; then
        echo "[$(date)] Temperatura alta: ${TEMP}°C - Reduzindo carga"
        cpufreq-set -g powersave 2>/dev/null
    fi
    
    sleep 30
done