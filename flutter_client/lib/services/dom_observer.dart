/// DOM observer scripts for Copilot Mirror CDP direct connection.
/// Ported from src/domInjection.ts.

class DomObserver {
  static String buildObserverScript() {
    return r'''
(async () => {
  if (window.__copilotMirrorInstalled) { return { ok: true, reason: 'already_installed' }; }
  window.__copilotMirrorInstalled = true;
  window.__copilotMirrorState = { messageFingerprints: new Map(), blockContent: new Map(), fineMode: true, fineFailCount: 0 };
  function emit(payload) {
    const json = JSON.stringify({ ...payload });
    try { if (typeof window.__copilotMirrorEmit === 'function') { window.__copilotMirrorEmit(json); return; } catch (_) {}
    console.log('[CopilotMirror]' + json);
  }
  function hash(value) { let h = 0; for (let i = 0; i < value.length; i++) { h = ((h << 5) - h) + value.charCodeAt(i); h |= 0; } return Math.abs(h).toString(36); }
  function stableId(p, v) { return p + '_' + hash(v); }
  function textOf(n) { return (n.textContent || n.innerText || '').replace(/\u00a0/g, ').trim(); }
  function cloneTextWithout(node, selectors) { if (!node) return ''; const clone = node.cloneNode(true); for (const s of selectors) { for (const c of Array.from(clone.querySelectorAll(s))) c.remove(); } return textOf(clone); }
  function findList() {
    const aux = document.getElementById('workbench.parts.auxiliarybar');
    if (!aux) return null;
    const p = aux.querySelector('.interactive-list .monaco-list, .chat-list-at-bottom .monaco-list, [class*="interactive-list"] .monaco-list');
    if (p) return p;
    return Array.from(aux.querySelectorAll('.monaco-list')).find(l => { const r = Array.from(l.querySelectorAll('.monaco-list-row')); return r.some(r => /request|response/.test((r.className||'').toLowerCase())); }) || null;
  }
  function getRows(list) { return Array.from(list.querySelectorAll('.monaco-list-row')).filter(r => r instanceof HTMLElement); }
  function rowRole(r) { return (r.className||'').toLowerCase().includes('request') ? 'user' : 'assistant'; }
  function extractThinkingParts(el) {
    const body = el.querySelector('.chat-used-context-list') || el;
    return Array.from(body.querySelectorAll('.chat-thinking-item.markdown-content')).filter(i => !i.closest('.chat-thinking-tool-wrapper')).map(i => textOf(i)).filter(t => t && t !== '\u601d\u8003' && t.toLowerCase() !== 'thinking');
  }
  function extractThinkingText(el) { return extractThinkingParts(el).join(String.fromCharCode(10)+String.fromCharCode(10)).trim(); }
  function normalizeWords(text) { return ' + text.toLowerCase().replace(/[^a-z\u4e00-\u9fff]+/g, ').trim() + '; }
  function containsWord(text, needles) { const n = normalizeWords(text); return needles.some(nn => n.includes(' ' + nn + ')); }
  function inferToolName(ic, dn, sm) {
    const t = (ic+' '+dn+' '+sm).toLowerCase();
    if (ic.includes('codicon-terminal')||containsWord(t,['run','running','execute','executed','command','terminal','build','open','switch','\u6267\u884c','\u8fd0\u884c'])) return 'run';
    if (ic.includes('codicon-search')||containsWord(t,['search','searched','find','found','grep','scan','scanned','lookup','\u641c\u7d22','\u67e5\u627e'])) return 'search';
    if (/codicon-(checklist|files|file|book|list-tree)/.test(ic)||containsWord(t,['review','reviewed','read','checked','check','inspect','inspected','\u8bfb\u53d6','\u68c0\u67e5','\u5ba1\u67e5'])) return 'read';
    if (/codicon-(edit|pencil|save)/.test(ic)||containsWord(t,['edit','edited','write','wrote','apply','applied','patch','patched','create','created','\u7f16\u8f91','\u4fee\u6539','\u521b\u5efa'])) return 'edit';
    return 'tool';
  }
  function extractToolDescriptor(el) {
    const ic = (el.querySelector('.chat-thinking-icon')?.className||'');
    const inv = el.querySelector('.chat-tool-invocation-part')||el;
    const ln = inv.querySelector('.chat-used-context-label [aria-label],.chat-used-context-label .monaco-button-label,.chat-used-context-label .monaco-button-mdlabel,.chat-used-context-label,[aria-label]');
    const al = ln instanceof Element ? (ln.getAttribute('aria-label')||'').trim() : '';
    const lt = ln ? textOf(ln) : '';
    const dn = al||lt||cloneTextWithout(inv,['.chat-thinking-icon','.codicon','svg'])||cloneTextWithout(el,['.chat-thinking-icon','.codicon','svg'])||'Tool';
    const sm = cloneTextWithout(inv,['.chat-used-context-label','.chat-thinking-icon','.codicon','svg','style','script','.xterm','.xterm-viewport','.xterm-screen','.xterm-helpers','.xterm-decoration-container','.xterm-accessibility'])||cloneTextWithout(el,['.chat-used-context-label','.chat-thinking-icon','.codicon','svg','style','script','.xterm','.xterm-viewport','.xterm-screen','.xterm-helpers','.xterm-decoration-container','.xterm-accessibility'])||dn;
    if ((!sm||sm==='Tool')&&(!dn||dn==='Tool')) return null;
    const tn = inferToolName(ic,dn,sm);
    const st = /failed|error|\u9519\u8bef|\u5931\u8d25/.test((dn+' '+sm).toLowerCase()) ? 'failed' : (/running|\u6b63\u5728\u8fd0\u884c|processing|\u6b63\u5728\u5904\u7406|loading|\u52a0\u8f7d/.test((dn+' '+sm).toLowerCase()) ? 'running' : 'succeeded');
    return { toolName: tn, displayName: dn, summary: sm, state: st };
  }
  function extractBlocks(row, msgId) {
    const blocks = [];
    const hfs = row.querySelector('.chat-markdown-part,.chat-used-context,.rendered-markdown,.chat-thinking');
    const contents = hfs ? row.querySelector('.monaco-tl-contents') : row;
    if (!contents&&!hfs) { const t=textOf(row); if(t) blocks.push({id:stableId('tx_',t.slice(0,64)),type:'text',status:'completed',format:'markdown',content:t,_fallback:true}); return blocks; }
    if (!contents) { const t=textOf(row); if(t) blocks.push({id:stableId('t_',t.slice(0,64)),type:'text',status:'completed',format:'markdown',content:t}); return blocks; }
    let sc = 0;
    for (const el of Array.from(contents.querySelectorAll('.chat-used-context.chat-thinking-box'))) {
      const title = el.querySelector('.chat-thinking-title-detail-text');
      const tt = title ? textOf(title) : '';
      const c = extractThinkingText(el);
      if (c) { blocks.push({id:stableId('th_',msgId+c.slice(0,32)),type:'thinking',status:'completed',format:'plain',content:c,visibility:'collapsed',title:tt||'Thinking'}); sc++; }
    }
    for (const el of Array.from(contents.querySelectorAll('.chat-thinking-tool-wrapper'))) {
      const tool = extractToolDescriptor(el);
      if (tool&&(tool.summary||tool.displayName)) { blocks.push({id:stableId('tl_',msgId+tool.summary.slice(0,32)),type:'tool_call',status:'completed',toolCallId:stableId('tc_',tool.displayName.slice(0,64)),toolName:tool.toolName,displayName:tool.displayName,state:tool.state,summary:tool.summary}); sc++; }
    }
    for (const el of Array.from(contents.querySelectorAll('.chat-markdown-part.rendered-markdown,.rendered-markdown'))) {
      if (el.closest('.chat-used-context.chat-thinking-box,.chat-thinking-tool-wrapper')) continue;
      const c = textOf(el); if (!c) continue;
      const isCode = el.classList.contains('progress-step');
      blocks.push({id:stableId(isCode?'cd_':'tx_',msgId+c.slice(0,48)),type:isCode?'code_block':'text',status:'completed',format:isCode?'plain':'markdown',content:c,...(isCode?{language:'plaintext'}:{})});
      sc++;
    }
    if (sc===0) { window.__copilotMirrorState.fineFailCount=(window.__copilotMirrorState.fineFailCount||0)+1; if (window.__copilotMirrorState.fineFailCount>=3&&window.__copilotMirrorState.fineMode) { window.__copilotMirrorState.fineMode=false; emit({kind:'heartbeat',_fallback:'fine_parsing_failed_switching_to_full_text'}); } }
    if (blocks.length===0) { const t=textOf(contents)||textOf(row); if(t) blocks.push({id:stableId('tx_',t.slice(0,64)),type:'text',status:'completed',format:'markdown',content:t,_fallback:true}); }
    return blocks;
  }
  function extractAll() {
    const list = findList();
    if (list) {
      const rows = getRows(list);
      if (rows.length>0) return rows.map((row,i)=>{const role=rowRole(row);const mid=stableId('msg_'+role,i+':'+role);const now=new Date().toISOString();return {id:mid,role,status:'completed',createdAt:now,updatedAt:now,blocks:extractBlocks(row,mid),metadata:{domIndex:i}};});
    }
    return [];
  }
  function mergeIncrementalMessages(msgs) {
    const r = [];
    for (const m of msgs) { if (r.length>0) { const p=r[r.length-1]; if (p.role===m.role) { const pt=p.blocks.map(b=>typeof b.content==='string'?b.content:'').join(''); const ct=m.blocks.map(b=>typeof b.content==='string'?b.content:'').join(''); if (pt.length>0&&ct.startsWith(pt)) { r[r.length-1]={...p,blocks:m.blocks}; continue; } r.push(m); }
    return r;
  }
  async function waitForList(retries=15,delayMs=400) { for (let i=0;i<retries;i++) { const l=findList(); if (l) return l; await new Promise(r=>setTimeout(r,delayMs)); } return null; }
  const list = await waitForList();
  if (!list) return { ok: false, reason: 'monaco_list_not_found' };
  function emitSnapshot() {
    const messages = mergeIncrementalMessages(extractAll());
    emit({kind:'snapshot',messages});
    const fp = window.__copilotMirrorState.messageFingerprints;
    for (const m of messages) { for (const b of m.blocks) { if (typeof b.content==='string') window.__copilotMirrorState.blockContent.set(b.id,b.content); } if (!fp.has(m.id)) fp.set(m.id,true); }
  }
  emitSnapshot();
  setInterval(()=>{emitSnapshot();},300);
  return { ok: true };
})();
''';
  }

  static String buildSnapshotScript() {
    return r'''
(() => {
  try {
    function hash(v) { let h=0; for(let i=0;i<v.length;i++){h=((h<<5)-h)+v.charCodeAt(i);h|=0;} return Math.abs(h).toString(36); }
    function stableId(p,v) { return p+'_'+hash(v); }
    function textOf(n) { return (n?.textContent||n?.innerText||'').replace(/\u00a0/g,' ').trim(); }
    function cloneTextWithout(n,s) { if(!n) return ''; const c=n.cloneNode(true); for(const x of s) for(const ch of Array.from(c.querySelectorAll(x))) ch.remove(); return textOf(c); }
    function normalizeWords(t) { return ' '+t.toLowerCase().replace(/[^a-z\u4e00-\u9fff]+/g,' ').trim()+' '; }
    function containsWord(t,ndls) { const n=normalizeWords(t); return ndls.some(x=>n.includes(' '+x+' ')); }
    function inferToolName(ic,dn,sm) {
      const t=(ic+' '+dn+' '+sm).toLowerCase();
      if(ic.includes('codicon-terminal')||containsWord(t,['run','running','execute','executed','command','terminal','build','open','switch'])) return 'run';
      if(ic.includes('codicon-search')||containsWord(t,['search','searched','find','found','grep','scan','scanned','lookup'])) return 'search';
      if(/codicon-(checklist|files|file|book|list-tree)/.test(ic)||containsWord(t,['review','reviewed','read','checked','check','inspect','inspected'])) return 'read';
      if(/codicon-(edit|pencil|save)/.test(ic)||containsWord(t,['edit','edited','write','wrote','apply','applied','patch','patched','create','created'])) return 'edit';
      return 'tool';
    }
    function extractToolDescriptor(el) {
      const ic=(el.querySelector('.chat-thinking-icon')?.className||'');
      const inv=el.querySelector('.chat-tool-invocation-part')||el;
      const ln=inv.querySelector('.chat-used-context-label [aria-label],.chat-used-context-label .monaco-button-label,.chat-used-context-label .monaco-button-mdlabel,.chat-used-context-label,[aria-label]');
      const al=ln instanceof Element?(ln.getAttribute('aria-label')||'').trim():'';
      const lt=ln?textOf(ln):'';
      const dn=al||lt||cloneTextWithout(inv,['.chat-thinking-icon','.codicon','svg'])||cloneTextWithout(el,['.chat-thinking-icon','.codicon','svg'])||'Tool';
      const sm=cloneTextWithout(inv,['.chat-used-context-label','.chat-thinking-icon','.codicon','svg','style','script','.xterm','.xterm-viewport','.xterm-screen','.xterm-helpers','.xterm-decoration-container','.xterm-accessibility'])||cloneTextWithout(el,['.chat-used-context-label','.chat-thinking-icon','.codicon','svg','style','script','.xterm','.xterm-viewport','.xterm-screen','.xterm-helpers','.xterm-decoration-container','.xterm-accessibility'])||dn;
      if((!sm||sm==='Tool')&&(!dn||dn==='Tool')) return null;
      const tn=inferToolName(ic,dn,sm);
      const st=/failed|error/.test((dn+' '+sm).toLowerCase())?'failed':(/running|processing|loading/.test((dn+' '+sm).toLowerCase())?'running':'succeeded');
      return {toolName:tn,displayName:dn,summary:sm,state:st};
    }
    function extractBlocks(row,mid) {
      const blocks=[];
      const hfs=row.querySelector('.chat-markdown-part,.chat-used-context,.rendered-markdown,.chat-thinking');
      const contents=hfs?row.querySelector('.monaco-tl-contents'):row;
      if(!contents&&!hfs){const t=textOf(row);if(t)blocks.push({id:stableId('tx_',t.slice(0,64)),type:'text',status:'completed',format:'markdown',content:t});return blocks;}
      if(!contents){const t=textOf(row);if(t)blocks.push({id:stableId('tx_',t.slice(0,64)),type:'text',status:'completed',format:'markdown',content:t});return blocks;}
      for(const el of Array.from(contents.querySelectorAll('.chat-used-context.chat-thinking-box'))){
        const title=el.querySelector('.chat-thinking-title-detail-text');
        const tt=title?textOf(title):'';
        const c=(()=>{const parts=Array.from((el.querySelector('.chat-used-context-list')||el).querySelectorAll('.chat-thinking-item.markdown-content')).filter(i=>!i.closest('.chat-thinking-tool-wrapper')).map(i=>textOf(i)).filter(t=>t&&t!=='\u601d\u8003'&&t.toLowerCase()!=='thinking');return parts.join(String.fromCharCode(10)+String.fromCharCode(10)).trim();})();
        if(c)blocks.push({id:stableId('th_',mid+c.slice(0,32)),type:'thinking',status:'completed',format:'plain',content:c,visibility:'collapsed',title:tt||'Thinking'});
      }
      for(const el of Array.from(contents.querySelectorAll('.chat-thinking-tool-wrapper'))){
        const tool=extractToolDescriptor(el);
        if(tool&&(tool.summary||tool.displayName))blocks.push({id:stableId('tl_',mid+tool.summary.slice(0,32)),type:'tool_call',status:'completed',toolCallId:stableId('tc_',tool.displayName.slice(0,64)),toolName:tool.toolName,displayName:tool.displayName,state:tool.state,summary:tool.summary});
      }
      for(const el of Array.from(contents.querySelectorAll('.chat-markdown-part.rendered-markdown,.rendered-markdown'))){
        if(el.closest('.chat-used-context.chat-thinking-box,.chat-thinking-tool-wrapper')) continue;
        const c=textOf(el); if(!c) continue;
        const isCode=el.classList.contains('progress-step');
        blocks.push({id:stableId(isCode?'cd_':'tx_',mid+c.slice(0,48)),type:isCode?'code_block':'text',status:'completed',format:isCode?'plain':'markdown',content:c,...(isCode?{language:'plaintext'}:{})});
      }
      if(blocks.length===0){const t=textOf(contents);if(t)blocks.push({id:stableId('tx_',t.slice(0,64)),type:'text',status:'completed',format:'markdown',content:t});}
      return blocks;
    }
    function findList(){
      const aux=document.getElementById('workbench.parts.auxiliarybar');
      if(!aux) return null;
      const p=aux.querySelector('.interactive-list .monaco-list,.chat-list-at-bottom .monaco-list,[class*="interactive-list"] .monaco-list');
      if(p) return p;
      return Array.from(aux.querySelectorAll('.monaco-list')).find(l=>Array.from(l.querySelectorAll('.monaco-list-row')).some(r=>/request|response/.test((r.className||'').toLowerCase())))||null;
    }
    const list=findList(); if(!list) return JSON.stringify({ok:false,reason:'chat_list_not_found'});
    const now=new Date().toISOString();
    let messages=Array.from(list.querySelectorAll('.monaco-list-row')).filter(r=>r instanceof HTMLElement).map((row,i)=>{const role=(row.className||'').toLowerCase().includes('request')?'user':'assistant';const mid=stableId('msg_'+role,i+':'+role);return {id:mid,role,status:'completed',createdAt:now,updatedAt:now,blocks:extractBlocks(row,mid),metadata:{domIndex:i,source:'snapshot_script'}};});
    const merged=[];
    for(const m of messages){if(merged.length>0){const p=merged[merged.length-1];if(p.role===m.role){const pt=p.blocks.map(b=>typeof b.content==='string'?b.content:'').join('');const ct=m.blocks.map(b=>typeof b.content==='string'?b.content:'').join('');if(pt.length>0&&ct.startsWith(pt)){merged[merged.length-1]={...p,blocks:m.blocks};continue;}}}merged.push(m);}
    messages=merged;
    return JSON.stringify({ok:true,result:{messages}});
  } catch(e) {
    return JSON.stringify({ok:false,reason:e instanceof Error?e.message:String(e)});
  }
})();
''';
  }

  static String buildSendPromptScript(String text, bool submit) {
    final escaped = text.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', '\\n').replaceAll('\r', '\\r');
    final t = "'$escaped'";
    final s = submit ? 'true' : 'false';
    return '''
(() => {
  const text = $t;
  const editor = document.querySelector('.interactive-input-editor');
  if (editor) {
    const ta = editor.querySelector('textarea');
    if (ta) ta.focus();
    if (ta) {
      const p = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
      if (p?.set) { p.set.call(ta, text); ta.dispatchEvent(new Event('input', { bubbles: true })); }
    }
    if ($s) {
      setTimeout(() => { if (ta) ta.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true })); }, 100);
    }
    return JSON.stringify({ ok: true });
  }
  for (const ta of document.querySelectorAll('textarea')) {
    if (ta.offsetParent === null || ta.className === 'ime-text-area' || ta.className === 'xterm-helper-textarea') continue;
    ta.focus();
    const p = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
    if (p?.set) { p.set.call(ta, text); ta.dispatchEvent(new Event('input', { bubbles: true })); }
    if ($s) { ta.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true })); }
    return JSON.stringify({ ok: true });
  }
  return JSON.stringify({ ok: false, reason: 'input_not_found' });
})();
''';
  }

  static String buildStopGenerationScript() => r'''
(() => {
  // Strategy 1: find the working chat input container and look for stop/cancel action
  const container = document.querySelector('.chat-input-container.working');
  if (container) {
    const actions = container.querySelectorAll('a.action-label, button, [role="button"], .monaco-button, .action-label');
    for (const el of actions) {
      if (el instanceof HTMLElement && el.offsetParent !== null) {
        const label = (el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent || '').toLowerCase();
        if (/stop|cancel|取消/.test(label) || el.querySelector('.codicon-stop, .codicon-stop-circle')) {
          el.click();
          return JSON.stringify({ ok: true, selector: 'working_container_action' });
        }
      }
    }
  }
  // Strategy 2: broad selectors covering all common VS Code stop button variants
  const sel = [
    'button[aria-label*="stop" i]', 'button[aria-label*="cancel" i]',
    'button[title*="stop" i]', 'button[title*="cancel" i]',
    'a[aria-label*="取消" i]', 'a[aria-label*="stop" i]', 'a[aria-label*="cancel" i]',
    'a[title*="stop" i]', 'a[title*="cancel" i]',
    '[role="button"][aria-label*="stop" i]', '[role="button"][aria-label*="cancel" i]',
    '[role="button"][title*="stop" i]', '[role="button"][title*="cancel" i]',
    '.action-label[aria-label*="stop" i]', '.action-label[aria-label*="cancel" i]',
    '.action-label[title*="stop" i]', '.action-label[title*="cancel" i]',
    '.monaco-button[aria-label*="stop" i]', '.monaco-button[aria-label*="cancel" i]',
    '.chat-stop-button', '.codicon-stop', '.codicon-stop-circle',
    '[aria-label*="Stop Generation"]'
  ];
  for (const s of sel) {
    const els = document.querySelectorAll(s);
    for (const el of els) {
      if (el instanceof HTMLElement && el.offsetParent !== null) {
        el.click();
        return JSON.stringify({ ok: true, selector: s });
      }
    }
  }
  return JSON.stringify({ ok: false, reason: 'stop_button_not_found' });
})();
''';

  static String buildSessionListScript() => r'''
(() => {
  try {
    const n = v => (v||'').replace(/\u00a0/g,' ').replace(/\s+/g,' ').trim();
    const viewer = document.querySelector('[class*="agent-sessions-viewer"]');
    if (!viewer) return JSON.stringify({ ok: false, reason: 'no_session_viewer' });
    const sl = Array.from(viewer.querySelectorAll('.monaco-list')).find(l => {
      const a = n(l.getAttribute('aria-label'));
      if (/agent sessions/i.test(a)) return true;
      return Array.from(l.querySelectorAll('.monaco-list-row')).some(r => r.querySelector('.monaco-highlighted-label'));
    });
    if (!sl) return JSON.stringify({ ok: false, reason: 'no_session_list' });
    const rows = Array.from(sl.querySelectorAll('.monaco-list-row'));
    const sessions = []; let vi = 0; let asid;
    rows.forEach((row, di) => {
      const title = n(row.querySelector('.monaco-highlighted-label')?.textContent || row.querySelector('.label-name')?.textContent);
      if (!title) return;
      const active = row.getAttribute('aria-selected')==='true' || row.classList.contains('selected') || row.classList.contains('focused');
      sessions.push({ sessionId: 'session_'+di+'_'+title.replace(/[^a-zA-Z0-9\u4e00-\u9fff]/g,'_').slice(0,32), title, index: vi, active, source: 'dom' });
      if (active) asid = sessions[sessions.length-1].sessionId;
      vi++;
    });
    if (!asid) {
      for (const s of sessions) s.active = false;
      const at = n(document.querySelector('.action-label.chat-view-title-label-container')?.textContent||'');
      if (at) { const f = sessions.find(s => n(s.title) === at); if (f) { f.active = true; asid = f.sessionId; } }
    }
    return JSON.stringify({ ok: true, result: { sessions, activeSessionId: asid } });
  } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); }
})();
''';

  static String buildGetActiveSessionScript() => r'''
(() => { try { const el = document.querySelector('.action-label.chat-view-title-label-container'); if (el) return JSON.stringify({ ok: true, title: (el.textContent||'').trim() }); return JSON.stringify({ ok: false, reason: 'no_active_session_title' }); } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); } })();
''';

  static String buildSwitchSessionScript(int index) => '''
(() => {
  try {
    const sl = Array.from(document.querySelectorAll('.monaco-list')).find(l => l.closest('[class*="agent-sessions-viewer"]'));
    if (!sl) return JSON.stringify({ ok: false, reason: 'no_session_list' });
    const rows = Array.from(sl.querySelectorAll('.monaco-list-row')).filter(row => { const t = (row.querySelector('.monaco-highlighted-label')?.textContent||'').trim(); return t != ''; });
    const tr = rows[$index];
    if (!tr) return JSON.stringify({ ok: false, reason: 'session_index_out_of_range', index: $index, count: rows.length });
    if (tr instanceof HTMLElement) { tr.click(); const inner = tr.querySelector('[role="button"], .monaco-highlighted-label'); if (inner instanceof HTMLElement) inner.click(); return JSON.stringify({ ok: true, title: (tr.querySelector('.monaco-highlighted-label')?.textContent||'').trim() }); }
    return JSON.stringify({ ok: false, reason: 'row_not_clickable' });
  } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); }
})();
''';

  static String buildNewSessionScript() => r'''
(() => {
  try {
    const btn = document.querySelector('a.monaco-button.secondary');
    if (btn && (btn.textContent||'').trim().includes('\u65b0\u5efa')) { if (btn instanceof HTMLElement) { btn.click(); return JSON.stringify({ ok: true }); } }
    for (const el of Array.from(document.querySelectorAll('a, button, [role="button"]'))) {
      const t = (el.textContent||'').trim().toLowerCase();
      if (t.includes('new')||t.includes('\u65b0\u5efa')) { if (el instanceof HTMLElement) { el.click(); return JSON.stringify({ ok: true, source: 'broad_fallback' }); } }
    }
    return JSON.stringify({ ok: false, reason: 'new_session_button_not_found' });
  } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); }
})();
''';

  static String buildOpenSessionSidebarScript() => r'''
(() => {
  try {
    const ex = document.querySelector('[class*="agent-sessions-viewer"]');
    if (ex instanceof HTMLElement && ex.getBoundingClientRect().width > 24 && ex.getBoundingClientRect().height > 24) return JSON.stringify({ ok: true, action: 'already_open' });
    const toggle = Array.from(document.querySelectorAll('button, [role="button"], a, .action-label')).find(el => {
      if (!(el instanceof HTMLElement)) return false;
      return /agent.sessions/.test((el.getAttribute('aria-label')||'').trim().toLowerCase()) || (el.textContent||'').trim().toLowerCase().includes('agent');
    });
    if (!(toggle instanceof HTMLElement)) return JSON.stringify({ ok: false, reason: 'no_session_sidebar_toggle' });
    toggle.click(); toggle.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }));
    return JSON.stringify({ ok: true, action: 'opened_sidebar' });
  } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); }
})();
''';

  static String buildAgentListScript() => r'''
(() => {
  try {
    function hasAgentMenu() {
      return Array.from(document.querySelectorAll('.context-view .monaco-list')).some(l => {
        if (l.getAttribute('role') !== 'menu') return false;
        return Array.from(l.querySelectorAll('.monaco-list-row')).some(r => /^(Agent|Ask|Plan)$/i.test((r.getAttribute('aria-label')||'').trim().split(/[,，]/)[0]||''));
      });
    }
    if (hasAgentMenu()) return JSON.stringify({ ok: true, action: 'already_open' });
    const lb = document.querySelector('li.chat-input-picker-item.chat-mode-picker-item .dropdown-label');
    const ab = document.querySelector('li.chat-input-picker-item.chat-mode-picker-item a.action-label[aria-label*="agent" i]');
    const db = document.querySelector('li.chat-input-picker-item.chat-mode-picker-item .monaco-dropdown');
    const qi = document.querySelector('.quick-input-widget:not([aria-hidden="true"])');
    if (qi) document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
    const attempts = [
      () => { if (lb instanceof HTMLElement) lb.click(); },
      () => { if (ab instanceof HTMLElement) { ab.dispatchEvent(new MouseEvent('mousedown', {bubbles:true,cancelable:true,button:0,buttons:1})); ab.click(); ab.dispatchEvent(new MouseEvent('mouseup', {bubbles:true,cancelable:true,button:0,buttons:0})); } },
      () => { if (db instanceof HTMLElement) db.click(); }
    ];
    return new Promise(resolve => {
      let i = 0;
      const next = () => { if (hasAgentMenu()) { resolve(JSON.stringify({ok:true,action:'opened_picker'})); return; } const a = attempts[i++]; if (!a) { resolve(JSON.stringify({ok:false,reason:'agent_menu_not_opened'})); return; } a(); setTimeout(next, 180); };
      setTimeout(next, 50);
    });
  } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); }
})();
''';

  static String buildScanAgentListScript() => r'''
(() => {
  try {
    function n(t) { return (t||'').replace(/\s+/g,' ').trim(); }
    function can(t) { const c=(t||'').replace(/\s+/g,'').toLowerCase(); if(c==='agent'||c==='\u667a\u80fd\u4f53') return 'Agent'; if(c==='ask') return 'Ask'; if(c==='plan') return 'Plan'; return n(t); }
    function isAR(r) { return /^(Agent|Ask|Plan)$/i.test(can((r.getAttribute('aria-label')||'').split(/[,，]/)[0]||r.textContent||'')); }
    function parseRows(rows, src) {
      const agents = rows.map((r,i)=>{
        const rawN=n(r.textContent||''); const rawA=n(r.getAttribute('aria-label')||'');
        const label=can(rawA.split(/[,，]/)[0]||'')||can(rawN.split(/[,，]/)[0]||rawN);
        const desc=n(rawN.slice(label.length)); const active=r.classList.contains('focused')||r.classList.contains('selected')||r.getAttribute('aria-selected')==='true';
        return {id:label.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]+/g,'_')||('agent_'+i),name:label,description:desc,index:i,active,source:src};
      }).filter(a => a.name);
      const aa = agents.find(a=>a.active);
      if (aa) window.__copilotMirrorLastActiveAgent = {id:aa.id,name:aa.name};
      return { agents, activeAgentId: aa ? aa.id : (window.__copilotMirrorLastActiveAgent?.id) };
    }
    const cl = Array.from(document.querySelectorAll('.context-view .monaco-list')).find(l => l.getAttribute('role')==='menu' && Array.from(l.querySelectorAll('.monaco-list-row')).some(r=>isAR(r)));
    if (cl) { const rows = Array.from(cl.querySelectorAll('.monaco-list-row')).filter(r=>r.classList.contains('action')); return JSON.stringify({ok:true,result:parseRows(rows,'context_view')}); }
    const qi = document.querySelector('.quick-input-widget:not([aria-hidden="true"])');
    if (!qi) return JSON.stringify({ ok: false, reason: 'no_agent_picker_overlay' });
    const list = qi.querySelector('.monaco-list');
    if (!list) return JSON.stringify({ ok: false, reason: 'no_list_in_picker' });
    const rows = Array.from(list.querySelectorAll('.monaco-list-row')).filter(r=>isAR(r));
    if (rows.length===0) return JSON.stringify({ ok: false, reason: 'no_agent_rows_in_quick_input' });
    return JSON.stringify({ ok: true, result: parseRows(rows, 'quick_input') });
  } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); }
})();
''';

  static String buildSwitchAgentScript(int index) => '''
(() => {
  try {
    function n(t) { return (t||'').replace(/\\s+/g,' ').trim(); }
    function can(t) { const c=(t||'').replace(/\\s+/g,'').toLowerCase(); if(c==='agent'||c==='\\u667a\\u80fd\\u4f53') return 'Agent'; if(c==='ask') return 'Ask'; if(c==='plan') return 'Plan'; return n(t); }
    function isAR(r) { return /^(Agent|Ask|Plan)\$/i.test(can((r.getAttribute('aria-label')||'').split(/[,，]/)[0]||r.textContent||'')); }
    function getRows() {
      const cl = Array.from(document.querySelectorAll('.context-view .monaco-list')).find(l => l.getAttribute('role')==='menu' && Array.from(l.querySelectorAll('.monaco-list-row')).some(r=>isAR(r)));
      if (cl) return Array.from(cl.querySelectorAll('.monaco-list-row')).filter(r=>{return r.classList.contains('action')&&isAR(r);});
      const qi = document.querySelector('.quick-input-widget:not([aria-hidden="true"])');
      if (!qi) return null; const list = qi.querySelector('.monaco-list'); if (!list) return null;
      return Array.from(list.querySelectorAll('.monaco-list-row'));
    }
    const rows = getRows();
    if (!rows) return JSON.stringify({ ok: false, reason: 'no_agent_picker_overlay' });
    const target = rows[$index];
    if (!target) return JSON.stringify({ ok: false, reason: 'index_out_of_range', count: rows.length });
    if (target instanceof HTMLElement) {
      const label = can(((target.getAttribute('aria-label')||'').split(/[,，]/)[0]||'').trim())||can(target.textContent||'');
      const id = label.toLowerCase().replace(/[^a-z0-9\\u4e00-\\u9fff]+/g,'_')||'agent_$index';
      window.__copilotMirrorLastActiveAgent = {id,name:label};
      target.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true,button:0,buttons:1}));
      target.click();
      target.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,cancelable:true,button:0,buttons:0}));
      return JSON.stringify({ok:true,result:{id,name:label}});
    }
    return JSON.stringify({ ok: false, reason: 'target_not_clickable' });
  } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); }
})();
''';

  static String buildScanSuggestWidgetScript() => r'''
(() => {
  try {
    const sw = document.querySelector('.suggest-widget:not([aria-hidden="true"]), .editor-widget:not([aria-hidden="true"])');
    const list = sw ? sw.querySelector('.monaco-list') : null;
    if (!list) {
      const cv = document.querySelector('.context-view.visible');
      if (cv) {
        const items = Array.from(cv.querySelectorAll('[role="option"], .monaco-list-row'));
        if (items.length > 0) {
          const cmds = items.map((el,i) => ({ id: el.id||'slash_'+i, label: (el.querySelector('.monaco-highlighted-label')?.textContent||el.textContent||'').trim().split('\n')[0], title: el.getAttribute('aria-label')||'', description: el.querySelector('.monaco-icon-label-description')?.textContent?.trim()||'', index: i, source: 'dom' }));
          return JSON.stringify({ ok: true, result: { items: cmds } });
        }
      }
      return JSON.stringify({ ok: false, reason: 'no_suggest_widget' });
    }
    const rows = Array.from(list.querySelectorAll('.monaco-list-row'));
    const cmds = rows.map((row,i) => ({ id: row.id||'slash_'+i, label: (row.querySelector('.monaco-highlighted-label')?.textContent||row.textContent||'').trim().split('\n')[0], title: row.getAttribute('aria-label')||'', description: row.querySelector('.monaco-icon-label-description')?.textContent?.trim()||'', index: i, source: 'dom' }));
    return JSON.stringify({ ok: true, result: { items: cmds } });
  } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); }
})();
''';

  static String buildRestoreInputScript() => r'''
(() => {
  try {
    const cc = document.querySelector('.chat-controls-container');
    const ta = cc ? (cc.querySelector('textarea.inputarea')||cc.querySelector('textarea')) : null;
    if (!ta) return JSON.stringify({ ok: false, reason: 'no_textarea' });
    const p = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
    if (p?.set) { p.set.call(ta, ''); ta.dispatchEvent(new Event('input', { bubbles: true })); }
    return JSON.stringify({ ok: true });
  } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); }
})();
''';

  static String buildSlashListScript(String? query) {
    final q = query ?? '';
    return '''
(() => {
  try {
    const cc = document.querySelector('.chat-controls-container');
    if (!cc) return JSON.stringify({ ok: false, reason: 'no_chat_controls' });
    const ta = cc.querySelector('textarea.inputarea')||cc.querySelector('textarea');
    if (!ta) return JSON.stringify({ ok: false, reason: 'no_textarea' });
    const prefix = '/$q';
    const p = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
    if (!p?.set) return JSON.stringify({ ok: false, reason: 'no_value_setter' });
    p.set.call(ta, prefix);
    ta.selectionStart = prefix.length; ta.selectionEnd = prefix.length;
    ta.dispatchEvent(new InputEvent('input', { data: prefix, inputType: 'insertText', bubbles: true }));
    return JSON.stringify({ ok: true, action: 'wait_for_suggest', prefix });
  } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); }
})();
''';
  }

  static String buildApplySlashScript(int index, bool insertOnly) => '''
(() => {
  try {
    if (${insertOnly ? 'true' : 'false'}) return JSON.stringify({ ok: true, action: 'inserted' });
    const sw = document.querySelector('.suggest-widget:not([aria-hidden="true"]), .editor-widget:not([aria-hidden="true"])');
    const list = sw ? sw.querySelector('.monaco-list') : null;
    if (!list) return JSON.stringify({ ok: false, reason: 'no_suggest_widget' });
    const rows = Array.from(list.querySelectorAll('.monaco-list-row'));
    const target = rows[$index];
    if (!target) return JSON.stringify({ ok: false, reason: 'index_out_of_range', count: rows.length });
    if (target instanceof HTMLElement) { target.click(); target.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 })); }
    return JSON.stringify({ ok: true });
  } catch(e) { return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) }); }
})();
''';

}