# Emergency Access — Recovery Procedure

This document, and the materials it describes, exist for exactly one scenario: you've lost the roastery SSH key, or you need fleet access from a machine that isn't roastery/americano, and the normal path is unavailable.

## What's on the emergency USB

Everything below lives inside a single `age`-encrypted archive (`purrbrews-emergency.tar.age`), protected by a passphrase that is **not** stored with the USB itself.

| Item | Added when | Purpose |
|---|---|---|
| `emergency-ssh/purrbrews-emergency` (private key, passphrase-protected) + `.pub` | Now | Break-glass SSH access — authorized on every node's `authorized_keys` alongside the roastery key, so losing roastery's key doesn't lock you out |
| `age/keys.txt` | Once sieve's init generates it (Section 19.3) | The SOPS decryption key — without this, encrypted secrets in the repo are permanently unreadable if the primary copy is lost |
| `console-passwords.txt` | As each node is initialized | The random `barista` password `purrbrews-init.sh` prints once at setup, for physical/console access if SSH is entirely unreachable (e.g. network/Authelia misconfiguration locks out remote access) |
| This file | Now | So future-you isn't reconstructing the procedure from memory under stress |

## How to use it

1. Locate a physical copy of the USB.
2. Decrypt: `age -d -o purrbrews-emergency.tar purrbrews-emergency.tar.age` (prompts for the passphrase).
3. Extract, then:
   - SSH access: `ssh -i emergency-ssh/purrbrews-emergency barista@<node-ip>`
   - Secrets decryption: copy `age/keys.txt` to wherever you're running `sops -d` (e.g. `SOPS_AGE_KEY_FILE=./age/keys.txt sops -d secrets/whatever.sops.yaml`)
   - Total lockout: use `console-passwords.txt` at the machine's physical console (or via BMC/IPMI if any node ever gets one)

## Maintenance

- **Every time a node's `purrbrews-init.sh` prints a new console password**, add it to `console-passwords.txt` in the USB contents before that terminal output scrolls away — it is not recoverable after the fact.
- **After sieve's age key is generated**, add `age/keys.txt` to the USB contents (this becomes the offline backup copy referenced in Section 19.3 — the USB *is* that backup, not a separate thing).
- **Test this quarterly**: plug in a copy, decrypt it, confirm the emergency key actually logs into a live node. An untested backup is not a backup.
- **Re-encrypt and redistribute to all copies** any time contents change — stale copies are worse than no copies if you grab the wrong one under pressure.

## Copies

<!-- number and location of physical copies — fill in once decided -->
