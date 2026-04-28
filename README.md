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
│  ~/.hermes/      backup.sh (daily cron @ 3am)   │
│  ├── config.yaml                 │              │
│  ├── SOUL.md                     ▼              │
│  ├── .env ─── gpg (public key) ──▶ .env.gpg     │
│  ├── auth.json ── gpg ──▶ auth.json.gpg         │
│  └── sessions/ ──▶ sessions.tar.gz              │
│                                     │           │
│  ~/projects/hermes-skills/ ────────┤           │
│  └── install.sh + projects.json ──┘           │
│                                         │     │
└─────────────────────────────────────────┼─────┘
                                          │ gh api push
                                          ▼
                    github.com/dinner3000/hermes-backup
                    (public — secrets are GPG-encrypted)

┌─────────────────────────────────────────┼─────┐
│              New Machine                │     │
│                                         │     │
│  restore.sh ◄───────────────────────────┘     │
│    │                                         │
│    ├── Installs Hermes (optional)            │
│    ├── Restores config.yaml, SOUL.md         │
│    ├── Imports GPG private key → decrypts    │
│    ├── Restores sessions                     │
│    ├── Runs hermes-skills/install.sh         │
│    └── Starts gateway                        │
│                                              │
└──────────────────────────────────────────────┘
```

## How Encryption Works

This uses **GPG public-key encryption** (asymmetric), not passphrase-based:

- A dedicated GPG key pair `Hermes Backup` was generated on setup
- **Public key** (`config/hermes-backup-public.key`) — committed to repo.
  Used during backup to encrypt `.env` and `auth.json`. No passphrase needed.
- **Private key** (`config/hermes-backup-private.key`) — stays on your local
  machine ONLY. Never pushed to GitHub. Used during restore to decrypt.
  If you lose the private key, you'll need to recreate secrets manually.

This means:
- **Daily backup** is fully automated — no passphrase prompt
- **Restore** works automatically as long as the private key is in the repo
- The private key is safe from GitHub because it's excluded from the commit
  (if using the script), and you control who has access to your machine

## Daily Automatic Backup

A cron job runs `backup.sh` every day at 3:00 AM. It auto-commits any
changes to config, session history, or skills. Check status with:

```bash
hermes cron list
```

## Usage

### Backup (from current machine)

```bash
# Clone (first time)
git clone git@github.com:dinner3000/hermes-backup.git ~/projects/hermes-backup
cd ~/projects/hermes-backup

# Run backup
./backup.sh
```

This copies config, encrypts .env/auth.json with your GPG public key,
archives recent sessions, and pushes everything to GitHub via API.

The backup also runs automatically every day at 3:00 AM via cron.

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

- **Secrets are GPG-encrypted** using public-key encryption (asymmetric).
  The **public key** (`hermes-backup-public.key`) is in the repo — it can only
  encrypt, never decrypt. The **private key** stays on your machine.
- The private key has no passphrase (required for automated daily backups).
  Protect it with filesystem permissions: `chmod 600 ~/projects/hermes-backup/config/hermes-backup-private.key`
- The `config.yaml` does NOT contain raw secrets (bot tokens live in `.env`)
- Consider making this a **private** GitHub repo if you want extra safety
  (though encrypted secrets are safe in public repos too)

## Prerequisites

- Git
- GPG (usually pre-installed on Linux/macOS)
- Hermes Agent (restore.sh can install it for you)
