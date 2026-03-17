#!/bin/bash

# Sirve el contenido de releases/ por HTTP local.
# Ctrl+C cierra el servidor automáticamente.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PORT=8080

cleanup() {
    echo -e "\n${YELLOW}Cerrando servidor...${NC}"
    kill "$SERVER_PID" 2>/dev/null || true
    echo -e "${GREEN}Servidor cerrado.${NC}"
    exit 0
}
trap cleanup SIGINT SIGTERM

if [ ! -d releases ] || [ -z "$(ls -A releases 2>/dev/null)" ]; then
    echo -e "${YELLOW}No hay archivos en releases/. Ejecuta build_release.sh primero.${NC}"
    exit 1
fi

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Deadbolt Release Server${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}\n"

( cd releases && python3 -m http.server "$PORT" > /dev/null 2>&1 ) &
SERVER_PID=$!

sleep 1

echo -e "${GREEN}✓ Servidor iniciado${NC}\n"
echo -e "  ${GREEN}http://${HOSTNAME}:${PORT}/${NC}\n"
echo -e "${BLUE}────────────────────────────────────────${NC}"
echo -e "Puerto: ${GREEN}$PORT${NC}   PID: ${GREEN}$SERVER_PID${NC}"
echo -e "${BLUE}────────────────────────────────────────${NC}\n"
echo -e "${YELLOW}Presiona Ctrl+C para detener${NC}\n"

wait "$SERVER_PID"
