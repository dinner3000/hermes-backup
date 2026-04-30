#!/usr/bin/env python3
"""Push updated backup files to GitHub via API."""
import base64, json, os, sys
sys.path.insert(0, os.path.expanduser("~/.hermes/hermes-agent"))
from hermes_tools_wrapper import terminal

repo = "dinner3000/hermes-backup"
base_dir = os.path.expanduser("~/projects/hermes-backup")

files = [
    "README.md",
    "backup.sh",
    "restore.sh",
    ".gitignore",
    "config/hermes-backup-public.key",
    "gpg-key-config",
]

for filepath in files:
    local = os.path.join(base_dir, filepath)
    if not os.path.exists(local):
        print(f"  - {filepath} (not found)")
        continue

    # Get SHA of existing file
    r = terminal(f"gh api repos/{repo}/contents/{filepath} --jq .sha 2>/dev/null || true", timeout=10)
    sha = r["output"].strip()

    with open(local, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")

    payload = {
        "message": "feat: automated non-interactive GPG encryption + daily cron",
        "content": b64,
        "branch": "main",
    }
    if sha:
        payload["sha"] = sha

    tmp = f"/tmp/gh_push_{os.path.basename(filepath)}.json"
    with open(tmp, "w") as f:
        json.dump(payload, f)

    r = terminal(f"gh api repos/{repo}/contents/{filepath} --method PUT --input {tmp}", timeout=20)
    ok = r["exit_code"] == 0
    print(f"  {'OK' if ok else 'FAIL'} {filepath}")
    os.remove(tmp)

print("Done")
