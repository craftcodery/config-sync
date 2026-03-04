// Cloudflare Worker for setup.northbuilt.com
// Serves the install script with smart content-type detection
//
// - Browsers get text/html (renders the documentation page)
// - curl/wget get text/plain (for piping to bash)
//
// Deploy: wrangler deploy

const SCRIPT_URL = 'https://raw.githubusercontent.com/craftcodery/northbuilt-workstation-config/main/web/install';

export default {
  async fetch(request) {
    // Fetch the install script from GitHub
    const scriptResponse = await fetch(SCRIPT_URL);
    const scriptContent = await scriptResponse.text();

    // Detect if this is a browser or CLI tool
    const userAgent = request.headers.get('User-Agent') || '';
    const accept = request.headers.get('Accept') || '';

    const isBrowser = accept.includes('text/html') &&
                      !userAgent.includes('curl') &&
                      !userAgent.includes('wget') &&
                      !userAgent.includes('HTTPie');

    // Set appropriate content type
    const contentType = isBrowser ? 'text/html; charset=utf-8' : 'text/plain; charset=utf-8';

    return new Response(scriptContent, {
      headers: {
        'Content-Type': contentType,
        'Cache-Control': 'public, max-age=300',
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
      },
    });
  },
};
