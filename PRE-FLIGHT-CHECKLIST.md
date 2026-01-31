# Pre-Flight Checklist

Are you ready to deploy? Check off these items:

## Critical Blockers (Must Fix)

- [ ] **Nix daemon permissions**
  ```bash
  sudo usermod -aG nix-users $USER
  # Then log out and log back in (or run: newgrp nix-users)

  # Verify it worked:
  groups | grep nix-users  # Should show nix-users
  nix develop  # Should work without permission errors
  ```

- [ ] **AWS credentials work**
  ```bash
  aws sts get-caller-identity
  # Should show your AWS account ID and user ARN
  # Should NOT show error
  ```

- [ ] **Secrets ready** (you'll create these in AWS Secrets Manager)
  - [ ] Anthropic API key (from console.anthropic.com)
  - [ ] Discord bot token (from Discord Developer Portal)
  - [ ] GitHub App private key (.pem file)

## Optional (Can Skip for Testing)

- [ ] GitHub CLI installed and authenticated
  ```bash
  gh auth status
  ```

- [ ] Understanding of costs
  - ~$1-2/day while instance runs
  - Can destroy instance when not using (keeps data)
  - See [docs/TESTING-OPTIONS.md](docs/TESTING-OPTIONS.md) for cost breakdown

## Your Current Status

Based on our conversation:

```
✓ Cloned repository
✓ Nix installed (version 2.18.1)
✓ Nix experimental features enabled
✓ AWS credentials configured (account: 644002404006)
✓ SSH key exists (~/.ssh/id_ed25519.pub)
? Nix-users group membership (may need to verify)
? Secrets ready (Anthropic API key, Discord token, GitHub App key)
```

## Next Steps

### If You Have the Secrets (15 min)

```bash
# 1. Fix Nix permissions (if needed)
sudo usermod -aG nix-users $USER
newgrp nix-users

# 2. Verify
nix develop
# Should enter dev shell without errors

# 3. Proceed to README Phase 1
```

**Then proceed to README Phase 1.**

### If You Don't Have All Secrets Yet

**Get these first:**
1. **Anthropic API key**: console.anthropic.com → API Keys
2. **Discord bot token**: discord.com/developers → Applications → Bot → Token
3. **GitHub App private key**: GitHub → Settings → Developer → GitHub Apps → Generate private key

**Once you have them, follow README from the beginning.**

### If You Just Want to Test the Config

```bash
# After fixing Nix permissions:
nix develop
nix build .#clawdinator-system

# If it builds successfully (no errors):
# ✓ Your NixOS configuration is valid
# ✓ All packages are available
# ✓ Ready for AWS deployment when you have secrets
```

## Decision Tree

```
Do you have all 3 secrets?
├─ YES → Fix Nix permissions → Follow README Phase 1 (60 min)
│
└─ NO → Get secrets first → Then follow README
```

## Estimated Timeline

**If everything is ready:**

```
Fix Nix permissions:        5 min
AWS Phase 1 (infra):       15 min
Create Secrets Manager:     5 min
GitHub Actions (AMI):      40 min
AWS Phase 2 (deploy):      10 min
                          --------
Total:                    ~75 min
```

## Am I Ready? (Quick Check)

Run these commands:

```bash
# 1. Nix works?
nix develop
# ✓ Should enter dev shell
# ✗ Permission denied → Fix nix-users group

# 2. AWS works?
aws sts get-caller-identity
# ✓ Shows your account
# ✗ Error → Fix AWS credentials

# 3. Secrets ready?
# Do you have:
# - Anthropic API key (sk-ant-...)
# - Discord bot token
# - GitHub App .pem file
```

**If all 3 are ✓ → You're ready!**
**If any are ✗ → Fix them first**

## The Minimal Path Forward

Want to just see if the config builds?

```bash
# 1. Fix Nix (required)
sudo usermod -aG nix-users $USER
newgrp nix-users

# 2. Test build (5 minutes)
cd ~/Projects/clawdbot-docker
nix develop
nix build .#clawdinator-system

# If successful:
# → Config is valid
# → You understand the basics
# → Ready for AWS when you have secrets
```

This proves the system works without requiring:
- AWS costs
- Actual secrets
- 75 minutes of waiting

**Then decide:** Deploy to AWS now, or wait?

## My Recommendation

**For you right now:**

1. Fix Nix permissions (5 min)
2. Test local build (5 min)
3. Get your secrets ready (Anthropic key, Discord token, GitHub App key)
4. Then decide: Deploy to AWS or wait?

**Don't deploy to AWS until you:**
- ✓ Can run `nix develop` without errors
- ✓ Have all 3 secrets ready
- ✓ Understand the ~$1-2/day cost
- ✓ Are ready to commit ~75 minutes

**The good news:** Steps 1-2 take 10 minutes and prove everything works.
