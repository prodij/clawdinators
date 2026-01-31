# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository ("clawdinators") provides NixOS-on-AWS infrastructure for deploying AI coding agent instances called CLAWDINATORs. It has two layers:

1. **Generic Layer**: Reusable NixOS-on-AWS patterns (AMI pipeline, OpenTofu infra, S3 bootstrap, agenix secrets)
2. **Specific Layer**: CLAWDINATOR agent runtime (Discord gateway, GitHub monitoring, hive-mind memory, self-update)

## Common Commands

### Development Environment

```bash
# Enter development shell (provides nixos-generators, awscli2, opentofu)
nix develop

# Or use direnv if configured
direnv allow
```

### Building and Deploying

```bash
# Build NixOS image (outputs to dist/)
./scripts/build-image.sh

# Upload image to S3
./scripts/upload-image.sh dist/nixos.img

# Import image as AWS AMI
./scripts/import-image.sh

# Upload bootstrap bundle (secrets + repo seeds)
./scripts/upload-bootstrap.sh clawdinator-1

# Deploy infrastructure with OpenTofu
cd infra/opentofu/aws
tofu init
tofu apply

# Get latest AMI ID
aws ec2 describe-images --region eu-central-1 --owners self \
  --filters "Name=tag:clawdinator,Values=true" \
  --query "Images | sort_by(@,&CreationDate)[-1].[ImageId,Name,CreationDate]" \
  --output text
```

### Testing and Development

```bash
# Build NixOS configuration locally (for validation)
nix build .#clawdinator-system

# Build image configuration
nix build .#clawdinator-image-system

# Update flake inputs (especially nix-openclaw)
nix flake update

# Update specific input
nix flake lock --update-input nix-openclaw
```

### Memory Operations (on running instance)

```bash
# Read from shared memory
memory-read ops.md

# Write to shared memory
memory-write ops.md "New content..."

# Edit shared memory in place
memory-edit ops.md
```

## Architecture Patterns

### Image-Based Provisioning Flow

This repo follows a strict **image-based provisioning only** approach:

1. **Build**: `nixos-generators` produces a raw NixOS image from `nix/hosts/clawdinator-1-image.nix`
2. **Upload**: Raw image uploaded to S3 bucket
3. **Import**: AWS VM Import creates AMI from S3 object
4. **Launch**: OpenTofu provisions EC2 instance from AMI
5. **Bootstrap**: Instance downloads secrets/repos from S3 at boot, runs `nixos-rebuild switch`
6. **Run**: Gateway service starts automatically

**Never SSH into running instances for configuration changes.** All changes must go through the repo → AMI → deploy pipeline.

### NixOS Module Structure

The main CLAWDINATOR module is at `nix/modules/clawdinator.nix`. It provides:

- Service management (`services.clawdinator.enable`)
- Secret mounting via agenix (`/run/agenix/*`)
- Workspace seeding from templates
- GitHub App token minting (short-lived installation tokens)
- EFS-backed shared memory mount
- Self-update timer (flake update + nixos-rebuild)
- GitHub org sync (PRs/issues to memory)

Host configurations are split into:
- `nix/hosts/clawdinator-1-common.nix`: Shared config (secrets, bootstrap, gateway config)
- `nix/hosts/clawdinator-1.nix`: Runtime host config (imports common + hardware)
- `nix/hosts/clawdinator-1-image.nix`: Image build config (imports common + image format modules)

### Secret Management with AWS Secrets Manager

Secrets are stored in [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/):

- Secrets stored in AWS Secrets Manager under `clawdinator/` prefix
- Fetched at boot via EC2 IAM role (no keys in images or S3)
- Written to `/run/agenix/*` for compatibility with existing module paths
- Permissions set to 0400 (owner read only)

Required secrets (in Secrets Manager):
- `clawdinator/anthropic-api-key` (Claude API key)
- `clawdinator/discord-token` (Discord bot token)
- `clawdinator/github-app-pem` (GitHub App private key)

Optional secrets:
- `clawdinator/openai-api-key` (GPT/Codex API key - fallback model)

### Shared Memory (Hive Mind)

- Mounted via AWS EFS at `/memory` (configured in `clawdinator-1-common.nix`)
- TLS tunnel via stunnel (NFS over TLS)
- Memory scripts use `flock` for exclusive/shared locking
- Template files in `memory/` directory (project.md, ops.md, discord.md, architecture.md)

### Bootstrap Process

The bootstrap flow is critical for zero-manual-setup provisioning:

1. `clawdinator-secrets.service` fetches from AWS Secrets Manager:
   - Uses EC2 instance IAM role for authentication
   - Fetches `clawdinator/anthropic-api-key`, `clawdinator/discord-token`, `clawdinator/github-app-pem`
   - Writes to `/run/agenix/clawdinator-*` (tmpfs)

2. `clawdinator-bootstrap.service` downloads from S3:
   - `repo-seeds.tar.zst` → `/var/lib/clawd/repo-seeds/`

3. `clawdinator-repo-seed.service` copies repo snapshots to `/var/lib/clawd/repos/`

4. `clawdinator.service` starts the gateway with seeded workspace

Bootstrap artifacts (repo seeds) are prepared by CI (`.github/workflows/image-build.yml`)

### Toolchain Management

Tools are defined in `nix/tools/clawdinator-tools.nix` with both packages and documentation.

To add a tool:
1. Add package to `packages` list
2. Add documentation entry to `docs` list
3. Rebuild - tools list is automatically rendered to `/etc/clawdinator/tools.md`

## Key Files and Their Roles

### Configuration
- `flake.nix`: Flake inputs (nix-openclaw, nixpkgs, agenix) and outputs (modules, packages, nixosConfigurations)
- `nix/modules/clawdinator.nix`: Main NixOS module with all service options
- `nix/hosts/clawdinator-1-common.nix`: Host-specific configuration
- `clawdinator/repos.tsv`: Repos to seed at boot (tab-separated: name, URL, branch)

### Infrastructure
- `infra/opentofu/aws/main.tf`: AWS resources (S3, IAM, VM Import role, EC2)
- `infra/opentofu/aws/variables.tf`: Tofu input variables
- `infra/opentofu/aws/outputs.tf`: Tofu outputs (bucket name, access keys)

### Scripts
- `scripts/build-image.sh`: Build raw NixOS image with nixos-generators
- `scripts/upload-image.sh`: Upload image to S3
- `scripts/import-image.sh`: Import S3 image as AMI
- `scripts/upload-bootstrap.sh`: Package and upload bootstrap bundle
- `scripts/prepare-repo-seeds.sh`: Clone and package repo seeds
- `scripts/mint-github-app-token.sh`: Generate short-lived GitHub App token
- `scripts/memory-*.sh`: Shared memory access wrappers (read/write/edit)

### Agent Workspace
- `clawdinator/workspace/`: Template directory for agent workspace
- `AGENTS.md`: Agent operating notes (read before acting)
- `CLAWDINATOR-SOUL.md`: Personality and behavior guidelines

## Important Principles

### Declarative-First Philosophy

From `docs/PHILOSOPHY.md`:
- **No manual host edits**: The repo + agenix secrets are the source of truth
- **Image-based only**: No SSH, no in-place drift, no pets
- **Self-updating**: CLAWDINATORs maintain themselves via systemd timers
- A CLAWDINATOR can bootstrap another CLAWDINATOR with a single command

### Zen of Moltbot

```
Beautiful is better than ugly.
Explicit is better than implicit.
Simple is better than complex.
Complex is better than complicated.
Flat is better than nested.
Sparse is better than dense.
Readability counts.
```

### Code Organization Rules

From `AGENTS.md`:
- **No inline scripting**: No Python/Node/etc. in Nix or shell blocks; put logic in script files
- **Cattle vs pets**: Hosts are disposable; prefer re-provisioning over manual fixes
- **Mental notes don't survive restarts**: Write it to a file

## CI/CD Pipeline

The `.github/workflows/image-build.yml` workflow automates:

1. Install Nix + tooling (nixos-generators, awscli2, age, jq, zstd)
2. Fetch encrypted secrets from S3
3. Mint GitHub App token for repo cloning
4. Prepare repo seeds (clone repos listed in `clawdinator/repos.tsv`)
5. Upload bootstrap bundle to S3
6. Build NixOS image
7. Upload image to S3
8. Import image as AMI

Triggered on push to `main` or manual workflow dispatch.

## Sister Repositories

- **openclaw**: Upstream runtime and gateway implementation
- **nix-openclaw**: Nix packaging for clawbot (provides `pkgs.openclaw-gateway`)
- **clawhub**: Public skill registry
- **ai-stack**: Public agent defaults and skills

This repo (`clawdinators`) is responsible for:
- NixOS configuration and modules
- AWS infrastructure (OpenTofu)
- Deployment automation (scripts, CI)
- Secret management wiring (agenix integration)

## Discord Configuration Note

**CRITICAL**: Always use `messages.queue.byChannel.discord = "interrupt"` in gateway config. Using `queue` mode causes significant delays in replies, making the bot appear unresponsive. The config is in `nix/hosts/clawdinator-1-common.nix`.

## Self-Update Mechanism

When `services.clawdinator.selfUpdate.enable = true`:
- Systemd timer runs daily (configurable)
- Executes `nix flake update` in `/var/lib/clawd/repos/clawdinators`
- Runs `nixos-rebuild switch` with the updated flake
- Gateway restarts automatically with new version

This requires the clawdinators repo to be present on the host.

## GitHub App Integration

CLAWDINATORs use GitHub Apps for authentication (not PATs):
- App ID and Installation ID in `nix/hosts/clawdinator-1-common.nix`
- Private key encrypted with agenix
- `clawdinator-github-app-token.service` mints short-lived tokens
- Timer refreshes token hourly
- Token exported as `GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_APP_TOKEN`

## Working with OpenTofu

Required environment variables:
```bash
export TF_VAR_aws_region=eu-central-1
export TF_VAR_ami_id=ami-xxxxx  # or empty string to skip instance creation
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
export TF_VAR_root_volume_size_gb=40  # adjust if needed
```

After `tofu apply`, update GitHub Actions secrets from outputs:
```bash
cd infra/opentofu/aws
tofu output -raw access_key_id  # → AWS_ACCESS_KEY_ID
tofu output -raw secret_access_key  # → AWS_SECRET_ACCESS_KEY
tofu output -raw bucket_name  # → S3_BUCKET
tofu output -raw aws_region  # → AWS_REGION
```

## What Happens After `terraform apply`

Once you run `tofu apply` with an AMI ID, here's the automatic boot sequence:

### 1. Instance Launches (Immediate)

OpenTofu creates:
- EC2 instance from the AMI
- IAM instance profile with S3 bootstrap permissions + SSM access
- Security groups (SSH port 22, gateway port 18789, EFS NFS port 2049)
- EFS file system with mount targets in all availability zones
- SSH key pair for operator access

Get instance details:
```bash
tofu output instance_public_ip
tofu output instance_public_dns
tofu output efs_file_system_id
```

### 2. Secrets Fetch Phase (~30 seconds)

The `clawdinator-secrets.service` runs automatically:

**What it does:**
- Uses EC2 instance IAM role to authenticate with Secrets Manager
- Fetches secrets from AWS Secrets Manager:
  - `clawdinator/anthropic-api-key` → `/run/agenix/clawdinator-anthropic-api-key`
  - `clawdinator/discord-token` → `/run/agenix/clawdinator-discord-token`
  - `clawdinator/github-app-pem` → `/run/agenix/clawdinator-github-app.pem`
- Sets permissions to 0400 (owner read only)

**Check secrets status:**
```bash
# SSH into instance
ssh root@$(tofu output -raw instance_public_ip)

# Check if secrets were fetched
systemctl status clawdinator-secrets.service
ls -la /run/agenix/  # Should show secrets (permissions 0400)

# View secrets logs
journalctl -u clawdinator-secrets.service
```

### 3. Bootstrap Phase (First Boot, ~2-3 minutes)

The `clawdinator-bootstrap.service` runs after secrets:

**What it does:**
- Downloads `s3://${S3_BUCKET}/bootstrap/clawdinator-1/repo-seeds.tar.zst`
  - Contains pre-cloned repos → `/var/lib/clawd/repo-seeds/`
- Creates sentinel file `/var/lib/clawd/.bootstrap-ok` (skip on subsequent boots)

**Verify bootstrap:**
```bash
systemctl status clawdinator-bootstrap.service
ls -la /var/lib/clawd/.bootstrap-ok  # Should exist
```

### 4. Repository Seeding (~30 seconds)

The `clawdinator-repo-seed.service` copies repos from snapshot:

**What it does:**
- Copies from `/var/lib/clawd/repo-seeds/` to `/var/lib/clawd/repos/`
- Includes this repo (clawdinators) for self-update capability
- Includes openclaw, nix-openclaw, and other configured repos

**Verify repos:**
```bash
systemctl status clawdinator-repo-seed.service
ls -la /var/lib/clawd/repos/
```

### 5. EFS Mount (~15 seconds)

The `clawdinator-efs-stunnel.service` establishes TLS tunnel:

**What it does:**
- Starts stunnel on 127.0.0.1:2049
- Connects to `${EFS_ID}.efs.${REGION}.amazonaws.com:2049` over TLS
- NFS mount at `/memory` tunnels through stunnel (for encryption in transit)

The `clawdinator-memory-init.service` initializes shared memory:

**What it does:**
- Creates `/memory/daily/` and `/memory/discord/` directories
- Creates `/memory/index.md` if not present
- Sets ownership to `clawdinator:clawdinator` with setgid bit

**Verify EFS:**
```bash
systemctl status clawdinator-efs-stunnel.service
systemctl status clawdinator-memory-init.service
mount | grep /memory  # Should show NFS mount
ls -la /memory/
```

### 6. GitHub Token Minting (~5 seconds)

The `clawdinator-github-app-token.service` generates short-lived token:

**What it does:**
- Reads GitHub App private key from `/run/agenix/clawdinator-github-app.pem`
- Generates JWT signed with RS256
- Exchanges JWT for installation access token via GitHub API
- Writes token to `/run/clawd/github-app.env` as `GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_APP_TOKEN`
- Timer refreshes hourly

**Verify token:**
```bash
systemctl status clawdinator-github-app-token.service
cat /run/clawd/github-app.env  # Should show GITHUB_TOKEN=ghs_...
gh auth status  # Should show authenticated
```

### 7. Gateway Startup (~10-30 seconds)

The `clawdinator.service` starts the main gateway:

**What it does (ExecStartPre):**
- Seeds workspace from `/nix/store/.../clawdinator/workspace/` to `/var/lib/clawd/workspace/`
  - Copies SOUL.md, IDENTITY.md, AGENTS.md, skills/, etc.
  - Appends `/etc/clawdinator/tools.md` to workspace TOOLS.md
- Note: Repo seeding happens via separate service (already completed by now)

**What it does (ExecStart):**
- Reads API keys from `/run/agenix/*` files
- Loads config from `/etc/clawd/openclaw.json`
- Starts `openclaw gateway --port 18789`
- Connects to Discord gateway
- Begins monitoring GitHub (via periodic sync timer)

**Verify gateway:**
```bash
systemctl status clawdinator.service

# View gateway logs (live)
journalctl -u clawdinator.service -f

# Check log file
tail -f /var/lib/clawd/logs/gateway.log

# Verify it's listening
ss -tlnp | grep 18789

# Check Discord connection (look for websocket connection)
journalctl -u clawdinator.service | grep -i discord
```

### 8. GitHub Sync Timer (Every 15 Minutes)

The `clawdinator-github-sync.service` runs periodically:

**What it does:**
- Uses `gh` CLI to fetch org PRs and issues
- Writes summaries to `/memory/` (shared hive-mind memory)
- Allows CLAWDINATORs to stay aware of repo activity

**Verify sync:**
```bash
systemctl status clawdinator-github-sync.service
journalctl -u clawdinator-github-sync.service

# Check sync timer
systemctl list-timers | grep github-sync
```

### 9. Self-Update Timer (Daily)

The `clawdinator-self-update.service` runs daily:

**What it does:**
- Runs `nix flake update` in `/var/lib/clawd/repos/clawdinators`
- Runs `nixos-rebuild switch --flake .#clawdinator-1`
- Gateway restarts with updated config/packages

**Check timer:**
```bash
systemctl list-timers | grep self-update
```

## Verification Checklist

After `tofu apply`, wait ~5 minutes then verify:

```bash
# Get instance IP
IP=$(cd infra/opentofu/aws && tofu output -raw instance_public_ip)

# SSH in
ssh root@$IP

# Check all services are active
systemctl status clawdinator-bootstrap.service     # Should be inactive (oneshot, completed)
systemctl status clawdinator-agenix.service       # Should be inactive (oneshot, completed)
systemctl status clawdinator-repo-seed.service    # Should be inactive (oneshot, completed)
systemctl status clawdinator-efs-stunnel.service  # Should be active (running)
systemctl status clawdinator-memory-init.service  # Should be inactive (oneshot, completed)
systemctl status clawdinator-github-app-token.service  # Should be inactive (oneshot, completed)
systemctl status clawdinator.service              # Should be active (running)

# Verify secrets exist
ls -la /run/agenix/

# Verify EFS is mounted
mount | grep /memory
ls -la /memory/

# Verify repos seeded
ls -la /var/lib/clawd/repos/

# Check gateway is running and connected
journalctl -u clawdinator.service --no-pager | tail -50

# Verify it responds on Discord
# (Go to Discord #clawdinators-test channel and message the bot)
```

## Troubleshooting

### Secrets Not Fetched
```bash
# Check what went wrong
journalctl -u clawdinator-secrets.service

# Common issues:
# - IAM role missing secretsmanager:GetSecretValue permission
# - Secret names don't match (should be clawdinator/*)
# - Network connectivity (check security group allows outbound)

# Verify IAM role can access secrets
aws secretsmanager get-secret-value --secret-id clawdinator/discord-token

# Check secrets exist
aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `clawdinator/`)].Name'
```

### Bootstrap Failed
```bash
# Check what went wrong
journalctl -u clawdinator-bootstrap.service

# Common issues:
# - S3 bucket permissions (instance IAM role needs s3:GetObject on bootstrap/*)
# - Missing repo-seeds bundle
# - Network connectivity (check security group allows outbound)
```

### EFS Mount Failed
```bash
# Check stunnel
systemctl status clawdinator-efs-stunnel.service
journalctl -u clawdinator-efs-stunnel.service

# Check mount
systemctl status memory.mount
mount | grep memory

# Verify EFS ID matches
grep fileSystemId /etc/stunnel/efs.conf
```

### Gateway Not Connecting to Discord
```bash
# Check logs for errors
journalctl -u clawdinator.service -f

# Verify Discord token is loaded
cat /run/agenix/clawdinator-discord-token

# Check network connectivity
curl -I https://discord.com/api/v10/gateway

# Verify config has correct channel IDs
cat /etc/clawd/openclaw.json | jq '.channels.discord'
```

### GitHub Token Not Working
```bash
# Check token service
systemctl status clawdinator-github-app-token.service
journalctl -u clawdinator-github-app-token.service

# Verify token exists
cat /run/clawd/github-app.env

# Test token
gh api user
```

## Accessing the Running Instance

**Via SSH:**
```bash
ssh root@$(cd infra/opentofu/aws && tofu output -raw instance_public_ip)
```

**Via AWS Systems Manager (if SSH fails):**
```bash
# Get instance ID
INSTANCE_ID=$(cd infra/opentofu/aws && tofu output -raw instance_id)

# Start SSM session
aws ssm start-session --target $INSTANCE_ID
```

**View gateway logs remotely:**
```bash
ssh root@$IP 'journalctl -u clawdinator.service -f'
```
