# Testing Options

Before deploying to AWS, here are your testing options.

## Current State

**You cannot test yet because:**
- ✗ Nix daemon permission issue (need to join `nix-users` group)
- ✗ No Docker support in this repo (despite the name)
- ✗ Need access to `nix-secrets` repo for encrypted secrets

**You need to fix first:**
```bash
sudo usermod -aG nix-users james
# Then log out and log back in
```

---

## Option 1: Build Locally, Test Configuration (Recommended First Step)

**What:** Validate that your NixOS configuration builds without errors
**Time:** 5-10 minutes
**Cost:** Free (local compute only)
**Requires:** Nix working

```bash
# Fix Nix permissions first!
sudo usermod -aG nix-users james
# Log out and back in

# Then test:
nix develop
nix build .#clawdinator-system

# If it builds successfully, config is valid
# Output: result/ symlink pointing to built system
```

**What this tests:**
- ✓ NixOS configuration is syntactically correct
- ✓ All packages exist in nixpkgs
- ✓ Modules compile correctly
- ✗ Does NOT test runtime behavior
- ✗ Does NOT test AWS integration
- ✗ Does NOT run the actual service

**Use this to:** Catch syntax errors and missing packages before AWS deployment.

---

## Option 2: NixOS VM (Local Full System Test)

**What:** Run the full NixOS system in a local VM
**Time:** 15-30 minutes
**Cost:** Free (local compute)
**Requires:** Nix working, QEMU support

```bash
# Build a VM configuration
nix build .#nixosConfigurations.clawdinator-1.config.system.build.vm

# Run it
./result/bin/run-clawdinator-1-vm
```

**⚠️ Challenge:** This config is designed for AWS EC2, so you'd need to:
- Create a separate VM config (not AWS-specific)
- Mock or disable: S3 bootstrap, EFS mount, EC2 metadata
- Provide secrets manually

**What this tests:**
- ✓ Full NixOS system boots
- ✓ Services start correctly
- ✓ Configuration works end-to-end
- ✗ S3/EFS/AWS integration (would need mocking)

**Use this to:** Test service configuration and systemd units before AWS deployment.

---

## Option 3: Deploy to AWS (The Real Test)

**What:** Full production deployment
**Time:** ~50 minutes (40 min build + 10 min deploy)
**Cost:** ~$0.50-2.00/day (t3.small + EFS + S3)
**Requires:** AWS credentials, nix-secrets access

**Steps:**
1. Follow Phase 1 in README (infrastructure setup)
2. Follow Phase 2 in README (build and deploy instance)
3. Verify on Discord

**What this tests:**
- ✓ Everything (complete integration)
- ✓ Real AWS services
- ✓ Discord connection
- ✓ GitHub integration

**Use this to:** Final validation and production deployment.

---

## Option 4: GitHub Actions (CI Build Test)

**What:** Let GitHub Actions build the AMI (without deploying)
**Time:** 40 minutes
**Cost:** Free (GitHub Actions minutes)
**Requires:** GitHub secrets configured

```bash
# Trigger workflow
gh workflow run image-build.yml

# Watch it
gh run watch

# If it completes successfully:
# ✓ Image builds correctly
# ✓ All dependencies resolve
# ✓ Bootstrap bundle creates successfully

# If it fails:
# ✗ See logs for errors
```

**What this tests:**
- ✓ Full image build process
- ✓ All packages available
- ✓ Bootstrap bundle creation
- ✗ Does NOT deploy or run

**Use this to:** Validate changes before deploying to AWS.

---

## Recommended Testing Sequence

### Minimal (Fastest)

```bash
# 1. Fix Nix permissions
sudo usermod -aG nix-users james
# Log out/in

# 2. Test build
nix develop
nix build .#clawdinator-system
# ✓ If succeeds: config is valid

# 3. Deploy to AWS
# Follow README Phase 1 & 2
```

**Timeline:** 5 min local + 50 min AWS = 55 min total

---

### Cautious (More Validation)

```bash
# 1. Fix Nix permissions
sudo usermod -aG nix-users james
# Log out/in

# 2. Test local build
nix develop
nix build .#clawdinator-system

# 3. Test CI build (don't deploy yet)
gh workflow run image-build.yml
gh run watch
# ✓ If succeeds: image builds in CI

# 4. Deploy to AWS (with confidence)
# Follow README Phase 2
```

**Timeline:** 5 min local + 40 min CI + 10 min AWS = 55 min total

---

### Thorough (Full Local Testing)

This requires creating a VM config:

**Create:** `nix/hosts/clawdinator-1-vm.nix`

```nix
{ config, pkgs, lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/virtualisation/qemu-vm.nix")
    ./clawdinator-1-common.nix
  ];

  # Override for local testing
  services.clawdinator = {
    bootstrap.enable = lib.mkForce false;  # No S3 in VM
    memoryEfs.enable = lib.mkForce false;  # No EFS in VM
    memoryDir = lib.mkForce "/var/lib/clawd/memory";  # Local dir
    repoSeedSnapshotDir = lib.mkForce null;  # No repo seeds
    repoSeeds = lib.mkForce [];

    # Would need to provide secrets manually
    # Or disable features requiring secrets
  };

  # VM settings
  virtualisation.vmVariant = {
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
    virtualisation.forwardPorts = [
      { from = "host"; host.port = 18789; guest.port = 18789; }
    ];
  };
}
```

Then:
```bash
nix build .#nixosConfigurations.clawdinator-1-vm.config.system.build.vm
./result/bin/run-clawdinator-1-vm
```

**Challenge:** Would need significant config changes to work without AWS.

---

## What About Docker?

**The repo name is misleading.** There is no Docker support:
- No Dockerfile
- No docker-compose.yml
- Designed for NixOS, not containers

**If you wanted Docker support, you'd need to:**
1. Create Dockerfile
2. Install Nix inside container
3. Build NixOS config inside container
4. Much more complex than just using NixOS directly

**Not recommended.** This repo is designed for NixOS on EC2.

---

## My Recommendation

**Given your current state:**

1. **First:** Fix Nix permissions
   ```bash
   sudo usermod -aG nix-users james
   # Log out and back in
   ```

2. **Second:** Validate config builds locally
   ```bash
   nix develop
   nix build .#clawdinator-system
   ```

3. **Third:** Do you have access to `nix-secrets`?
   - ✓ Yes → Proceed to Phase 1 (AWS deployment)
   - ✗ No → Ask openclaw maintainers for access first

4. **Fourth:** Deploy to AWS
   - It's designed for AWS
   - Testing locally is complex (need to mock AWS services)
   - AWS deployment is the "real" test
   - Costs ~$1-2/day (can destroy after testing)

**Timeline if you start now:**
- Fix Nix: 5 min (one command + logout/login)
- Local build test: 5 min
- AWS Phase 1: 15 min (setup infrastructure)
- AWS Phase 2: 50 min (CI build + deploy)
- **Total: ~75 minutes to running CLAWDINATOR**

---

## Cost Breakdown (AWS)

If you're worried about cost:

**One-time (Phase 1):**
- S3 bucket: $0 (free tier)
- IAM roles: $0 (free)
- EFS: ~$0.01/day

**Per Instance (Phase 2):**
- t3.small EC2: ~$0.80/day (~$24/month)
- 40GB EBS: ~$0.13/day (~$4/month)
- EFS storage: ~$0.10/day (~$3/month) for 1GB
- S3 storage: ~$0.01/day for images

**Total: ~$1.00-2.00/day while instance runs**

**To minimize cost:**
```bash
# Destroy instance when not using
cd infra/opentofu/aws
export TF_VAR_ami_id=""
tofu apply  # Destroys instance, keeps S3/EFS/IAM

# Re-create when needed
export TF_VAR_ami_id=ami-xxxxx
tofu apply
```

---

## Summary

| Option | Time | Cost | What It Tests |
|--------|------|------|---------------|
| Local build | 5 min | Free | Config syntax |
| CI build | 40 min | Free | Full image build |
| AWS deploy | 50 min | $1-2/day | Everything |
| Local VM | 30+ min | Free | Service behavior (complex setup) |

**Recommended path:** Local build → AWS deploy → Test → Destroy if not using

You're building **production infrastructure**, not a development environment. AWS is the target, so AWS is the test.
