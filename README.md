# CLAWDINATORS

CLAWDINATORS are maintainer‑grade coding agents. This repo defines how to spawn them
declaratively (OpenTofu + NixOS). Humans are not in the loop.

Prime directives:
- Declarative‑first. Another CLAWDINATOR can bootstrap a fresh CLAWDINATOR with a single command.
- No manual host edits. The repo + agenix secrets are the source of truth.
- Latest upstream `nix-clawdbot` by default; breaking changes are acceptable.
- AWS only: AMI pipeline is the only deploy path (no pets, no in‑place drift).
- Infra stack: Nix + OpenTofu.
- First prove 1 POC CLAWDINATOR, then scale out.
- No interactive setup. Provisioning is fully declarative.
- CLAWDINATORS are named `CLAWDINATOR-{1..n}`.
- CLAWDINATORS connect to Discord; start in `#clawdributors-test`.
- CLAWDINATORS are ephemeral, but share memory (hive mind).
- CLAWDINATORS are br00tal. Soul lives in `CLAWDINATOR-SOUL.md` and must be distilled into workspace docs.
- CLAWDINATORS respond only to maintainers.
- CLAWDINATORS can interact with GitHub (read‑only required).
- Primary task: monitor GitHub issues + PRs and direct human attention.
- CLAWDINATORS can write and run code for maintainers.
- CLAWDINATORS can self‑modify and self‑deploy.
- CLAWDINATORS post lots of Arnie gifs.
- CLAWDINATORS must understand project philosophy, goals, architecture, and repo deeply.
- CLAWDINATORS act like maintainers with SOTA intelligence.
- CLAWDINATORS use Codex for coding. Claude for personality.
- Use local Nix examples in sibling repos (ai‑stack, nixos‑config, gohome) and `nix-clawdbot`.

Zen of Clawdbot (explicit):
- **Only one way to do things.** No optional paths.
Beautiful is better than ugly.
Explicit is better than implicit.
Simple is better than complex.
Complex is better than complicated.
Flat is better than nested.
Sparse is better than dense.
Readability counts.
Special cases aren't special enough to break the rules.
Although practicality beats purity.
Errors should never pass silently.
Unless explicitly silenced.
In the face of ambiguity, refuse the temptation to guess.
There should be one-- and preferably only one --obvious way to do it.
Although that way may not be obvious at first unless you're Dutch.
Now is better than never.
Although never is often better than *right* now.
If the implementation is hard to explain, it's a bad idea.
If the implementation is easy to explain, it may be a good idea.
Namespaces are one honking great idea -- let's do more of those!

Stack (AWS):
- AMIs built in CI (nixos-generators raw + import-image).
- EC2 instances launched from those AMIs via OpenTofu.
- NixOS modules configure Clawdbot and CLAWDINATOR runtime.
- Shared hive‑mind memory stored on a mounted shared filesystem (EFS).

Shared memory (hive mind):
- All instances share the same memory files (no per‑instance prefixes for canonical files).
- Daily notes can be per‑instance: `YYYY-MM-DD_INSTANCE.md`.
- Canonical files are single shared sources of truth.
- Agents must use `memory-read` / `memory-write` / `memory-edit` for file locking.

Example layout:
```
~/clawd/
├── memory/
│ ├── project.md # Project goals + non-negotiables
│ ├── architecture.md # Architecture decisions + invariants
│ ├── discord.md # Discord-specific stuff
│ ├── whatsapp.md # WhatsApp-specific stuff
│ └── 2026-01-06.md # Daily notes
```

Secrets (required):
- GitHub App private key (for short‑lived installation tokens).
- GitHub App tokens are short‑lived; refresh via timer if using a GitHub App.
- Discord bot token (per instance).
- Discord bot tokens are explicit files via agenix.
- Anthropic API key (Claude models).
- AWS credentials (image pipeline + infra).
- Agenix image key (baked into AMI via CI).

Secrets are stored in `../nix/nix-secrets` using agenix and decrypted to `/run/agenix/*`
on hosts. See `docs/SECRETS.md`.

Deploy (automation‑first):
- Image‑based provisioning only.
- Host config lives in `nix/hosts/*` and is exposed in `flake.nix`.
- Ensure `/var/lib/clawd/repo` contains this repo (needed for self‑update).
- Configure Discord guild/channel allowlist and GitHub App installation ID.

Discord:
- Setup must follow upstream docs: https://github.com/clawdbot/clawdbot/blob/main/docs/discord.md

Image‑based deploy (only path):
1) Build a bootstrap image with nixos-generators:
   - `nix run github:nix-community/nixos-generators -- -f raw -c nix/hosts/clawdinator-1-image.nix -o dist`
2) Upload the raw image to S3 (private object).
3) Import into AWS as an AMI (snapshot import + register image).
4) Launch hosts from the AMI (OpenTofu `infra/opentofu/aws`).
5) Ensure secrets are encrypted to the baked agenix key and sync them to `/var/lib/clawd/nix-secrets`.
6) Run `nixos-rebuild switch --flake /var/lib/clawd/repo#clawdinator-1`.

CI (recommended):
- GitHub Actions builds the image, uploads to S3, and imports an AMI.
- See `.github/workflows/image-build.yml` and `scripts/*.sh`.
- CI must provide `CLAWDINATOR_AGE_KEY` so the image can bake `/etc/agenix/keys/clawdinator.agekey`.

AWS bucket bootstrap:
- `infra/opentofu/aws` provisions a private S3 bucket + scoped IAM user + VM Import role.

Docs:
- `docs/PHILOSOPHY.md`
- `docs/ARCHITECTURE.md`
- `docs/SHARED_MEMORY.md`
- `docs/POC.md`
- `docs/SECRETS.md`
- `docs/SKILLS_AUDIT.md`

Repo layout:
- `infra/opentofu/aws` — S3 bucket + IAM + VM import role
- `nix/modules/clawdinator.nix` — NixOS module
- `nix/hosts/` — host configs
- `nix/examples/` — example host + flake wiring
- `clawdinator/workspace/` — agent workspace templates (synced to `/var/lib/clawd/workspace`)
- `memory/` — template memory files

Operating mode:
- No manual setup. Machines are created by automation (other CLAWDINATORS).
- Everything is in repo + agenix. No ad‑hoc changes on hosts.

Sister repos:
- `clawdbot`: upstream runtime + gateway.
- `nix-clawdbot`: Nix packaging for Clawdbot + gateway build/test.
- `clawdinators`: infrastructure, AMI pipeline, deployment, workspace templates, and ops.

## nix-clawdbot integration

Role: CLAWDINATORS own automation around packaging updates; `nix-clawdbot` stays focused on Nix packaging.

Automated flow:
1) Poll upstream clawdbot commits (throttled to max once every 10 minutes).
2) Update `nix-clawdbot` canary pin (PR).
3) Wait for Garnix build + `pnpm test`.
4) Run live Discord smoke test in `#clawdinators-test`.
5) If green → promote canary pin to stable (PR auto-merge).
6) If red → do nothing; stable stays pinned.
