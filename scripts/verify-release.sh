#!/bin/bash
set -e

# Verify Deadbolt release authenticity
# This script helps users verify downloaded releases
# Usage: ./verify-release.sh <binary-file>

BINARY_FILE="$1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "======================================"
echo "Deadbolt Release Verification"
echo "======================================"
echo ""

# Check if binary file was provided
if [ -z "$BINARY_FILE" ]; then
    echo -e "${RED}Error: No binary file specified${NC}"
    echo ""
    echo "Usage: $0 <binary-file>"
    echo ""
    echo "Example:"
    echo "  $0 deadbolt-linux-x64.tar.gz"
    echo "  $0 deadbolt-android.apk"
    echo "  $0 deadbolt-windows-x64.zip"
    echo ""
    exit 1
fi

# Check if binary file exists
if [ ! -f "$BINARY_FILE" ]; then
    echo -e "${RED}Error: File '$BINARY_FILE' not found${NC}"
    exit 1
fi

# Check if GPG is installed
if ! command -v gpg &> /dev/null; then
    echo -e "${RED}Error: GPG not found. Please install GnuPG.${NC}"
    echo ""
    echo "Installation:"
    echo "  Ubuntu/Debian: sudo apt install gnupg"
    echo "  macOS: brew install gnupg"
    echo "  Windows: Install Gpg4win from https://gpg4win.org/"
    echo ""
    exit 1
fi

# Check if sha256sum is installed
if ! command -v sha256sum &> /dev/null; then
    echo -e "${RED}Error: sha256sum not found${NC}"
    exit 1
fi

BINARY_DIR=$(dirname "$BINARY_FILE")
BINARY_NAME=$(basename "$BINARY_FILE")

# Check for verification files in the same directory
SHA256SUMS_FILE="${BINARY_DIR}/SHA256SUMS"
SHA256SUMS_ASC_FILE="${BINARY_DIR}/SHA256SUMS.asc"

echo -e "${BLUE}Binary file: $BINARY_NAME${NC}"
echo -e "${BLUE}Directory: $BINARY_DIR${NC}"
echo ""

# Check if SHA256SUMS exists
if [ ! -f "$SHA256SUMS_FILE" ]; then
    echo -e "${RED}Error: SHA256SUMS not found in the same directory${NC}"
    echo ""
    echo "Please download SHA256SUMS from the same release:"
    echo "  https://github.com/frijolo/deadbolt/releases"
    echo ""
    exit 1
fi

# Check if SHA256SUMS.asc exists
if [ ! -f "$SHA256SUMS_ASC_FILE" ]; then
    echo -e "${RED}Error: SHA256SUMS.asc not found in the same directory${NC}"
    echo ""
    echo "Please download SHA256SUMS.asc from the same release:"
    echo "  https://github.com/frijolo/deadbolt/releases"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Found SHA256SUMS${NC}"
echo -e "${GREEN}✓ Found SHA256SUMS.asc${NC}"
echo ""

# Step 1: Check if GPG key is imported
echo -e "${YELLOW}[Step 1/3] Checking for maintainer's GPG key...${NC}"

# Try to verify signature to see if key is available
if gpg --verify "$SHA256SUMS_ASC_FILE" "$SHA256SUMS_FILE" 2>&1 | grep -q "public key not found"; then
    echo -e "${YELLOW}Maintainer's GPG key not found in your keyring${NC}"
    echo ""
    echo "Importing public key from repository..."

    # Try to download from GitHub
    if curl -sL https://raw.githubusercontent.com/frijolo/deadbolt/main/GPG_PUBLIC_KEY.asc | gpg --import; then
        echo -e "${GREEN}✓ GPG key imported successfully${NC}"
    else
        echo -e "${RED}✗ Failed to import GPG key automatically${NC}"
        echo ""
        echo "Please import manually:"
        echo "  curl -sL https://raw.githubusercontent.com/frijolo/deadbolt/main/GPG_PUBLIC_KEY.asc | gpg --import"
        echo ""
        exit 1
    fi
else
    echo -e "${GREEN}✓ GPG key already in keyring${NC}"
fi

echo ""

# Step 2: Verify GPG signature
echo -e "${YELLOW}[Step 2/3] Verifying GPG signature on SHA256SUMS...${NC}"
echo ""

if gpg --verify "$SHA256SUMS_ASC_FILE" "$SHA256SUMS_FILE" 2>&1 | tee /tmp/gpg_verify.log; then
    echo ""

    # Check for "Good signature"
    if grep -q "Good signature" /tmp/gpg_verify.log; then
        echo -e "${GREEN}✓ GPG signature is VALID${NC}"

        # Extract signer info
        SIGNER=$(grep "Good signature" /tmp/gpg_verify.log | sed 's/.*from "\(.*\)".*/\1/')
        echo -e "${GREEN}  Signed by: $SIGNER${NC}"

        # Warn about trust if not certified
        if grep -q "not certified with a trusted signature" /tmp/gpg_verify.log; then
            echo -e "${YELLOW}  Note: Key is not marked as trusted (this is normal)${NC}"
            echo -e "${YELLOW}  Verify the fingerprint matches official sources${NC}"
        fi
    else
        echo -e "${RED}✗ GPG signature verification FAILED${NC}"
        echo ""
        echo "The signature is invalid. This file may have been tampered with."
        echo "DO NOT use this binary."
        echo ""
        exit 1
    fi
else
    echo ""
    echo -e "${RED}✗ GPG verification failed${NC}"
    echo ""
    exit 1
fi

rm -f /tmp/gpg_verify.log
echo ""

# Step 3: Verify checksum
echo -e "${YELLOW}[Step 3/3] Verifying binary checksum...${NC}"

cd "$BINARY_DIR"
if sha256sum -c SHA256SUMS --ignore-missing 2>&1 | grep "$BINARY_NAME"; then
    if sha256sum -c SHA256SUMS --ignore-missing 2>&1 | grep -q "$BINARY_NAME: OK"; then
        echo -e "${GREEN}✓ Checksum is VALID${NC}"
    else
        echo -e "${RED}✗ Checksum verification FAILED${NC}"
        echo ""
        echo "The file's checksum does not match. The file may be corrupted or tampered with."
        echo "DO NOT use this binary."
        echo ""
        exit 1
    fi
else
    echo -e "${RED}✗ File not found in SHA256SUMS${NC}"
    echo ""
    echo "The binary filename doesn't match any entry in SHA256SUMS."
    echo "Make sure you downloaded the correct files from the same release."
    echo ""
    exit 1
fi

cd - > /dev/null

echo ""
echo "======================================"
echo -e "${GREEN}✓ VERIFICATION SUCCESSFUL${NC}"
echo "======================================"
echo ""
echo -e "${GREEN}$BINARY_NAME is authentic and safe to use${NC}"
echo ""
echo "This binary was:"
echo "  ✓ Signed by the Deadbolt maintainer"
echo "  ✓ Not tampered with since signing"
echo "  ✓ Verified against cryptographic checksums"
echo ""
echo "You can now safely install and use this binary."
echo ""
