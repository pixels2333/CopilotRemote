const fs = require('fs');
const path = require('path');

const BASE = 'D:/programme/CopilotRemote/flutter_client/lib';

// Helper to write file cleanly (binary-safe)
function w(fn, c) {
  fs.writeFileSync(path.join(BASE, fn), c, 'utf8');
  console.log('WROTE ' + fn + ' (' + c.length + ' bytes)');
}

// === 1. dom_scripts.dart - All injected JavaScript ===
w('services/dom_scripts.dart', `
/// JavaScript scripts injected into the VS Code Copilot page via CDP.
class DomScripts {

  /// Observer script: injected once, extracts messages via polling.
  /// Emits data via window.__copilotMirrorEmit().
  static String get observer => '''
(() => {
  if (window.__copilotMirrorInstalled) return;
  window.__copilotMirrorInstalled = true;

  function emit(payload) {
    const json = JSON.stringify(payload);
    try { if (typeof window.__copilotMirrorEmit === 'function') { window.__copilotMirrorEmit(json); return; } catch (_) {}
    console.log('[CopilotMirror]' + json);
  }

  function hash(v) { let h=0; for(let i=0;i<v.length;i++){h=((h<<5)-h)+v.charCodeAt(i);h|=0} return Math.abs(h).toString(36); }
  function stableId(p,v) { return p + '_' + hash(v); }
  function textOf(n) { return (n.textContent || n.innerText || '').replace(/\\u00a0/g,' ').trim(); }

  function findList() {
    const aux = document.getElementById('workbench.parts.auxiliarybar');
    if (!aux) return null;
    const p = aux.querySelector('.interactive-list .monaco-list, .chat-list-at-bottom .monaco-list');
    if (p) return p;
    return aux.querySelectorAll('.monaco-list');
    const lists = Array.from(aux.querySelectorAll('.monaco-list'));
    return lists.find(l => {
      if (l.closest('.interactive-list, .chat-list-at-bottom')) return true;
      return Array.from(l.querySelectorAll('.monaco-list-row')).some(r => /request|response/.test((r.className||'').toLowerCase()));
    }) || null;
  }

  function getRows(list) { return Array.from(list.querySelectorAll('.monaco-list-row')).filter(r => r instanceof HTMLElement); }
  function rowRole(r) { return (r.className||'').toLowerCase().includes('request') ? 'user' : 'assistant'; }

  function extractBlocks(row, msgId) {
    const blocks = [];
    const contents = row.querySelector('.monaco-tl-contents') || row;
    if (!contents) {
      const t = textOf(row); if (t) blocks.push({id:stableId('tx_',t.slice(0,64)),type:'text',status:'completed',format:'markdown',content:t});
      return blocks;
    }
    // Thinking
    contents.querySelectorAll('.chat-used-context.chat-thinking-box').forEach(el => {
      const t = el.querySelector('.chat-thinking-title-detail-text');
      const title = t ? textOf(t) : '';
      const items = Array.from((el.querySelector('.chat-used-context-list')||el).querySelectorAll('.chat-thinking-item.markdown-content'))
        .filter(item => !item.closest('.chat-thinking-tool-wrapper'))
        .map(item => textOf(item))
        .filter(t => t && t !== '思考' && t.toLowerCase() !== 'thinking');
      const c = items.join('\\n\\n').trim();
      if (c) blocks.push({id:stableId('th_',msgId+c.slice(0,32)),type:'thinking',status:'completed',format:'plain',content:c,visibility:'collapsed',title:title||'Thinking'});
    });
    // Tool calls
    contents.querySelectorAll('.chat-thinking-tool-wrapper').forEach(el => {
      const icon = el.querySelector('.chat-thinking-icon')?.className || '';
      const inv = el.querySelector('.chat-tool-invocation-part') || el;
      const label = inv.querySelector('.chat-used-context-label');
      const dn = label ? textOf(label) : 'Tool';
      const summary = textOf(inv) || dn;
      if (!summary && dn==='Tool') return;
      const toolName = icon.includes('terminal')||/run|execut|command|build/.test(summary)?'run':
        icon.includes('search')||/search|find|grep|scan/.test(summary)?'search':
        /edit|write|create|patch/.test(summary)?'edit':'tool';
      const state = /fail|error/.test(summary)?'failed':/running|processing|loading/.test(summary)?'running':'succeeded';
      blocks.push({id:stableId('tl_',msgId+summary.slice(0,32)),type:'tool_call',status:'completed',toolCallId:stableId('tc_',dn.slice(0,64)),toolName,displayName:dn,state,summary});
    });
    // Markdown
    contents.querySelectorAll('.chat-markdown-part.rendered-markdown, .rendered-markdown').forEach(el => {
      if (el.closest('.chat-used-context.chat-thinking-box,.chat-thinking-tool-wrapper')) return;
      const c = textOf(el); if (!c) return;
      const isCode = el.classList.contains('progress-step');
      blocks.push({id:stableId(isCode?'cd_':'tx_',msgId+c.slice(0,48)),type:isCode?'code_block':'text',status:'completed',format:isCode?'plain':'markdown',content:c,...(isCode?{language:'plaintext'}:{})});
    });
    // Fallback
    if (blocks.length===0) {
      const t = textOf(contents)||textOf(row);
      if (t) blocks.push({id:stableId('tx_',t.slice(0,64)),type:'text',status:'completed',format:'markdown',content:t});
    }
    return blocks;
  }

  function extractAll() {
    const list = findList();
    if (list) {
      const rows = getRows(list);
      if (rows.length > 0) {
        return rows.map((row, i) => {
          const role = rowRole(row);
          const mid = stableId('msg_' + role, i + ':' + role);
          const now = new Date().toISOString();
          return { id: mid, role, status: 'completed', createdAt: now, updatedAt: now, blocks: extractBlocks(row, mid), metadata: { domIndex: i } };
        });
      }
    }
    return [];
  }

  function mergeMsgs(messages) {
    const r = [];
    for (const m of messages) {
      if (r.length > 0) {
        const p = r[r.length-1];
        if (p.role === m.role) {
          const pt = p.blocks.map(b => typeof b.content === 'string' ? b.content : '').join('');
          const ct = m.blocks.map(b => typeof b.content === 'string' ? b.content : '').join('');
          if (pt.length > 0 && ct.startsWith(pt)) { r[r.length-1] = { ...p, blocks: m.blocks }; continue; }
        }
      }
      r.push(m);
    }
    return r;
  }

  async function waitForList(retries, delayMs) {
    for (let i = 0; i < retries; i++) {
      const list = findList();
      if (list) return list;
      await new Promise(r => setTimeout(r, delayMs));
    }
    return null;
  }

  async function init() {
    const list = await waitForList(15, 400);
    if (!list) { emit({ kind: 'error', reason: 'list_not_found' }); return; }

    function snap() {
      const msgs = mergeMsgs(extractAll());
      emit({ kind: 'snapshot', messages: msgs });
    }
    snap();
    setInterval(snap, 300);
  }
  init();
})();
''';

  /// Script to send a message in the Copilot input field
  static String sendPrompt(String text, bool submit) => '''
(() => {
  const text = ${JSON.stringify(text)};
  const editor = document.querySelector('.interactive-input-editor');
  if (!editor) return JSON.stringify({ok:false,reason:'no_editor'});
  const textarea = editor.querySelector('textarea');
  if (textarea) {
    textarea.focus();
    const proto = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
    if (proto?.set) { proto.set.call(textarea, text); textarea.dispatchEvent(new Event('input', {bubbles:true})); }
  }
  if ($submit) {
    setTimeout(() => { if(textarea) textarea.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true})); }, 100);
  }
  return JSON.stringify({ok:true});
})();
''';

  /// Script to stop generation
  static String get stopGeneration => '''
(() => {
  const btn = Array.from(document.querySelectorAll('.action-label')).find(el => (el.getAttribute('aria-label')||'').includes('\\u53d6\\u6d88'));
  if (btn instanceof HTMLElement) { btn.click(); return JSON.stringify({ok:true}); }
  return JSON.stringify({ok:false,reason:'cancel_btn_not_found'});
})();
''';

  /// Script for one-shot snapshot (used on connect)
  static String get currentSnapshot => '''
(() => {
  function hash(v) { let h=0; for(let i=0;i<v.length;i++){h=((h<<5)-h)+v.charCodeAt(i);h|=0} return Math.abs(h).toString(36); }
  function stableId(p,v) { return p + '_' + hash(v); }
  function textOf(n) { return (n.textContent||n.innerText||'').replace(/\\u00a0/g,' ').trim(); }

  function findList() {
    const aux = document.getElementById('workbench.parts.auxiliarybar');
    if (!aux) return null;
    const p = aux.querySelector('.interactive-list .monaco-list, .chat-list-at-bottom .monaco-list');
    if (p) return p;
    const lists = Array.from(aux.querySelectorAll('.monaco-list'));
    return lists.find(l => Array.from(l.querySelectorAll('.monaco-list-row')).some(r => /request|response/.test((r.className||'').toLowerCase())))||null;
  }

  function getRows(list) { return Array.from(list.querySelectorAll('.monaco-list-row')).filter(r=>r instanceof HTMLElement); }
  function rowRole(r) { return (r.className||'').toLowerCase().includes('request')?'user':'assistant'; }

  function extractBlocks(row, msgId) {
    const blocks = [];
    const contents = row.querySelector('.monaco-tl-contents')||row;
    if (!contents) { const t=textOf(row); if(t) blocks.push({id:stableId('tx_',t.slice(0,64)),type:'text',status:'completed',format:'markdown',content:t}); return blocks; }
    // Thinking
    contents.querySelectorAll('.chat-used-context.chat-thinking-box').forEach(el => {
      const items = Array.from((el.querySelector('.chat-used-context-list')||el).querySelectorAll('.chat-thinking-item.markdown-content')).filter(i=>!i.closest('.chat-thinking-tool-wrapper')).map(i=>textOf(i)).filter(t=>t&&t!=='\\u601d\\u8003'&&t.toLowerCase()!=='thinking');
      const c = items.join('\\n\\n').trim();
      if (c) blocks.push({id:stableId('th_',msgId+c.slice(0,32)),type:'thinking',status:'completed',format:'plain',content:c,visibility:'collapsed',title:'Thinking'});
    });
    // Tool calls
    contents.querySelectorAll('.chat-thinking-tool-wrapper').forEach(el => {
      const inv = el.querySelector('.chat-tool-invocation-part')||el;
      const dn = inv.querySelector('.chat-used-context-label')?textOf(inv.querySelector('.chat-used-context-label')):'Tool';
      const summary = textOf(inv)||dn;
      if (!summary&&dn==='Tool') return;
      blocks.push({id:stableId('tl_',msgId+summary.slice(0,32)),type:'tool_call',status:'completed',toolCallId:stableId('tc_',dn.slice(0,64)),toolName:'tool',displayName:dn,state:'succeeded',summary});
    });
    // Markdown
    contents.querySelectorAll('.chat-markdown-part.rendered-markdown,.rendered-markdown').forEach(el => {
      if(el.closest('.chat-used-context.chat-thinking-box,.chat-thinking-tool-wrapper')) return;
      const c=textOf(el);if(!c)return;
      blocks.push({id:stableId('tx_',msgId+c.slice(0,48)),type:'text',status:'completed',format:'markdown',content:c});
    });
    if(blocks.length===0){const t=textOf(contents)||textOf(row);if(t)blocks.push({id:stableId('tx_',t.slice(0,64)),type:'text',status:'completed',format:'markdown',content:t});}
    return blocks;
  }

  const list = findList();
  if (!list) return '[]';
  const rows = getRows(list);
  const now = new Date().toISOString();
  const messages = rows.map((row,i) => {
    const role=rowRole(row); const mid=stableId('msg_'+role,i+':'+role);
    return {id:mid,role,status:'completed',createdAt:now,updatedAt:now,blocks:extractBlocks(row,mid),metadata:{domIndex:i}};
  });
  return JSON.stringify(messages);
})();
''';
}
`.trimStart());
');

console.log('ALL DONE - dom_scripts.dart created');
