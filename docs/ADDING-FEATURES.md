# Adding Features to CLAWDINATOR

This guide shows how to extend CLAWDINATOR with new capabilities. We'll use adding a headless browser for screenshots as a complete example.

## Example: Adding Playwright for Screenshot Capability

**Goal:** Enable the AI agent to take screenshots of websites using a headless browser.

**What we'll add:**
- Playwright package (browser automation framework)
- Chromium browser (headless)
- A wrapper script for easy screenshots
- Documentation for the agent

---

## Step 1: Add Packages to Toolchain

**File:** `nix/tools/clawdinator-tools.nix`

```nix
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

    # NEW: Headless browser tools
    pkgs.playwright-driver.browsers  # Chromium, Firefox, WebKit
    pkgs.chromium                    # Standalone Chromium
  ];

  docs = [
    { name = "bash"; description = "Shell runtime for CLAWDINATOR scripts."; }
    { name = "gh"; description = "GitHub CLI for repo + PR inventory."; }
    { name = "openclaw-gateway"; description = "CLAWDINATOR runtime (Clawbot gateway)."; }
    { name = "git"; description = "Repo sync + ops."; }
    { name = "curl"; description = "HTTP requests."; }
    { name = "jq"; description = "JSON processing."; }
    { name = "python3"; description = "Moltbot dev chain dependency."; }
    { name = "ffmpeg"; description = "Media processing."; }
    { name = "ripgrep"; description = "Fast file search."; }
    { name = "nodejs_22"; description = "Moltbot dev chain runtime."; }
    { name = "pnpm_10"; description = "Moltbot dev chain package manager."; }
    { name = "util-linux"; description = "Provides flock used by memory wrappers."; }
    { name = "nfs-utils"; description = "NFS client utilities for EFS."; }
    { name = "stunnel"; description = "TLS tunnel for EFS in transit."; }
    { name = "awscli2"; description = "AWS CLI for bootstrap S3 pulls."; }
    { name = "zstd"; description = "Compression tool for bootstrap archives."; }

    # NEW: Browser documentation
    { name = "playwright"; description = "Browser automation for screenshots and testing."; }
    { name = "chromium"; description = "Headless browser (Chromium)."; }
  ];
}
```

**What this does:**
- Adds `playwright-driver.browsers` (includes Chromium, Firefox, WebKit)
- Adds `chromium` as standalone binary
- Documents them so the agent knows they exist

---

## Step 2: Create Helper Script

**File:** `scripts/screenshot.sh` (new file)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: screenshot.sh <url> <output-file>
# Example: screenshot.sh https://example.com /tmp/example.png

url="${1:?URL required}"
output="${2:?Output file required}"

# Use Playwright with Chromium to take screenshot
npx -y playwright@latest screenshot \
  --browser chromium \
  --viewport-size 1920,1080 \
  "$url" \
  "$output"

echo "Screenshot saved to: $output"
```

Make it executable:
```bash
chmod +x scripts/screenshot.sh
```

**Or use a Node.js script for more control:**

**File:** `scripts/screenshot.js` (new file)

```javascript
#!/usr/bin/env node
// Usage: node screenshot.js <url> <output-file> [options]

const { chromium } = require('playwright');

async function takeScreenshot(url, outputPath, options = {}) {
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    ...options
  });

  const page = await context.newPage();
  await page.goto(url, { waitUntil: 'networkidle' });

  // Optional: Wait for specific elements
  if (options.waitForSelector) {
    await page.waitForSelector(options.waitForSelector);
  }

  await page.screenshot({
    path: outputPath,
    fullPage: options.fullPage || false
  });

  await browser.close();
  console.log(`Screenshot saved to: ${outputPath}`);
}

// Parse command line arguments
const url = process.argv[2];
const output = process.argv[3];

if (!url || !output) {
  console.error('Usage: node screenshot.js <url> <output-file>');
  process.exit(1);
}

takeScreenshot(url, output, {
  fullPage: process.argv.includes('--full-page')
}).catch(err => {
  console.error('Screenshot failed:', err);
  process.exit(1);
});
```

---

## Step 3: Install Playwright in NixOS Module

**File:** `nix/modules/clawdinator.nix`

Add Playwright installation to the service:

```nix
systemd.services.clawdinator = {
  # ... existing config ...

  environment = {
    CLAWDBOT_CONFIG_PATH = configPath;
    CLAWDBOT_STATE_DIR = cfg.stateDir;
    CLAWDBOT_WORKSPACE_DIR = workspaceDir;
    CLAWDBOT_LOG_DIR = logDir;

    # NEW: Playwright environment variables
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";  # Use Nix-provided browsers
  };

  serviceConfig = {
    # ... existing config ...

    # NEW: Install Playwright npm package at service start
    ExecStartPre = [
      # Existing pre-start scripts...

      # Install Playwright (if not using global install)
      "+${pkgs.bash}/bin/bash -c 'cd ${cfg.stateDir} && ${pkgs.pnpm_10}/bin/pnpm add -g playwright'"
    ];
  };
};
```

**Alternative: Global Playwright Installation**

If you want Playwright available system-wide:

```nix
environment.systemPackages = [
  cfg.package
  (pkgs.writeShellScriptBin "screenshot" ''
    ${pkgs.nodejs_22}/bin/node ${../../scripts/screenshot.js} "$@"
  '')
] ++ toolchain.packages;
```

---

## Step 4: Add to Agent Workspace Documentation

**File:** `clawdinator/workspace/TOOLS.md`

Add documentation so the agent knows how to use it:

```markdown
## Screenshot Tools

### screenshot command

Take screenshots of web pages for debugging or analysis.

**Usage:**
```bash
screenshot <url> <output-file>
```

**Examples:**
```bash
# Basic screenshot
screenshot https://example.com /tmp/example.png

# Full page screenshot
node /usr/local/bin/screenshot.js https://example.com /tmp/page.png --full-page

# Via Playwright CLI
npx playwright screenshot https://example.com output.png
```

**Use cases:**
- Visual debugging of web applications
- Capturing error states
- Documenting UI issues
- Testing responsive designs

**Available browsers:**
- Chromium (default)
- Firefox
- WebKit

**Environment:**
- `PLAYWRIGHT_BROWSERS_PATH`: Pre-installed browser binaries
- Browsers are managed by Nix, no manual installation needed
```

---

## Step 5: Test Locally

Before deploying, test that everything works:

```bash
# Enter dev environment
nix develop

# Build the NixOS configuration
nix build .#clawdinator-system

# Test that packages are available
nix-shell -p playwright-driver.browsers chromium

# Test the screenshot script
node scripts/screenshot.js https://example.com /tmp/test.png
# Should create /tmp/test.png
```

---

## Step 6: Deploy the Changes

### Option A: Quick Test (Loop 3)

If you already have a running instance and want to test quickly:

```bash
# Commit your changes
git add .
git commit -m "Add Playwright for screenshots"
git push origin main

# SSH into running instance
ssh root@instance-ip

# Pull changes
cd /var/lib/clawd/repos/clawdinators
git pull origin main

# Rebuild
nixos-rebuild switch --flake .#clawdinator-1

# Restart gateway
systemctl restart clawdinator.service

# Test it
screenshot https://example.com /tmp/test.png
ls -lh /tmp/test.png
```

### Option B: Full Deployment (Loop 2)

For production deployment:

```bash
# Commit your changes
git add .
git commit -m "Add Playwright screenshot capability"
git push origin main

# Trigger GitHub Actions to build new AMI
gh workflow run image-build.yml

# Wait ~40 minutes for build to complete

# Get new AMI ID
AMI=$(aws ec2 describe-images --region eu-central-1 --owners self \
  --filters "Name=tag:clawdinator,Values=true" \
  --query "Images|sort_by(@,&CreationDate)[-1].ImageId" --output text)

# Deploy with OpenTofu
cd infra/opentofu/aws
export TF_VAR_ami_id=$AMI
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
tofu apply
```

---

## Step 7: Verify on Running Instance

```bash
ssh root@instance-ip

# Check that packages are installed
which chromium
playwright --version

# Check environment variables
env | grep PLAYWRIGHT

# Test screenshot
screenshot https://example.com /tmp/test.png
file /tmp/test.png  # Should show: PNG image data

# Check in agent workspace
cat /var/lib/clawd/workspace/TOOLS.md | grep -A 10 "Screenshot"
```

---

## Alternative Approaches

### Option 1: Python with Selenium

If you prefer Python:

**Add to toolchain:**
```nix
pkgs.python3.withPackages (ps: [ ps.selenium ])
pkgs.chromedriver
```

**Script:**
```python
#!/usr/bin/env python3
from selenium import webdriver
from selenium.webdriver.chrome.options import Options

options = Options()
options.add_argument('--headless')
options.add_argument('--no-sandbox')
options.add_argument('--disable-dev-shm-usage')

driver = webdriver.Chrome(options=options)
driver.get('https://example.com')
driver.save_screenshot('/tmp/screenshot.png')
driver.quit()
```

### Option 2: Simple with Chromium CLI

Chromium has a built-in screenshot mode:

```bash
#!/usr/bin/env bash
chromium \
  --headless \
  --disable-gpu \
  --screenshot=/tmp/output.png \
  --window-size=1920,1080 \
  "$1"
```

### Option 3: Use Playwright Docker (within NixOS)

Add Docker and use Playwright's official image:

```nix
virtualisation.docker.enable = true;

# Then use:
# docker run --rm -v /tmp:/screenshots mcr.microsoft.com/playwright:v1.40.0 \
#   playwright screenshot https://example.com /screenshots/out.png
```

---

## Creating a Skill for Screenshot

For openclaw/clawbot integration, create a skill:

**File:** `clawdinator/workspace/skills/screenshot/skill.yaml`

```yaml
name: screenshot
description: Take screenshots of web pages
version: 1.0.0

tools:
  - name: take_screenshot
    description: Capture a screenshot of a URL
    parameters:
      url:
        type: string
        description: The URL to screenshot
        required: true
      output_path:
        type: string
        description: Where to save the screenshot
        default: /tmp/screenshot.png
      full_page:
        type: boolean
        description: Capture full scrollable page
        default: false

    command: |
      #!/usr/bin/env bash
      set -euo pipefail

      URL="{{url}}"
      OUTPUT="{{output_path}}"
      FULL_PAGE="{{full_page}}"

      if [ "$FULL_PAGE" = "true" ]; then
        node /usr/local/bin/screenshot.js "$URL" "$OUTPUT" --full-page
      else
        node /usr/local/bin/screenshot.js "$URL" "$OUTPUT"
      fi

      echo "Screenshot saved: $OUTPUT"
      echo "Size: $(du -h "$OUTPUT" | cut -f1)"
```

---

## Best Practices

1. **Resource Management**: Headless browsers use memory. Monitor usage:
   ```bash
   # In NixOS config, limit service memory if needed
   systemd.services.clawdinator.serviceConfig.MemoryMax = "2G";
   ```

2. **Cleanup**: Screenshots can accumulate. Add cleanup:
   ```bash
   # Cron job to clean old screenshots
   systemd.timers.screenshot-cleanup = {
     wantedBy = [ "timers.target" ];
     timerConfig.OnCalendar = "daily";
   };

   systemd.services.screenshot-cleanup = {
     script = ''
       find /tmp -name "*.png" -mtime +7 -delete
       find /var/lib/clawd/screenshots -mtime +7 -delete
     '';
   };
   ```

3. **Security**: Run browser as unprivileged user:
   ```nix
   users.users.browseruser = {
     isSystemUser = true;
     group = "browseruser";
   };

   # Use DynamicUser in service
   systemd.services.screenshot.serviceConfig.DynamicUser = true;
   ```

4. **Performance**: Use browser pools for multiple screenshots:
   ```javascript
   // Keep browser instance alive, reuse contexts
   const browserPool = new BrowserPool({ max: 3 });
   ```

---

## Summary

Adding features to CLAWDINATOR follows this pattern:

1. **Add packages** to `nix/tools/clawdinator-tools.nix`
2. **Create helper scripts** in `scripts/` (optional)
3. **Configure environment** in `nix/modules/clawdinator.nix`
4. **Document for agent** in `clawdinator/workspace/TOOLS.md`
5. **Test locally** with `nix build`
6. **Deploy** via AMI rebuild (Loop 2)

The same pattern works for:
- Database clients (PostgreSQL, MongoDB)
- Image processing (ImageMagick, GraphicsMagick)
- Video tools (ffmpeg - already included)
- Cloud CLIs (gcloud, azure-cli)
- Any tool available in nixpkgs

Check available packages: https://search.nixos.org/packages
