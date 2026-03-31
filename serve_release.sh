#!/bin/bash

# Serves the contents of releases/ over a local HTTP server.
# Ctrl+C stops the server automatically.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PORT=8080

cleanup() {
    echo -e "\n${YELLOW}Stopping server...${NC}"
    kill "$SERVER_PID" 2>/dev/null || true
    echo -e "${GREEN}Server stopped.${NC}"
    exit 0
}
trap cleanup SIGINT SIGTERM

if [ ! -d releases ] || [ -z "$(ls -A releases 2>/dev/null)" ]; then
    echo -e "${YELLOW}No files in releases/. Run build_release.sh first.${NC}"
    exit 1
fi

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Deadbolt Release Server${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}\n"

( cd releases && python3 -m http.server "$PORT" > /dev/null 2>&1 ) &
SERVER_PID=$!

sleep 1

echo -e "${GREEN}✓ Server started${NC}\n"
echo -e "  ${GREEN}http://${HOSTNAME}:${PORT}/${NC}\n"
echo -e "${BLUE}────────────────────────────────────────${NC}"
echo -e "Puerto: ${GREEN}$PORT${NC}   PID: ${GREEN}$SERVER_PID${NC}"
echo -e "${BLUE}────────────────────────────────────────${NC}\n"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}\n"

wait "$SERVER_PID"
