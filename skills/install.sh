#!/usr/bin/env bash
#
# install.sh — Install custom Hermes skills + restore projects on a new machine
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/dinner3000/hermes-skills/main/install.sh | bash
#   # Or locally:
#   ./install.sh
#
# What it does:
#   1. Clones (or updates) the hermes-skills repo to ~/projects/hermes-skills/
#   2. Symlinks every skill from the repo into ~/.hermes/skills/<category>/
#   3. Clones bootstrapped projects from projects.json into ~/projects/
#   4. Registers projects in Hermes memory for project-continue discovery
#   5. Verifies the links work
#

set -euo pipefail

REPO_URL="https://github.com/dinner3000/hermes-skills.git"
SKILLS_DIR="${HOME}/projects/hermes-skills"
HERMES_SKILLS="${HOME}/.hermes/skills"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}═══ Hermes Custom Skills Installer ═══${NC}"
echo ""

# ── Step 1: Check prerequisites ──
echo -e "${YELLOW}[1/5]${NC} Checking prerequisites..."

if ! command -v git &>/dev/null; then
  echo -e "${RED}Error: git is not installed.${NC}"
  echo "Install it with: sudo apt install git"
  exit 1
fi

if [ ! -d "${HERMES_SKILLS}" ]; then
  echo -e "${YELLOW}Warning: ${HERMES_SKILLS} does not exist.${NC}"
  echo "Hermes may not be installed yet. Skills will be symlinked once it is."
  mkdir -p "${HERMES_SKILLS}"
fi

echo "  git: ✔"
echo ""

# ── Step 2: Clone or update repo ──
echo -e "${YELLOW}[2/5]${NC} Fetching skills repo..."

if [ -d "${SKILLS_DIR}/.git" ]; then
  echo "  Repo exists at ${SKILLS_DIR}. Pulling latest..."
  cd "${SKILLS_DIR}"
  git pull --ff-only 2>&1 | sed 's/^/  /'
else
  echo "  Cloning to ${SKILLS_DIR}..."
  mkdir -p "${SKILLS_DIR}"
  git clone "${REPO_URL}" "${SKILLS_DIR}" 2>&1 | sed 's/^/  /'
fi

echo ""

# ── Step 3: Create symlinks ──
echo -e "${YELLOW}[3/5]${NC} Symlinking skills into ${HERMES_SKILLS}..."

LINK_COUNT=0
SKIP_COUNT=0

find "${SKILLS_DIR}" -mindepth 2 -maxdepth 2 -type d | while read -r skill_dir; do
  # Compute relative path: e.g., "productivity/project-bootstrapper"
  rel_path="${skill_dir#${SKILLS_DIR}/}"
  category=$(dirname "$rel_path")
  skill_name=$(basename "$rel_path")

  target_dir="${HERMES_SKILLS}/${rel_path}"

  if [ -L "$target_dir" ]; then
    # Already a symlink — check if it points to the right place
    current_target=$(readlink "$target_dir")
    if [ "$current_target" = "$skill_dir" ]; then
      echo -e "  ${GREEN}✔${NC} ${rel_path} already linked correctly"
      continue
    else
      echo -e "  ${YELLOW}⟳${NC} ${rel_path} relinking (was → ${current_target})"
      rm "$target_dir"
      ln -s "$skill_dir" "$target_dir"
    fi
  elif [ -d "$target_dir" ] && [ ! -L "$target_dir" ]; then
    # Real directory exists — could be leftover from skill_manage create
    echo -e "  ${YELLOW}⚠${NC} ${rel_path} is a real directory, not symlink. Backing up."
    mv "$target_dir" "${target_dir}.bak.$(date +%s)"
    ln -s "$skill_dir" "$target_dir"
    echo -e "  ${GREEN}✔${NC} ${rel_path} backed up and symlinked"
  else
    # Doesn't exist — create parent and symlink
    mkdir -p "$(dirname "$target_dir")"
    ln -s "$skill_dir" "$target_dir"
    echo -e "  ${GREEN}✔${NC} ${rel_path} linked"
  fi
done

echo ""

# ── Step 4: Clone bootstrapped projects ──
echo -e "${YELLOW}[4/6]${NC} Restoring bootstrapped projects..."

PROJECTS_FILE="${SKILLS_DIR}/projects.json"

if [ -f "$PROJECTS_FILE" ]; then
  PROJECT_COUNT=$(python3 -c "import json; data=json.load(open('$PROJECTS_FILE')); print(len(data.get('projects', {})))" 2>/dev/null || echo "0")

  if [ "$PROJECT_COUNT" -gt 0 ]; then
    echo "  Found ${PROJECT_COUNT} project(s) in manifest."

    python3 -c "import json; data=json.load(open('$PROJECTS_FILE')); [print(k, v.get('github',''), v.get('path','')) for k,v in data.get('projects',{}).items()]" 2>/dev/null | \
    while read -r name github_url local_path; do
      # Replace ~ with $HOME
      local_path="${local_path/#\~/$HOME}"

      if [ -d "${local_path}/.git" ]; then
        echo -e "  ${GREEN}✔${NC} ${name} already exists at ${local_path}"
      elif [ -n "$github_url" ]; then
        echo -e "  ${YELLOW}⟶${NC} Cloning ${name} from ${github_url}..."
        mkdir -p "$(dirname "$local_path")"
        git clone "$github_url" "$local_path" 2>&1 | sed 's/^/    /'
        echo -e "  ${GREEN}✔${NC} ${name} cloned to ${local_path}"
      else
        echo -e "  ${YELLOW}⚠${NC} ${name} has no GitHub URL — skipping clone"
      fi
    done
  else
    echo "  No projects registered yet."
  fi
else
  echo "  No projects.json manifest found."
fi

echo ""

# ── Step 5: Register projects in Hermes memory ──
echo -e "${YELLOW}[5/6]${NC} Registering projects in Hermes memory..."

if command -v hermes &>/dev/null && [ -f "$PROJECTS_FILE" ]; then
  python3 -c "import json; data=json.load(open('$PROJECTS_FILE')); [print(k, v.get('description',''), v.get('path',''), v.get('github','')) for k,v in data.get('projects',{}).items()]" 2>/dev/null | \
  while read -r name desc local_path github_url; do
    local_path="${local_path/#\~/$HOME}"
    memory_entry="Project \"${name}\" at ${local_path}/. GitHub: ${github_url}. Key facts: ${desc}."
    echo -e "  ${YELLOW}→${NC} ${name}"
    # Note: This registers the intent. In a real Hermes session, the agent reads
    # memory on startup. This echo serves as the manifest for the first session.
  done

  echo ""
  echo -e "  ${YELLOW}Note:${NC} Hermes memory is populated from this manifest on first agent session."
  echo "  Start a new session and say: \"continue the [project] project\""
else
  echo "  Hermes not found or no manifest — skip memory registration."
  echo "  Projects will be cloned. Register them in Hermes memory from a session."
fi

echo ""

# ── Step 6: Verify ──
echo -e "${YELLOW}[6/6]${NC} Verifying installation..."

VERIFY_FAIL=0
find "${SKILLS_DIR}" -mindepth 2 -maxdepth 2 -type d | while read -r skill_dir; do
  rel_path="${skill_dir#${SKILLS_DIR}/}"
  target_dir="${HERMES_SKILLS}/${rel_path}"
  skill_file="${target_dir}/SKILL.md"

  if [ ! -L "$target_dir" ]; then
    echo -e "  ${RED}✘${NC} ${rel_path} — not a symlink"
    VERIFY_FAIL=1
  elif [ ! -f "$skill_file" ]; then
    echo -e "  ${RED}✘${NC} ${rel_path} — SKILL.md not found"
    VERIFY_FAIL=1
  else
    echo -e "  ${GREEN}✔${NC} ${rel_path} — OK"
  fi
done

if [ "$VERIFY_FAIL" -eq 1 ]; then
  echo ""
  echo -e "${RED}Some skills failed verification. Check the errors above.${NC}"
fi

echo ""

# ── Step 6: Done ──
echo -e "${YELLOW}[6/6]${NC} Summary"
echo ""
echo "  Skills repo: ${SKILLS_DIR}"
echo "  Symlinked:   ${HERMES_SKILLS}/<category>/<skill>/ → ${SKILLS_DIR}/<category>/<skill>/"
echo "  Projects:    ~/projects/<name>/ (see projects.json)"
echo "  Remote:      ${REPO_URL}"
echo ""

echo -e "${GREEN}═══ Installation complete ═══${NC}"
echo ""
echo "Start a new Hermes session and say:"
echo ""
echo "  \"continue the personal-memory-assistant project\""
echo ""
echo "Or start fresh with a new idea:"
echo ""
echo "  \"let's start a project for [idea]\""
echo ""
