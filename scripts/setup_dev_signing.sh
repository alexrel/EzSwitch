#!/bin/bash
# ============================================================================
# setup_dev_signing.sh
# ----------------------------------------------------------------------------
# Sets up a stable codesigning identity so that builds of EzSwitch always
# produce the same signature. This prevents macOS from treating each new
# build as a brand-new application and forcing you to re-grant
# Accessibility / Input Monitoring permissions after every build.
#
# Strategies (tried in order):
#
#   1. Personal Team (recommended, free, $0)
#      Looks for an existing "Apple Development" certificate that Xcode
#      creates automatically once you sign in with an Apple ID.
#      If found, this is used as the signing identity.
#
#   2. Self-signed via Keychain Access (manual, ~2 minutes)
#      Provides step-by-step GUI instructions to create a code-signing
#      certificate yourself using macOS's built-in Keychain Access app.
#
# Usage:
#   ./scripts/setup_dev_signing.sh
#
# Re-run this script any time to verify or update the setup.
# ============================================================================

set -euo pipefail

CERT_NAME="EzSwitch Dev"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "$1"; }
ok()  { log "${GREEN}✅ $1${NC}"; }
warn(){ log "${YELLOW}⚠️  $1${NC}"; }
fail(){ log "${RED}❌ $1${NC}"; exit 1; }
hr()  { log "${BLUE}─────────────────────────────────────────────${NC}"; }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
log ""
log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
log "${BLUE}🔐 EzSwitch — Stable Signing Setup${NC}"
log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

[ "$(uname)" = "Darwin" ] || fail "This script must be run on macOS"

# Unlock keychain
log "${YELLOW}🔓 Unlocking login keychain…${NC}"
security unlock-keychain -p "" "$KEYCHAIN" 2>/dev/null || \
    log "${YELLOW}   (keychain may already be unlocked)${NC}"

# ---------------------------------------------------------------------------
# Strategy 1: Apple Development (Personal Team or paid developer account)
# ---------------------------------------------------------------------------
log ""
log "${YELLOW}🔍 Looking for existing Apple Development certificate (Personal Team)…${NC}"
hr
# Match any identity whose name starts with "Apple Development".
# Real names look like: "Apple Development: rel@example.com (TEAMID)"
APPLE_DEV=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E '"Apple Development' | head -1 || true)

if [ -n "$APPLE_DEV" ]; then
    # Output line format: "  1) ABCDEF1234... \"Apple Development: ...\""
    # Field 1 = "1)"  (index), Field 2 = hash, Field 3+ = quoted name
    HASH=$(echo "$APPLE_DEV" | awk '{print $2}')
    NAME=$(echo "$APPLE_DEV" | sed -E 's/.*"([^"]+)".*/\1/')
    ok "Found Apple Development certificate"
    log "  Name: ${GREEN}$NAME${NC}"
    log "  Hash: ${GREEN}$HASH${NC}"
    log ""
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${GREEN}✅ Setup complete! Using \"$NAME\" for stable signing.${NC}"
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    log "Just run ${BLUE}./build.sh${NC} and macOS will keep your permissions across builds."
    exit 0
fi
warn "No Apple Development certificate found"

# ---------------------------------------------------------------------------
# Strategy 2: EzSwitch Dev (already created by previous run)
# ---------------------------------------------------------------------------
log ""
log "${YELLOW}🔍 Looking for existing \"$CERT_NAME\" certificate…${NC}"
hr
EXISTING=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -F "\"$CERT_NAME\"" | head -1 || true)

if [ -n "$EXISTING" ]; then
    HASH=$(echo "$EXISTING" | awk '{print $2}')
    ok "Found \"$CERT_NAME\""
    log "  Hash: ${GREEN}$HASH${NC}"
    log ""
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${GREEN}✅ Setup complete! Using \"$CERT_NAME\" for stable signing.${NC}"
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    log "Just run ${BLUE}./build.sh${NC} and macOS will keep your permissions across builds."
    exit 0
fi
warn "No \"$CERT_NAME\" certificate found"

# ---------------------------------------------------------------------------
# Strategy 3: Guide user through GUI certificate creation
# ---------------------------------------------------------------------------
log ""
log "${YELLOW}⚙️  No suitable signing identity found.${NC}\n"
log "Choose ONE of the following options:\n"

log "${BLUE}═══ OPTION A (recommended, free): Personal Team via Apple ID ═══${NC}"
log "  1. Open Xcode → Settings (⌘,) → Accounts tab"
log "  2. Click '+' → sign in with your Apple ID (free, no paid account needed)"
log "  3. After signing in, click 'Manage Certificates' → '+' → 'Apple Development'"
log "  4. Re-run this script: ${BLUE}./scripts/setup_dev_signing.sh${NC}"
log ""

log "${BLUE}═══ OPTION B: Self-signed certificate via Keychain Access ═══${NC}"
log "  1. Open ${BLUE}Keychain Access${NC} app (Spotlight → 'Keychain Access')"
log "  2. Menu: ${BLUE}Keychain Access → Certificate Assistant → Create a Certificate…${NC}"
log "     If the menu item is missing, run this in Terminal first:"
log "       ${BLUE}defaults write com.apple.keychainaccess CertificateDistributionShowError -bool false${NC}"
log "       then re-open Keychain Access."
log "  3. Fill in:"
log "       Name:                 ${GREEN}EzSwitch Dev${NC}"
log "       Identity Type:        ${GREEN}Self Signed Root${NC}"
log "       Certificate Type:     ${GREEN}Code Signing${NC}"
log "       Let me override defaults: ${GREEN}✅ (check this)${NC}"
log "  4. Continue through the wizard, accepting defaults"
log "  5. Make sure the new certificate appears in:"
log "       ${BLUE}Keychain Access → My Certificates${NC}"
log "  6. Quit and re-open any apps that need access to the certificate"
log "  7. Re-run this script: ${BLUE}./scripts/setup_dev_signing.sh${NC}"
log ""

log "${BLUE}═══ OPTION C: If you have a paid Apple Developer account ═══${NC}"
log "  1. Open Xcode → Settings → Accounts → select your Apple ID"
log "  2. Click 'Manage Certificates' → '+' → 'Apple Development'"
log "  3. Edit ${BLUE}EzSwitch.xcodeproj/project.pbxproj${NC} and uncomment:"
log "       ${BLUE}DEVELOPMENT_TEAM = YOUR_TEAM_ID;${NC}  (in 4 places)"
log "  4. Then build normally with ${BLUE}./build.sh${NC}"
log ""

log "${YELLOW}After completing one of the above, run this script again to verify.${NC}"
