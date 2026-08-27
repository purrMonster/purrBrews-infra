# secrets/

This directory holds SOPS-encrypted files only — ciphertext, safe to commit. Never place an unencrypted secret here or anywhere else in this repo.

- Encryption/decryption key: an age keypair. The **public** key goes into `.sops.yaml` at the repo root (tracked, not secret). The **private** key lives at `/etc/purrbrews/age/keys.txt` on each node that needs to decrypt — outside this repo entirely, generated once (on sieve, first in deploy order) and copied node-to-node over SSH, never committed.
- Offline backup of the private key (printed or on a USB kept safely) is the disaster-recovery copy; a convenience copy in Vaultwarden (once cellar is live) is secondary to that.
- To encrypt a new secret file: `sops -e -i secrets/<name>.sops.yaml`. To edit: `sops secrets/<name>.sops.yaml` (decrypts in your editor, re-encrypts on save — needs the private key present locally).
