#!/bin/bash
set -e

# Sign release checksums with GPG
# This script is a manual fallback for local signing if GitHub Actions fails
# Usage: ./scripts/sign-checksums.sh [release-directory]

RELEASE_DIR="${1:-release}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "Deadbolt Release Signing Script"
echo "======================================"
echo ""

# Check if release directory exists
if [ ! -d "$RELEASE_DIR" ]; then
    echo -e "${RED}Error: Release directory '$RELEASE_DIR' not found${NC}"
    echo "Usage: $0 [release-directory]"
    exit 1
fi

# Check if any release files exist
if ! ls "$RELEASE_DIR"/*.{apk,tar.gz,zip} 1> /dev/null 2>&1; then
    echo -e "${RED}Error: No release files found in '$RELEASE_DIR'${NC}"
    echo "Expected files: *.apk, *.tar.gz, *.zip"
    exit 1
fi

# Check if GPG is installed
if ! command -v gpg &> /dev/null; then
    echo -e "${RED}Error: GPG not found. Please install GnuPG.${NC}"
    exit 1
fi

# List available GPG secret keys
echo -e "${YELLOW}Available GPG keys:${NC}"
gpg --list-secret-keys --keyid-format=long
echo ""

# Prompt for key ID
echo -e "${YELLOW}Enter your GPG key ID (e.g., ABCD1234EFGH5678):${NC}"
read -r KEY_ID

if [ -z "$KEY_ID" ]; then
    echo -e "${RED}Error: No key ID provided${NC}"
    exit 1
fi

# Verify key exists
if ! gpg --list-secret-keys "$KEY_ID" &> /dev/null; then
    echo -e "${RED}Error: Key ID '$KEY_ID' not found${NC}"
    exit 1
fi

echo ""
echo "Using key: $KEY_ID"
echo ""

# Generate checksums
echo -e "${YELLOW}[1/3] Generating SHA256 checksums...${NC}"
cd "$RELEASE_DIR"
sha256sum *.apk *.tar.gz *.zip 2>/dev/null > SHA256SUMS || true

if [ ! -s SHA256SUMS ]; then
    echo -e "${RED}Error: Failed to generate checksums${NC}"
    exit 1
fi

echo -e "${GREEN}Checksums generated:${NC}"
cat SHA256SUMS
echo ""

# Sign the checksums file
echo -e "${YELLOW}[2/3] Signing checksums with GPG...${NC}"
echo "You may be prompted for your GPG passphrase."
echo ""

# Remove old signature if it exists
rm -f SHA256SUMS.asc

# Sign with GPG (detached signature, ASCII armor)
if gpg --default-key "$KEY_ID" --armor --detach-sign --output SHA256SUMS.asc SHA256SUMS; then
    echo -e "${GREEN}Signature created successfully${NC}"
else
    echo -e "${RED}Error: GPG signing failed${NC}"
    exit 1
fi

echo ""

# Verify the signature
echo -e "${YELLOW}[3/3] Verifying signature...${NC}"
if gpg --verify SHA256SUMS.asc SHA256SUMS; then
    echo ""
    echo -e "${GREEN}✓ Signature verified successfully${NC}"
else
    echo ""
    echo -e "${RED}✗ Signature verification failed${NC}"
    exit 1
fi

echo ""
echo "======================================"
echo -e "${GREEN}Signing Complete!${NC}"
echo "======================================"
echo ""
echo "Files created:"
echo "  - SHA256SUMS       (checksums)"
echo "  - SHA256SUMS.asc   (GPG signature)"
echo ""
echo "To verify locally:"
echo "  gpg --verify SHA256SUMS.asc SHA256SUMS"
echo "  sha256sum -c SHA256SUMS"
echo ""
echo "Next steps:"
echo "  1. Upload all files to GitHub Release"
echo "  2. Include SHA256SUMS and SHA256SUMS.asc"
echo "  3. Update release notes with verification instructions"
echo ""
