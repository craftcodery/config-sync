# setup.northbuilt.com

This directory contains the dual-purpose install script and Cloudflare Worker configuration for `setup.northbuilt.com`.

## How It Works

The `install` file is both:
1. **A valid bash script** - When piped to bash, it executes the setup
2. **A webpage** - When viewed in a browser, it shows documentation

The HTML is wrapped in a bash heredoc that's discarded:
```bash
: <<'END_HTML'
<!DOCTYPE html>
...
END_HTML
```

The `:` command does nothing, and the heredoc content is never executed.

## Deployment

### Option 1: Cloudflare Worker (Recommended)

1. Install Wrangler:
   ```bash
   npm install -g wrangler
   ```

2. Authenticate:
   ```bash
   wrangler login
   ```

3. Deploy:
   ```bash
   cd web
   wrangler deploy
   ```

4. Configure custom domain in Cloudflare dashboard:
   - Go to Workers & Pages → northbuilt-setup → Settings → Triggers
   - Add Custom Domain: `setup.northbuilt.com`

### Option 2: Cloudflare Pages

1. Connect repo to Cloudflare Pages
2. Set build output directory to `web`
3. Configure custom domain: `setup.northbuilt.com`

Note: Pages uses the `_headers` and `_redirects` files, but doesn't do content-type negotiation. The Worker approach is better.

## Testing Locally

```bash
# Verify bash syntax
bash -n install

# Test execution (will actually run setup!)
# bash install

# Preview HTML (open in browser)
# python3 -m http.server 8000
# Then visit http://localhost:8000/install
```

## Usage

Once deployed:

```bash
curl -fsSL https://setup.northbuilt.com | bash
```

Or visit https://setup.northbuilt.com in a browser to see the documentation.
