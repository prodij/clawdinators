# Quick Reference: Adding a Headless Browser

Want to add screenshot capability? Here's the exact diff:

## 1. Add Package (`nix/tools/clawdinator-tools.nix`)

```diff
{ pkgs }:
{
  packages = [
    pkgs.bash
    pkgs.gh
    pkgs.git
    pkgs.curl
    pkgs.jq
    pkgs.python3
    pkgs.ffmpeg
    pkgs.ripgrep
    pkgs.nodejs_22
    pkgs.pnpm_10
    pkgs.util-linux
    pkgs.nfs-utils
    pkgs.stunnel
    pkgs.awscli2
    pkgs.zstd
+   pkgs.playwright-driver.browsers  # Chromium, Firefox, WebKit
+   pkgs.chromium
  ];

  docs = [
    { name = "bash"; description = "Shell runtime for CLAWDINATOR scripts."; }
    # ... existing docs ...
    { name = "zstd"; description = "Compression tool for bootstrap archives."; }
+   { name = "playwright"; description = "Browser automation for screenshots."; }
+   { name = "chromium"; description = "Headless Chromium browser."; }
  ];
}
```

## 2. Create Helper Script (`scripts/screenshot.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

url="${1:?URL required}"
output="${2:?Output file required}"

chromium \
  --headless \
  --disable-gpu \
  --screenshot="$output" \
  --window-size=1920,1080 \
  "$url"

echo "Screenshot saved: $output"
```

```bash
chmod +x scripts/screenshot.sh
```

## 3. Make Available System-Wide (`nix/modules/clawdinator.nix`)

```diff
environment.systemPackages =
  [ cfg.package ]
  ++ toolchain.packages
  ++ [
    (pkgs.writeShellScriptBin "memory-read" ''exec /etc/clawdinator/bin/memory-read "$@"'')
    (pkgs.writeShellScriptBin "memory-write" ''exec /etc/clawdinator/bin/memory-write "$@"'')
    (pkgs.writeShellScriptBin "memory-edit" ''exec /etc/clawdinator/bin/memory-edit "$@"'')
+   (pkgs.writeShellScriptBin "screenshot" ''exec ${../../scripts/screenshot.sh} "$@"'')
  ];
```

## 4. Document for Agent (`clawdinator/workspace/TOOLS.md`)

Add to the file:

```markdown
## Screenshot Tool

### screenshot

Take screenshots of web pages.

**Usage:**
```bash
screenshot <url> <output-file>
```

**Example:**
```bash
screenshot https://example.com /tmp/example.png
```

**Use cases:**
- Visual debugging
- Capturing error states
- UI documentation
```

## 5. Deploy

```bash
# Commit changes
git add .
git commit -m "Add headless browser for screenshots"
git push origin main

# Build new AMI (GitHub Actions, ~40 min)
gh workflow run image-build.yml

# Get AMI ID
AMI=$(aws ec2 describe-images --region eu-central-1 --owners self \
  --filters "Name=tag:clawdinator,Values=true" \
  --query "Images|sort_by(@,&CreationDate)[-1].ImageId" --output text)

# Deploy
cd infra/opentofu/aws
export TF_VAR_ami_id=$AMI
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
tofu apply

# Wait ~5-7 min for boot, then test
ssh root@$(tofu output -raw instance_public_ip)
screenshot https://example.com /tmp/test.png
ls -lh /tmp/test.png
```

## That's It!

The agent can now use `screenshot` command in Discord conversations:

**User:** "Take a screenshot of example.com"

**CLAWDINATOR:** *runs `screenshot https://example.com /tmp/example.png` and shares result*

---

## The Flow

```
Your Edit          →  Git Push  →  CI Builds AMI  →  tofu apply  →  Instance Has Feature
(4 files)             (main)       (~40 min)         (~2 min)       (ready in ~7 min)
```

**Total time from idea to deployment:** ~50 minutes (mostly automated)
