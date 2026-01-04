#!/bin/bash
# SOLUÇÃO RÁPIDA PARA TRAVAMENTOS NO LINUX MINT

# Executar como sudo
if [ "$EUID" -ne 0 ]; then
    echo "Execute com sudo: sudo $0"
    exit 1
fi

echo "=== SOLUÇÃO RÁPIDA PARA TRAVAMENTOS ==="

# 1. Matar processos problemáticos
echo "1. Matando processos problemáticos..."
pkill -f chrome 2>/dev/null
pkill -f firefox 2>/dev/null
pkill -f java 2>/dev/null
pkill -f cinnamon-settings 2>/dev/null

# 2. Liberar memória
echo "2. Liberando memória..."
sync && echo 3 > /proc/sys/vm/drop_caches

# 3. Verificar swap
echo "3. Verificando swap..."
swapon --show || {
    echo "Criando swap temporário..."
    fallocate -l 2G /swap_temp
    chmod 600 /swap_temp
    mkswap /swap_temp
    swapon /swap_temp
}

# 4. Redefinir interface gráfica
echo "4. Redefinindo interface gráfica..."
pkill -HUP cinnamon 2>/dev/null || pkill -HUP mate-session 2>/dev/null

# 5. Limpar cache do usuário
echo "5. Limpando cache..."
rm -rf ~/.cache/*
rm -rf /tmp/*

echo "=== CONCLUÍDO! ==="
echo "O sistema deve estar mais responsivo agora."