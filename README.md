# Hermes Environment Backup & Restore

Backup and restore your full Hermes Agent profile — config, secrets (encrypted),
chat history, custom skills, and projects — to/from GitHub.

## What's Backed Up

| Item | Location | Encrypted? |
|------|----------|-----------|
| Config & settings | `~/.hermes/config.yaml` | No |
| Personality | `~/.hermes/SOUL.md` | No |
| Agent memory | `~/.hermes/memory.json` | No |
| Chat history | `~/.hermes/sessions/` (last 30 days) | No |
| API keys & tokens | `~/.hermes/.env` | Yes (GPG) |
| OAuth credentials | `~/.hermes/auth.json` | Yes (GPG) |
| Custom skills | Reference to `hermes-skills` repo | No |
| Bootstrapped projects | Reference to `projects.json` | No |

## Workflow Overview

```
┌─────────────────────────────────────────────────┐
│              Your Machine                        │
│                                                  │
│  ~/.hermes/      backup.sh ──────┐              │
│  ├── config.yaml                 │              │
│  ├── SOUL.md                     ▼              │
│  ├── .env ─── gpg ──▶ .env.gpg   │              │
│  ├── auth.json ── gpg ──▶ auth.json.gpg         │
│  └── sessions/ ──▶ sessions.tar.gz              │
│                                     │           │
│  ~/projects/hermes-skills/ ────────┤           │
│  └── install.sh + projects.json ──┘           │
│                                         │     │
└─────────────────────────────────────────┼─────┘
                                          │ git push
                                          ▼
                              github.com/dinner3000/hermes-backup
                                          │
                                          │ git clone
                                          ▼
┌─────────────────────────────────────────┼─────┐
│              New Machine                │     │
│                                         │     │
│  restore.sh ◄───────────────────────────┘     │
│    │                                         │
│    ├── Installs Hermes (optional)            │
│    ├── Restores config.yaml, SOUL.md         │
│    ├── Decrypts .env, auth.json              │
│    ├── Restores sessions                     │
│    ├── Runs hermes-skills/install.sh         │
│    └── Starts gateway                        │
│                                              │
└──────────────────────────────────────────────┘
```

## Usage

### Backup (from current machine)

```bash
# Clone (first time)
git clone git@github.com:dinner3000/hermes-backup.git ~/projects/hermes-backup
cd ~/projects/hermes-backup

# Run backup — will prompt for GPG passphrase to encrypt secrets
./backup.sh
```

This copies config, encrypts .env/auth.json, archives recent sessions,
and pushes everything to GitHub.

### Restore (on a new/fresh machine)

```bash
# One-command restore
curl -fsSL https://raw.githubusercontent.com/dinner3000/hermes-backup/main/restore.sh | bash

# Or if already cloned:
cd ~/projects/hermes-backup && ./restore.sh
```

The restore script will:
1. Install Hermes Agent (if not present)
2. Restore all config, skills, secrets, sessions
3. Clone your projects
4. Start the gateway with all your bots
5. Print a status summary

## Security Notes

- **Secrets are GPG-encrypted** — you choose a passphrase during backup
  and enter it again during restore. Without the passphrase, the encrypted
  files are useless.
- The `config.yaml` does NOT contain raw secrets (bot tokens live in `.env`)
- Store your GPG passphrase in a password manager
- Consider making this a **private** GitHub repo if you want extra safety
  (though encrypted secrets are safe in public repos too)

## Prerequisites

- Git
- GPG (usually pre-installed on Linux/macOS)
- Hermes Agent (restore.sh can install it for you)
