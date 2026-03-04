# setup.northbuilt.com

GitHub Pages site for the NorthBuilt workstation setup.

## How It Works

The `index.html` file is **both** a webpage AND a bash script:

- **Browsers** render the HTML (JavaScript cleans up the bash artifacts)
- **`curl | bash`** executes the script (bash ignores the HTML via heredoc)

This is similar to how [firebase.tools](https://firebase.tools) works.

## Files

- `index.html` - Dual-purpose: landing page + setup script
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

**Browser:** Visit https://setup.northbuilt.com

**Terminal:**
```bash
curl -fsSL https://setup.northbuilt.com | bash
```

## Technical Details

The file structure:

```bash
#!/bin/bash
: <<'HTML_CONTENT'
<!DOCTYPE html>
<html>... (full HTML page) ...</html>
HTML_CONTENT

# Actual bash script here
set -euo pipefail
...
```

- The `: <<'HTML_CONTENT'` is a bash heredoc that discards its content
- Browsers see `#!/bin/bash` and `: <<'HTML_CONTENT'` as text, but JavaScript removes these text nodes
- The page is hidden (`opacity: 0`) until JS cleanup completes, then fades in
