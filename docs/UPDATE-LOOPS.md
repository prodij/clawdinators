# Update Loops

This document explains how code changes enter the CLAWDINATOR deployment and the different update paths available.

## The Three Update Loops

### Loop 1: Automatic Self-Update (Daily)

**What it updates:** Upstream dependencies (openclaw, nix-openclaw, nixpkgs)
**When:** Daily, via systemd timer
**Where:** On the running instance

```
┌─────────────────────────────────────────────────────────────┐
│                    Daily Timer Triggers                      │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Instance: /var/lib/clawd/repos/clawdinators                │
│                                                               │
│  1. git pull origin main                                     │
│  2. nix flake update  (updates flake.lock)                   │
│  3. nixos-rebuild switch --flake .#clawdinator-1             │
│                                                               │
│  flake.lock before:                                          │
│    nix-openclaw: commit abc123                               │
│                                                               │
│  flake.lock after:                                           │
│    nix-openclaw: commit def456  ← Latest from upstream       │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Gateway Restarts with New Version               │
└─────────────────────────────────────────────────────────────┘
```

**What happens:**
1. Timer runs at the configured schedule (default: daily)
2. Pulls latest clawdinators repo from GitHub
3. Runs `nix flake update` which updates `flake.lock`:
   - Fetches latest `github:openclaw/nix-openclaw`
   - Fetches latest `nixpkgs` (following nix-openclaw)
   - Fetches latest `agenix`
4. Runs `nixos-rebuild switch` which:
   - Rebuilds the system with new packages
   - Updates the gateway binary to the latest openclaw version
   - Restarts affected services
5. Gateway automatically restarts with new code

**No human intervention needed.** The instance keeps itself up to date.

**Configuration:**
```nix
# In nix/hosts/clawdinator-1-common.nix
selfUpdate.enable = true;
selfUpdate.flakePath = "/var/lib/clawd/repos/clawdinators";
selfUpdate.flakeHost = "clawdinator-1";
```

---

### Loop 2: Configuration Changes (Manual AMI Rebuild)

**What it updates:** NixOS configuration, infrastructure, scripts
**When:** When you change .nix files, configs, or scripts
**Where:** Full AMI rebuild and redeploy

```
┌─────────────────────────────────────────────────────────────┐
│           You Edit Code Locally                              │
│  - nix/modules/clawdinator.nix (module config)               │
│  - nix/hosts/clawdinator-1-common.nix (host config)          │
│  - scripts/*.sh (deployment scripts)                         │
│  - clawdinator/workspace/* (agent templates)                 │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              git commit && git push origin main              │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│           GitHub Actions Workflow Triggers                   │
│  (.github/workflows/image-build.yml)                         │
│                                                               │
│  1. Builds NixOS image with nixos-generators                 │
│  2. Uploads image to S3                                      │
│  3. Imports as AMI                                           │
│  4. Tags AMI with clawdinator=true                           │
│                                                               │
│  Output: ami-new123456                                       │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│         You Deploy the New AMI (Manual Step)                 │
│                                                               │
│  cd infra/opentofu/aws                                       │
│  export TF_VAR_ami_id=ami-new123456                          │
│  tofu apply                                                  │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              New Instance Launches                           │
│  - Uses your updated configuration                           │
│  - Runs bootstrap from S3                                    │
│  - Starts gateway with new setup                             │
└─────────────────────────────────────────────────────────────┘
```

**When to use this:**
- Changing Discord channel allowlist
- Changing systemd service configuration
- Adding new tools to the toolchain
- Modifying workspace templates
- Updating bootstrap scripts

**Example:**
```bash
# You want to change the Discord channel configuration
vim nix/hosts/clawdinator-1-common.nix
# Edit channels.discord.guilds section

git commit -m "Add #new-channel to allowlist"
git push origin main

# Wait for GitHub Actions to complete (~40 min)
# Get the new AMI ID
AMI=$(aws ec2 describe-images ... | get latest)

# Deploy it
cd infra/opentofu/aws
export TF_VAR_ami_id=$AMI
tofu apply
```

---

### Loop 3: Quick Updates (Git Pull + Rebuild)

**What it updates:** Anything in the clawdinators repo
**When:** For urgent fixes without waiting for full AMI rebuild
**Where:** Directly on the running instance

```
┌─────────────────────────────────────────────────────────────┐
│      You Push Urgent Fix to GitHub                           │
│  git push origin main                                        │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│         SSH into Running Instance                            │
│  ssh root@instance-ip                                        │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│    Pull Latest Code and Rebuild                              │
│                                                               │
│  cd /var/lib/clawd/repos/clawdinators                        │
│  git pull origin main                                        │
│  nixos-rebuild switch --flake .#clawdinator-1                │
│                                                               │
│  systemctl restart clawdinator.service                       │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│         Instance Now Runs Updated Code                       │
│  (Changes persist until instance is replaced)                │
└─────────────────────────────────────────────────────────────┘
```

**When to use this:**
- Emergency fixes that can't wait for AMI rebuild
- Testing changes before committing to full rebuild
- Debugging on a live instance

**⚠️ Important:** Changes made this way are **not baked into the AMI**. If you:
- Redeploy the instance with the old AMI
- Instance reboots
- Self-update runs

...your manual changes will be lost (unless they were also committed to git and pulled by self-update).

**Best practice:** After using this method, follow up with Loop 2 (AMI rebuild) to make changes permanent.

---

## What Updates Through Which Loop?

| What Changed | Loop to Use | Why |
|--------------|-------------|-----|
| openclaw runtime code | Loop 1 (Automatic) | Tracked via nix-openclaw flake input |
| nix-openclaw package | Loop 1 (Automatic) | Tracked via flake input |
| NixOS module config | Loop 2 (AMI rebuild) | Baked into image |
| Discord channel list | Loop 2 (AMI rebuild) | In host config |
| Workspace templates | Loop 2 (AMI rebuild) | Baked into image |
| Bootstrap scripts | Loop 2 (AMI rebuild) | Baked into image |
| Urgent bug fix | Loop 3 (Quick update) | Then follow with Loop 2 |
| Testing changes | Loop 3 (Quick update) | For experimentation |

---

## Understanding flake.lock

The `flake.lock` file pins exact versions of dependencies:

```json
{
  "nix-openclaw": {
    "locked": {
      "owner": "openclaw",
      "repo": "nix-openclaw",
      "rev": "abc123...",  ← Exact git commit
      "narHash": "sha256-..."  ← Hash of the content
    }
  }
}
```

**When you run `nix flake update`:**
- Fetches latest commit from `github:openclaw/nix-openclaw`
- Updates the `rev` and `narHash` in flake.lock
- Next rebuild uses the new version

**Manual update:**
```bash
# Update all inputs
nix flake update

# Update specific input
nix flake lock --update-input nix-openclaw

# Commit the updated flake.lock
git add flake.lock
git commit -m "Update nix-openclaw to latest"
```

---

## Development Workflow Examples

### Example 1: Upstream openclaw releases new feature

**What happens automatically:**
1. openclaw team pushes new code to `github:openclaw/openclaw`
2. nix-openclaw team updates their package to point to new version
3. **Loop 1** (self-update) runs on your instance (daily)
4. Instance pulls latest flake.lock → points to new nix-openclaw → includes new openclaw
5. Gateway restarts with new feature

**No action required from you.**

### Example 2: You want to change the Discord allowlist

**You must use Loop 2:**
1. Edit `nix/hosts/clawdinator-1-common.nix`
2. Change the `channels.discord.guilds` section
3. Commit and push to main
4. GitHub Actions builds new AMI (~40 min)
5. You deploy new AMI with `tofu apply`
6. New instance uses updated allowlist

### Example 3: Emergency fix needed NOW

**Use Loop 3, then Loop 2:**
1. Fix the bug in your local clone
2. Commit and push to main
3. SSH into running instance
4. `cd /var/lib/clawd/repos/clawdinators && git pull`
5. `nixos-rebuild switch --flake .#clawdinator-1`
6. Fix is live immediately
7. **Then:** Trigger AMI rebuild (Loop 2) to make it permanent

---

## Monitoring Updates

### Check what version is running

```bash
ssh root@instance-ip

# Check clawdinators repo version
cd /var/lib/clawd/repos/clawdinators
git log -1 --oneline

# Check nix-openclaw version
nix flake metadata | grep nix-openclaw
```

### Check when self-update last ran

```bash
systemctl status clawdinator-self-update.service

# Check timer
systemctl list-timers | grep self-update
```

### Check self-update logs

```bash
journalctl -u clawdinator-self-update.service
```

---

## Summary

**Three loops, three purposes:**

1. **Loop 1 (Automatic)**: Keeps upstream dependencies fresh daily
2. **Loop 2 (Manual AMI)**: Deploys configuration and infrastructure changes
3. **Loop 3 (Quick)**: Emergency fixes and testing

**Golden rule:** Changes to `.nix` files or templates need Loop 2 (AMI rebuild). Everything else can use Loop 1 (automatic) or Loop 3 (quick fix).
