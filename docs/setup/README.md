# setup.northbuilt.com

GitHub Pages site for the NorthBuilt workstation setup.

## How It Works

The `index.html` file is **both** a webpage AND a bash script, using the same approach as [firebase.tools](https://firebase.tools):

- **Browsers** see the script with syntax highlighting (via Prism.js)
- **`curl | bash`** executes the script directly

## Files

- `index.html` - Dual-purpose: syntax-highlighted script + executable bash
- `CNAME` - Custom domain configuration

## Setup

### 1. Enable GitHub Pages

1. Go to repository Settings → Pages
2. Source: "Deploy from a branch"
3. Branch: `main`
4. Folder: `/docs/setup`
5. Save

### 2. Configure DNS

Add a CNAME record in your DNS provider:

```
Type:  CNAME
Name:  setup
Value: craftcodery.github.io
```

### 3. Wait for SSL

GitHub automatically provisions an SSL certificate (may take a few minutes).

## Usage

**Browser:** Visit https://setup.northbuilt.com to see the script with syntax highlighting.

**Terminal:**
```bash
curl -fsSL https://setup.northbuilt.com | bash
```

## Technical Details

The file structure follows the firebase.tools pattern:

```bash
#!/usr/bin/env bash

## <style>...</style>
## <script>...</script>
: ==========================================
:   Section Header
: ==========================================

# Regular comments
set -euo pipefail
...
```

- `##` lines are bash comments that contain HTML/CSS/JS - browsers parse the tags
- `:` is a bash no-op - used for readable section headers
- Prism.js provides syntax highlighting in the browser
- The script is fully visible and transparent
