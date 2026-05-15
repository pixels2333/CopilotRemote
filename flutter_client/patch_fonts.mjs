import fs from 'fs';

const p = 'd:/programme/CopilotRemote/flutter_client/build/web/index.html';
let html = fs.readFileSync(p, 'utf8');

// Remove the old 404-based interceptor
html = html.replace(
  /var origFetch = window\.fetch;[\s\S]*?return origFetch\.call\(this, url, opts\);[\s\S]*?\};/,
  ''
);

// Add new font redirect interceptor after <body>
const interceptor = `
  <script>
    (function() {
      var REDIRECTS = {
        'fonts.gstatic.com/s/roboto': '/fonts-local/Roboto.woff2',
        'fonts.gstatic.com/s/notosanssymbols2': '/fonts-local/NotoSansSymbols2.woff2'
      };
      var origFetch = window.fetch;
      window.fetch = function(url, opts) {
        var urlStr = typeof url === 'string' ? url : (url && url.url) || '';
        for (var key in REDIRECTS) {
          if (urlStr.indexOf(key) !== -1) {
            return origFetch(REDIRECTS[key], opts);
          }
        }
        return origFetch.call(this, url, opts);
      };
    })();
  </script>`;

html = html.replace('<body>', '<body>' + interceptor);

fs.writeFileSync(p, html);
console.log('OK');
