import CDP from 'chrome-remote-interface';

const client = await CDP({ target: 'ws://localhost:9229/devtools/page/312A377E48964BCE8DEB8F20A57B75F6' });
const { Runtime } = client;
await Runtime.enable();

const r = await Runtime.evaluate({
  expression: `(() => {
    const c = document.querySelector('.chat-input-container.working');
    const s = document.querySelector('button[aria-label*="stop" i], button[title*="stop" i], .codicon-stop, .chat-stop-button');
    return {
      url: location.href,
      title: document.title,
      container: !!c,
      stopBtn: s ? { tag: s.tagName, ariaLabel: s.getAttribute('aria-label')||'', text: s.textContent?.slice(0,20)||'' } : null,
      hasAux: !!document.getElementById('workbench.parts.auxiliarybar'),
      lists: document.querySelectorAll('.monaco-list').length
    };
  })()`,
  returnByValue: true
});

console.log('Result:', JSON.stringify(r.result.value, null, 2));
client.close();
