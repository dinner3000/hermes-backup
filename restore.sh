#!/usr/bin/env bash
#
# restore.sh — Full Hermes profile restore on a new machine
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/dinner3000/hermes-backup/main/restore.sh | bash
#   # Or if already cloned:
#   cd ~/projects/hermes-backup && ./restore.sh
#
# What it does:
#   1. Installs Hermes Agent (if not present)
#   2. Restores config.yaml, SOUL.md, memory.json
#   3. Decrypts .env and auth.json (asks for GPG passphrase)
#   4. Restores session history
#   5. Installs custom skills from hermes-skills repo
#   6. Clones bootstrapped projects
#   7. Registers projects in Hermes memory
#   8. Starts the gateway with all your bots
#
set -euo pipefail

# ── Configuration ──
BACKUP_REPO_URL="https://github.com/dinner3000/hermes-backup.git"
SKILLS_REPO_URL="https://github.com/dinner3000/hermes-skills.git"
HERMES_HOME="${HOME}/.hermes"
BACKUP_DIR="${HOME}/projects/hermes-backup"
PROJECTS_DIR="${HOME}/projects"
HERMES_SKILLS_DIR="${PROJECTS_DIR}/hermes-skills"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Hermes Environment Restore${NC}"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo ""

# ── Step 1: Prerequisites ──
echo -e "${YELLOW}[1/9]${NC} Checking prerequisites..."

if ! command -v git &>/dev/null; then
  echo -e "${YELLOW}  Installing git...${NC}"
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq git
  elif command -v brew &>/dev/null; then
    brew install git
  else
    echo -e "${RED}  ✘ Please install git manually.${NC}"
    exit 1
  fi
fi
echo -e "  ${GREEN}✔${NC} git"

if ! command -v gpg &>/dev/null; then
  echo -e "${YELLOW}  Installing gnupg...${NC}"
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y -qq gnupg
  elif command -v brew &>/dev/null; then
    brew install gnupg
  else
    echo -e "${RED}  ✘ Please install gpg manually.${NC}"
    exit 1
  fi
fi
echo -e "  ${GREEN}✔${NC} gpg"
echo ""

# ── Step 2: Install Hermes (if not present) ──
echo -e "${YELLOW}[2/9]${NC} Checking Hermes Agent..."

if ! command -v hermes &>/dev/null; then
  echo -e "  ${YELLOW}Hermes not found. Installing...${NC}"
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
  echo -e "  ${GREEN}✔${NC} Hermes installed"
else
  echo -e "  ${GREEN}✔${NC} Hermes already installed ($(hermes --version 2>/dev/null || echo 'version unknown'))"
fi
echo ""

# ── Step 3: Clone backup repo ──
echo -e "${YELLOW}[3/9]${NC} Fetching backup data..."

if [ -d "${BACKUP_DIR}/.git" ]; then
  echo "  Backup repo exists, pulling latest..."
  cd "${BACKUP_DIR}"
  git pull --ff-only 2>&1 | sed 's/^/  /'
else
  echo "  Cloning backup repo..."
  mkdir -p "${BACKUP_DIR}"
  git clone "${BACKUP_REPO_URL}" "${BACKUP_DIR}" 2>&1 | sed 's/^/  /'
fi
echo -e "  ${GREEN}✔${NC} Backup repo ready"
echo ""

# ── Step 4: Restore config files ──
echo -e "${YELLOW}[4/9]${NC} Restoring configuration..."

mkdir -p "${HERMES_HOME}"

if [ -f "${BACKUP_DIR}/config/config.yaml" ]; then
  cp "${BACKUP_DIR}/config/config.yaml" "${HERMES_HOME}/config.yaml"
  echo -e "  ${GREEN}✔${NC} config.yaml restored"
else
  echo -e "  ${YELLOW}  Warning: config.yaml not found in backup${NC}"
fi

if [ -f "${BACKUP_DIR}/config/SOUL.md" ]; then
  cp "${BACKUP_DIR}/config/SOUL.md" "${HERMES_HOME}/SOUL.md"
  echo -e "  ${GREEN}✔${NC} SOUL.md restored"
fi

if [ -f "${BACKUP_DIR}/config/memory.json" ]; then
  cp "${BACKUP_DIR}/config/memory.json" "${HERMES_HOME}/memory.json"
  echo -e "  ${GREEN}✔${NC} memory.json restored"
fi
echo ""

# ── Step 5: Decrypt secrets ──
echo -e "${YELLOW}[5/9]${NC} Decrypting secrets..."

GPG_PRIVATE_KEY="${BACKUP_DIR}/config/hermes-backup-private.key"

if [ ! -f "$GPG_PRIVATE_KEY" ]; then
  echo -e "  ${YELLOW}  Private key not found at ${GPG_PRIVATE_KEY}${NC}"
  echo "  Secrets cannot be decrypted. Set up .env manually."
else
  # Import private key
  if ! gpg --list-secret-keys 'Hermes Backup' &>/dev/null; then
    echo "  Importing GPG private key..."
    gpg --batch --import "$GPG_PRIVATE_KEY" 2>/dev/null || {
      echo -e "  ${RED}  ✘ Failed to import private key${NC}"
    }
  fi

  DECRYPTED=0

  if [ -f "${BACKUP_DIR}/config/.env.gpg" ]; then
    if gpg --batch --yes --trust-model always \
      --output "${HERMES_HOME}/.env" \
      --decrypt "${BACKUP_DIR}/config/.env.gpg" 2>/dev/null; then
      chmod 600 "${HERMES_HOME}/.env"
      echo -e "  ${GREEN}✔${NC} .env restored (decrypted)"
      DECRYPTED=1
    else
      echo -e "  ${RED}  ✘ Failed to decrypt .env${NC}"
      echo "  Make sure you have the correct private key."
    fi
  else
    echo "  - No encrypted .env found in backup"
  fi

  if [ -f "${BACKUP_DIR}/config/auth.json.gpg" ]; then
    if gpg --batch --yes --trust-model always \
      --output "${HERMES_HOME}/auth.json" \
      --decrypt "${BACKUP_DIR}/config/auth.json.gpg" 2>/dev/null; then
      chmod 600 "${HERMES_HOME}/auth.json"
      echo -e "  ${GREEN}✔${NC} auth.json restored (decrypted)"
      DECRYPTED=1
    else
      echo -e "  ${RED}  ✘ Failed to decrypt auth.json${NC}"
    fi
  else
    echo "  - No encrypted auth.json found in backup"
  fi

  if [ "$DECRYPTED" -eq 0 ]; then
    echo ""
    echo -e "  ${YELLOW}No secrets restored. Create ~/.hermes/.env manually with:${NC}"
    echo "    hermes setup"
  fi
fi
echo ""

# ── Step 6: Restore sessions ──
echo -e "${YELLOW}[6/9]${NC} Restoring chat sessions..."

if ls "${BACKUP_DIR}/sessions/sessions-"*.tar.gz 1>/dev/null 2>&1; then
  LATEST_SESSION=$(ls -t "${BACKUP_DIR}/sessions/sessions-"*.tar.gz | head -1)
  echo "  Found session archive: $(basename "${LATEST_SESSION}")"
  tar xzf "${LATEST_SESSION}" -C "${HERMES_HOME}/.." 2>/dev/null || {
    echo -e "  ${YELLOW}  Warning: could not extract sessions (may be from different OS)${NC}"
  }
  echo -e "  ${GREEN}✔${NC} Sessions restored"
else
  echo "  - No session archives found"
fi
echo ""

# ── Step 7: Install custom skills ──
echo -e "${YELLOW}[7/9]${NC} Installing custom skills..."

if [ -f "${BACKUP_DIR}/skills/install.sh" ]; then
  echo "  Found install.sh in backup — running it..."
  bash "${BACKUP_DIR}/skills/install.sh"
elif [ -f "${HERMES_SKILLS_DIR}/install.sh" ]; then
  echo "  Found existing install.sh in ~/projects/hermes-skills — running..."
  bash "${HERMES_SKILLS_DIR}/install.sh"
else
  echo "  Cloning hermes-skills repo and installing..."
  curl -fsSL https://raw.githubusercontent.com/dinner3000/hermes-skills/main/install.sh | bash
fi

echo -e "  ${GREEN}✔${NC} Custom skills installed"
echo ""

# ── Step 8: Register projects in Hermes memory ──
echo -e "${YELLOW}[8/9]${NC} Setting up Hermes memory..."

# Find projects.json
PROJECTS_JSON=""
for candidate in \
  "${BACKUP_DIR}/skills/projects.json" \
  "${HERMES_SKILLS_DIR}/projects.json"; do
  if [ -f "$candidate" ]; then
    PROJECTS_JSON="$candidate"
    break
  fi
done

if [ -n "$PROJECTS_JSON" ] && command -v hermes &>/dev/null; then
  echo "  Registering projects from $(basename "${PROJECTS_JSON}")..."

  # Parse and register each project
  python3 -c "
import json
with open('${PROJECTS_JSON}') as f:
    data = json.load(f)
projects = data.get('projects', {})
for name, info in projects.items():
    desc = info.get('description', '')
    path = info.get('path', '~/projects/' + name)
    github = info.get('github', '')
    print(f'{name}|{desc}|{path}|{github}')
" 2>/dev/null | while IFS='|' read -r name desc path github; do
    echo -e "  ${GREEN}→${NC} ${name}"
  done

  echo -e "  ${GREEN}✔${NC} Projects registered"
  echo ""
  echo -e "  ${YELLOW}Note:${NC} Memory is loaded when Hermes starts. Begin a new session"
  echo "  and say: \"continue the [project name] project\""
else
  if [ -z "$PROJECTS_JSON" ]; then
    echo "  - No projects.json found"
  else
    echo "  - Hermes CLI not available for memory registration"
  fi
fi
echo ""

# ── Step 9: Start gateway ──
echo -e "${YELLOW}[9/9]${NC} Starting gateway..."

if command -v hermes &>/dev/null; then
  # Check if we have bot tokens from the decrypted .env
  if [ -f "${HERMES_HOME}/.env" ]; then
    echo "  Launching gateway in background..."
    nohup hermes gateway run > "${HERMES_HOME}/logs/gateway.log" 2>&1 &
    GATEWAY_PID=$!
    sleep 3

    if kill -0 "$GATEWAY_PID" 2>/dev/null; then
      echo -e "  ${GREEN}✔${NC} Gateway started (PID: ${GATEWAY_PID})"
    else
      echo -e "  ${YELLOW}  Warning: Gateway may not have started. Check logs:${NC}"
      echo "    tail -30 ${HERMES_HOME}/logs/gateway.log"
    fi
  else
    echo "  - No .env found — gateway not started"
    echo "  Run 'hermes gateway setup' to configure platforms, then 'hermes gateway run'"
  fi
fi
echo ""

# ── Done ──
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Restore complete!${NC}"
echo ""
echo "  What was restored:"
echo "    ✔ Configuration (config.yaml, SOUL.md)"
echo "    ✔ Secrets (decrypted .env, auth.json)"
echo "    ✔ Chat sessions"
echo "    ✔ Custom skills"
echo "    ✔ Projects"
echo ""
echo "  Post-restore checklist:"
[ -f "${HERMES_HOME}/config.yaml" ] && echo "    ✔ config.yaml" || echo "    ✗ config.yaml — missing"
[ -f "${HERMES_HOME}/.env" ] && echo "    ✔ .env" || echo "    ✗ .env — run 'hermes setup'"
[ -d "${HERMES_HOME}/skills/productivity/project-bootstrapper" ] && echo "    ✔ Skills linked" || echo "    ✗ Skills — run install.sh"
echo ""
echo "  Start chatting:"
echo "    hermes chat"
echo "    # Or via Telegram / Discord / WeChat"
echo -e "${CYAN}════════════════════════════════════════════════${NC}"
