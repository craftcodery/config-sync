# setup.northbuilt.com

GitHub Pages site for the NorthBuilt workstation setup landing page.

## Files

- `index.html` - Landing page with documentation and copy button
- `install` - The actual setup script (served as plain text)
- `CNAME` - Custom domain configuration

## Setup

### 1. Enable GitHub Pages

1. Go to repository Settings → Pages
2. Source: "Deploy from a branch"
3. Branch: `main`
4. Folder: `/docs/setup`
5. Save

### 2. Configure DNS

Add a CNAME record in your DNS:

```
setup.northbuilt.com → craftcodery.github.io
```

### 3. Wait for SSL

GitHub automatically provisions an SSL certificate. This may take a few minutes.

## Usage

**Browser:** Visit https://setup.northbuilt.com to see the documentation.

**Terminal:**
```bash
curl -fsSL https://setup.northbuilt.com/install | bash
```

## Keeping the Script Updated

The `install` file is a copy of `setup.sh` from the repo root. When updating `setup.sh`, also update this file:

```bash
cp setup.sh docs/setup/install
git add docs/setup/install
git commit -m "Update install script"
git push
```

Or create a pre-commit hook to do this automatically.
