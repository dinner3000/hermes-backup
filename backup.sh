#!/usr/bin/env bash
#
# backup.sh — Backup Hermes Agent profile to GitHub
#
# Usage:
#   ./backup.sh
#
# What it backs up:
#   - ~/.hermes/config.yaml     → config/config.yaml
#   - ~/.hermes/SOUL.md         → config/SOUL.md
#   - ~/.hermes/memory.json     → config/memory.json (if exists)
#   - ~/.hermes/.env            → config/.env.gpg (encrypted)
#   - ~/.hermes/auth.json       → config/auth.json.gpg (encrypted, if exists)
#   - ~/.hermes/sessions/       → sessions/sessions-YYYY-MM-DD.tar.gz (last 30 days)
#   - ~/projects/hermes-skills/ → skills/ (reference copy of projects.json)
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="${REPO_DIR}"
HERMES_HOME="${HOME}/.hermes"
DATE_TAG=$(date +%Y-%m-%d)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Hermes Environment Backup${NC}"
echo -e "${CYAN}  ${DATE_TAG}${NC}"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo ""

# ── Step 1: Prerequisites ──
echo -e "${YELLOW}[1/8]${NC} Checking prerequisites..."

if ! command -v hermes &>/dev/null; then
  echo -e "${RED}  ✘ Hermes not found. Nothing to back up.${NC}"
  exit 1
fi
echo "  ✔ hermes"

if ! command -v git &>/dev/null; then
  echo -e "${RED}  ✘ git not found. Install git first.${NC}"
  exit 1
fi
echo "  ✔ git"

if ! command -v gpg &>/dev/null; then
  echo -e "${RED}  ✘ gpg not found. Install gnupg first.${NC}"
  exit 1
fi
echo "  ✔ gpg"

if [ ! -d "${HERMES_HOME}" ]; then
  echo -e "${RED}  ✘ ${HERMES_HOME} does not exist.${NC}"
  exit 1
fi
echo "  ✔ ~/.hermes/ exists"
echo ""

# ── Step 2: Init / update git repo ──
echo -e "${YELLOW}[2/8]${NC} Preparing git repository..."

if [ ! -d "${REPO_DIR}/.git" ]; then
  echo "  Initializing git repo..."
  git init "${REPO_DIR}"
  git -C "${REPO_DIR}" remote add origin git@github.com:dinner3000/hermes-backup.git
  echo "  ✔ Repo initialized"
else
  echo "  ✔ Git repo exists"
  # Pull latest to avoid conflicts
  git -C "${REPO_DIR}" pull --ff-only 2>/dev/null || true
fi
echo ""

# ── Step 3: Backup config files ──
echo -e "${YELLOW}[3/8]${NC} Backing up configuration..."

mkdir -p "${BACKUP_DIR}/config"

cp "${HERMES_HOME}/config.yaml" "${BACKUP_DIR}/config/config.yaml"
echo "  ✔ config.yaml"

if [ -f "${HERMES_HOME}/SOUL.md" ]; then
  cp "${HERMES_HOME}/SOUL.md" "${BACKUP_DIR}/config/SOUL.md"
  echo "  ✔ SOUL.md"
else
  echo "  - SOUL.md (not found, skipping)"
fi

if [ -f "${HERMES_HOME}/memory.json" ]; then
  cp "${HERMES_HOME}/memory.json" "${BACKUP_DIR}/config/memory.json"
  echo "  ✔ memory.json"
else
  echo "  - memory.json (not found, skipping)"
fi

# Export memory from Hermes if available
if hermes memory status &>/dev/null 2>&1; then
  echo "  ✔ Hermes memory accessible"
else
  echo "  - memory export skipped (not available in CLI mode)"
fi
echo ""

# ── Step 4: Encrypt secrets (non-interactive, uses GPG public key) ──
echo -e "${YELLOW}[4/8]${NC} Encrypting secrets..."

GPG_PUBLIC_KEY="${REPO_DIR}/config/hermes-backup-public.key"

if [ ! -f "$GPG_PUBLIC_KEY" ]; then
  echo -e "${RED}  ✘ Public key not found at ${GPG_PUBLIC_KEY}${NC}"
  echo "  Run setup first: gpg --import config/hermes-backup-public.key"
  exit 1
fi

# Import the key if not already in keyring
if ! gpg --list-keys 'Hermes Backup' &>/dev/null; then
  gpg --import "$GPG_PUBLIC_KEY" 2>/dev/null
fi

RECIPIENT="E5FF386452B38293B0B91CC656F6369D51C3649F"
SECRETS_FOUND=0

if [ -f "${HERMES_HOME}/.env" ]; then
  SECRETS_FOUND=$((SECRETS_FOUND + 1))
  gpg --batch --yes --trust-model always \
    --recipient "$RECIPIENT" \
    --output "${BACKUP_DIR}/config/.env.gpg" \
    --encrypt "${HERMES_HOME}/.env"
  echo -e "  ${GREEN}✔${NC} .env → config/.env.gpg"
else
  echo "  - .env (not found, skipping)"
fi

if [ -f "${HERMES_HOME}/auth.json" ]; then
  SECRETS_FOUND=$((SECRETS_FOUND + 1))
  gpg --batch --yes --trust-model always \
    --recipient "$RECIPIENT" \
    --output "${BACKUP_DIR}/config/auth.json.gpg" \
    --encrypt "${HERMES_HOME}/auth.json"
  echo -e "  ${GREEN}✔${NC} auth.json → config/auth.json.gpg"
else
  echo "  - auth.json (not found, skipping)"
fi

if [ "$SECRETS_FOUND" -eq 0 ]; then
  echo -e "  ${YELLOW}No secrets found — nothing to encrypt.${NC}"
fi
echo ""

# ── Step 5: Archive recent sessions ──
echo -e "${YELLOW}[5/8]${NC} Archiving recent chat sessions..."

SESSIONS_DIR="${HERMES_HOME}/sessions"
mkdir -p "${BACKUP_DIR}/sessions"

if [ -d "${SESSIONS_DIR}" ]; then
  echo "  Archiving session data..."
  tar czf "${BACKUP_DIR}/sessions/sessions-${DATE_TAG}.tar.gz" \
    -C "$(dirname "${SESSIONS_DIR}")" \
    "$(basename "${SESSIONS_DIR}")" --ignore-failed-read 2>/dev/null
  SESSION_SIZE=$(du -sh "${BACKUP_DIR}/sessions/sessions-${DATE_TAG}.tar.gz" 2>/dev/null | cut -f1)
  echo -e "  ${GREEN}✔${NC} sessions archived (${SESSION_SIZE:-unknown})"
else
  echo "  - sessions/ (not found, skipping)"
fi
echo ""

# ── Step 6: Save skills repo reference ──
echo -e "${YELLOW}[6/8]${NC} Saving skills repo reference..."

mkdir -p "${BACKUP_DIR}/skills"

# Only store the URL — actual skills are fetched from hermes-skills at restore time
echo "https://github.com/dinner3000/hermes-skills.git" > "${BACKUP_DIR}/skills/skills-repo-url.txt"
echo -e "  ${GREEN}✔${NC} skills repo reference saved"
echo ""

# ── Step 7: Create version info ──
echo -e "${YELLOW}[7/8]${NC} Recording environment info..."

mkdir -p "${BACKUP_DIR}/meta"
cat > "${BACKUP_DIR}/meta/backup-info.txt" <<EOF
Backup date: ${DATE_TAG}
Hostname: $(hostname)
User: ${USER}
OS: $(uname -a)
Hermes version: $(hermes --version 2>/dev/null || echo "unknown")
Model: $(hermes config 2>/dev/null | grep -i 'model.default' | head -1 || echo "unknown")
Provider: $(hermes config 2>/dev/null | grep -i 'model.provider' | head -1 || echo "unknown")
Skills count: $(ls -d ${HERMES_HOME}/skills/*/*/SKILL.md 2>/dev/null | wc -l)
EOF
echo -e "  ${GREEN}✔${NC} meta/backup-info.txt"
echo ""

# ── Step 8: Commit and push ──
echo -e "${YELLOW}[8/8]${NC} Committing and pushing to GitHub..."

cd "${REPO_DIR}"

# Create .gitignore for safety
cat > "${REPO_DIR}/.gitignore" << 'GITIGNORE'
# Never commit plaintext secrets
*.gpg
GITIGNORE

git add -A

# Check if there's anything to commit
if git diff --cached --quiet; then
  echo -e "  ${YELLOW}Nothing changed — no commit needed.${NC}"
else
  git commit -m "backup: ${DATE_TAG}"
  echo "  ✔ Committed"
fi

# Push to GitHub
echo "  Pushing to GitHub..."
PUSH_FAILED=0

# Try git push via SSH
echo "  Trying git push via SSH..."
# Ensure ssh-agent has the key loaded
if command -v ssh-agent &>/dev/null; then
  eval $(ssh-agent -s) >/dev/null 2>&1 || true
  ssh-add ~/.ssh/id_ed25519 2>/dev/null || true
fi
if git push --set-upstream origin main 2>&1; then
  echo -e "  ${GREEN}✔${NC} Git push via SSH succeeded"
else
  echo -e "  ${RED}✘${NC} Git push via SSH failed"
  PUSH_FAILED=1


if [ "$PUSH_FAILED" -eq 0 ]; then
  echo -e "  ${GREEN}✔${NC} Push complete"
else
  echo -e "  ${RED}✘${NC} Push to GitHub failed — local backup is safe in ${REPO_DIR}"
  echo ""
  echo -e "${YELLOW}To fix GitHub authentication:${NC}"
  echo "  1. Run: gh auth login"
  echo "     (or use device code: visit https://github.com/login/device and enter the code)"
  echo "  2. Or add your SSH public key to GitHub:"
  echo "     Key: $(cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo 'No SSH key found')"
fi
echo ""

# ── Done ──
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Backup complete!${NC}"
echo ""
echo "  Backup location: ${REPO_DIR}"
echo "  Remote:          github.com/dinner3000/hermes-backup"
echo ""
echo "  Remember your GPG passphrase — you'll need it to restore."
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
