/*---------------------------------------------------------------------------------------------
 *  Copilot Mirror – DOM Injection Script Builder (Phase 2)
 *  Architecture: nodejs-cdp-bridge.md
 *
 *  UPDATE 2026-05: VS Code Insiders renders Copilot Chat natively in the workbench DOM
 *  (auxiliarybar → agent-sessions-container → monaco-list), NOT in a webview.
 *  All selectors are based on CDP live probe results.
 *--------------------------------------------------------------------------------------------*/

import type { BridgeOptions } from './protocol.js';

/**
 * Build observer script for native VS Code Copilot Chat view.
 *
 * DOM hierarchy (right sidebar):
 *   #workbench.parts.auxiliarybar
 *     → .pane-body.chat-viewpane
 *       → .agent-sessions-container[3]
 *         → .monaco-list
 *           → .monaco-list-row.request / .response
 *             → .monaco-tl-contents
 *               → .chat-markdown-part.rendered-markdown  (text)
 *               → .chat-used-context.chat-thinking-box    (thinking)
 *               → .chat-thinking-tool-wrapper             (tool call)
 *               → .rendered-markdown                      (code steps)
 */
export function buildObserverScript(options: BridgeOptions): string {
	return `
(async () => {
	if (window.__copilotMirrorInstalled) { return { ok: true, reason: 'already_installed' }; }

	const SESSION_ID = ${JSON.stringify(options.sessionId)};

	window.__copilotMirrorInstalled = true;
	window.__copilotMirrorState = { messageFingerprints: new Map(), blockContent: new Map(), fineMode: true, fineFailCount: 0 };

	function emit(payload) {
		const json = JSON.stringify({ sessionId: SESSION_ID, ...payload });
		try { if (typeof window.__copilotMirrorEmit === 'function') { window.__copilotMirrorEmit(json); return; } } catch (_) {}
		console.log('[CopilotMirror]' + json);
	}

	function hash(value) {
		let h = 0;
		for (let i = 0; i < value.length; i++) { h = ((h << 5) - h) + value.charCodeAt(i); h |= 0; }
		return Math.abs(h).toString(36);
	}
	function stableId(p, v) { return p + '_' + hash(v); }
	function textOf(n) { return (n.textContent || n.innerText || '').replace(/\\u00a0/g, ' ').trim(); }
	function cloneTextWithout(node, selectors) {
		if (!node) return '';
		const clone = node.cloneNode(true);
		for (const selector of selectors) {
			for (const child of Array.from(clone.querySelectorAll(selector))) child.remove();
		}
		return textOf(clone);
	}

	/* ── Find chat panel root ── */
	function findList() {
		const aux = document.getElementById('workbench.parts.auxiliarybar');
		if (!aux) return null;

		// Prefer the actual chat message list, not the agent sessions sidebar list.
		const preferred = aux.querySelector('.interactive-list .monaco-list, .chat-list-at-bottom .monaco-list, [class*="interactive-list"] .monaco-list');
		if (preferred) return preferred;

		const lists = Array.from(aux.querySelectorAll('.monaco-list'));
		return lists.find(list => {
			const inInteractiveList = list.closest('.interactive-list, [class*="interactive-list"], .chat-list-at-bottom');
			if (inInteractiveList) return true;

			const rows = Array.from(list.querySelectorAll('.monaco-list-row'));
			return rows.some(row => /request|response/.test((row.className || '').toLowerCase()));
		}) || null;
	}

	/* ── Broader fallback: scan for any visible text containers ── */
	function findFallbackRows() {
		const aux = document.getElementById('workbench.parts.auxiliarybar');
		if (!aux) return [];
		// Look for generic visible content blocks (fallback when monaco-list not found)
		const containers = aux.querySelectorAll('.monaco-tl-contents, .pane-body > div > div, [class*="content"] > div > div');
		const rows = Array.from(containers).filter(el => el instanceof HTMLElement && textOf(el).length > 20 && el.children.length > 0);
		return rows.slice(-20); // only recent rows
	}

	/* ── Extract rows ── */
	function getRows(list) {
		return Array.from(list.querySelectorAll('.monaco-list-row')).filter(r => r instanceof HTMLElement);
	}

	function rowRole(r) { return (r.className || '').toLowerCase().includes('request') ? 'user' : 'assistant'; }

	function extractThinkingParts(el) {
		const body = el.querySelector('.chat-used-context-list') || el;
		return Array.from(body.querySelectorAll('.chat-thinking-item.markdown-content'))
			.filter(item => !item.closest('.chat-thinking-tool-wrapper'))
			.map(item => textOf(item))
			.filter(text => text && text !== '思考' && text.toLowerCase() !== 'thinking');
	}

	function extractThinkingText(el) {
		const parts = extractThinkingParts(el);
		const text = parts.join(String.fromCharCode(10) + String.fromCharCode(10)).trim();
		return text;
	}

	function normalizeWords(text) {
		return (' ' + text.toLowerCase().replace(/[^a-z\u4e00-\u9fff]+/g, ' ').trim() + ' ');
	}

	function containsWord(text, needles) {
		const normalized = normalizeWords(text);
		return needles.some(needle => normalized.includes(' ' + needle + ' '));
	}

	function inferToolName(iconClass, displayName, summary) {
		const text = (iconClass + ' ' + displayName + ' ' + summary).toLowerCase();
		if (iconClass.includes('codicon-terminal') || containsWord(text, ['run', 'running', 'execute', 'executed', 'command', 'terminal', 'build', 'open', 'switch', '执行', '运行'])) return 'run';
		if (iconClass.includes('codicon-search') || containsWord(text, ['search', 'searched', 'find', 'found', 'grep', 'scan', 'scanned', 'lookup', '搜索', '查找'])) return 'search';
		if (/codicon-(checklist|files|file|book|list-tree)/.test(iconClass) || containsWord(text, ['review', 'reviewed', 'read', 'checked', 'check', 'inspect', 'inspected', '读取', '检查', '审查'])) return 'read';
		if (/codicon-(edit|pencil|save)/.test(iconClass) || containsWord(text, ['edit', 'edited', 'write', 'wrote', 'apply', 'applied', 'patch', 'patched', 'create', 'created', '编辑', '修改', '创建'])) return 'edit';
		return 'tool';
	}

	function extractToolDescriptor(el) {
		const iconClass = el.querySelector('.chat-thinking-icon')?.className || '';
		const invocation = el.querySelector('.chat-tool-invocation-part') || el;
		const labelNode = invocation.querySelector('.chat-used-context-label [aria-label], .chat-used-context-label .monaco-button-label, .chat-used-context-label .monaco-button-mdlabel, .chat-used-context-label, [aria-label]');
		const ariaLabel = labelNode instanceof Element ? (labelNode.getAttribute('aria-label') || '').trim() : '';
		const labelText = labelNode ? textOf(labelNode) : '';
		const displayName = ariaLabel || labelText || cloneTextWithout(invocation, ['.chat-thinking-icon', '.codicon', 'svg']) || cloneTextWithout(el, ['.chat-thinking-icon', '.codicon', 'svg']) || 'Tool';
		const summary = cloneTextWithout(invocation, ['.chat-used-context-label', '.chat-thinking-icon', '.codicon', 'svg', 'style', 'script', '.xterm', '.xterm-viewport', '.xterm-screen', '.xterm-helpers', '.xterm-decoration-container', '.xterm-accessibility']) || cloneTextWithout(el, ['.chat-used-context-label', '.chat-thinking-icon', '.codicon', 'svg', 'style', 'script', '.xterm', '.xterm-viewport', '.xterm-screen', '.xterm-helpers', '.xterm-decoration-container', '.xterm-accessibility']) || displayName;
		if ((!summary || summary === 'Tool') && (!displayName || displayName === 'Tool')) return null;
		const toolName = inferToolName(iconClass, displayName, summary);
		const state = /failed|error|错误|失败/.test((displayName + ' ' + summary).toLowerCase())
			? 'failed'
			: (/running|正在运行|processing|正在处理|loading|加载/.test((displayName + ' ' + summary).toLowerCase()) ? 'running' : 'succeeded');
		return { toolName, displayName, summary, state };
	}

	function classifyActionSummary(title, content) {
		const normalized = (title + ' ' + content).toLowerCase().trim();
		if (!normalized || normalized.length > 240) return null;
		if (containsWord(normalized, ['search', 'searched', 'searching', 'find', 'found', 'grep', 'scan', 'scanned', 'scanning'])) return 'search';
		if (containsWord(normalized, ['review', 'reviewed', 'reviewing', 'read', 'reads', 'reading', 'check', 'checked', 'checking', 'inspect', 'inspected', 'inspecting'])) return 'read';
		if (containsWord(normalized, ['execute', 'executed', 'executing', 'run', 'runs', 'running', 'ran', 'build', 'built', 'building', 'open', 'opened', 'opening', 'switch', 'switched', 'switching'])) return 'run';
		if (containsWord(normalized, ['create', 'created', 'creating', 'edit', 'edited', 'editing', 'write', 'wrote', 'writing', 'apply', 'applied', 'applying', 'patch', 'patched', 'patching'])) return 'edit';
		return null;
	}

	/* ── Extract blocks from a response row ── */
	function extractBlocks(row, msgId) {
		const blocks = [];
		const hasFineSelectors = row.querySelector('.chat-markdown-part, .chat-used-context, .rendered-markdown, .chat-thinking');
		const contents = hasFineSelectors ? row.querySelector('.monaco-tl-contents') : row;

		if (!contents && !hasFineSelectors) {
			// 🔻 Fallback: extract entire row as one text block
			const t = textOf(row);
			if (t) blocks.push({ id: stableId('tx_', t.slice(0,64)), type: 'text', status: 'completed', format: 'markdown', content: t, _fallback: true });
			return blocks;
		}

		if (!contents) {
			const t = textOf(row); if (t) blocks.push({ id: stableId('t_', t.slice(0,64)), type: 'text', status: 'completed', format: 'markdown', content: t });
			return blocks;
		}

		// Fine: check if we found any specialized blocks below
		let specializedCount = 0;

		// Thinking
		for (const el of Array.from(contents.querySelectorAll('.chat-used-context.chat-thinking-box'))) {
			const title = el.querySelector('.chat-thinking-title-detail-text');
			const titleText = title ? textOf(title) : '';
			const c = extractThinkingText(el);
			if (c) { blocks.push({ id: stableId('th_', msgId + c.slice(0,32)), type: 'thinking', status: 'completed', format: 'plain', content: c, visibility: 'collapsed', title: titleText || 'Thinking' }); specializedCount++; }
		}

		// Tool wrappers
		for (const el of Array.from(contents.querySelectorAll('.chat-thinking-tool-wrapper'))) {
			const tool = extractToolDescriptor(el);
			if (tool && (tool.summary || tool.displayName)) {
				blocks.push({
					id: stableId('tl_', msgId + tool.summary.slice(0,32)), type: 'tool_call', status: 'completed',
					toolCallId: stableId('tc_', tool.displayName.slice(0,64)), toolName: tool.toolName,
					displayName: tool.displayName, state: tool.state, summary: tool.summary
				});
				specializedCount++;
			}
		}

		// Markdown content (text + code)
		for (const el of Array.from(contents.querySelectorAll('.chat-markdown-part.rendered-markdown, .rendered-markdown'))) {
			if (el.closest('.chat-used-context.chat-thinking-box, .chat-thinking-tool-wrapper')) continue;
			const c = textOf(el); if (!c) continue;
			const isCode = el.classList.contains('progress-step');
			const type = isCode ? 'code_block' : 'text';
			const format = isCode ? 'plain' : 'markdown';
			const extra = isCode ? { language: 'plaintext' } : {};
			blocks.push({ id: stableId(isCode ? 'cd_' : 'tx_', msgId + c.slice(0,48)), type, status: 'completed', format, content: c, ...extra });
			specializedCount++;
		}

		// 🔻 Fine-mode health: if no specialized blocks found in this row, increment fail counter
		if (specializedCount === 0) {
			window.__copilotMirrorState.fineFailCount = (window.__copilotMirrorState.fineFailCount || 0) + 1;
			if (window.__copilotMirrorState.fineFailCount >= 3 && window.__copilotMirrorState.fineMode) {
				window.__copilotMirrorState.fineMode = false;
				emit({ kind: 'heartbeat', _fallback: 'fine_parsing_failed_switching_to_full_text' });
			}
		}

		// Fallback: try contents text, then row text
		if (blocks.length === 0) {
			const t = textOf(contents) || textOf(row);
			if (t) blocks.push({ id: stableId('tx_', t.slice(0,64)), type: 'text', status: 'completed', format: 'markdown', content: t, _fallback: true });
		}
		return blocks;
	}

	/* ── Extract all messages ── */
	function extractAll() {
		const list = findList();
		if (list) {
			const rows = getRows(list);
			if (rows.length > 0) {
				return rows.map((row, i) => {
					const role = rowRole(row);
					const t = textOf(row);
					const mid = stableId('msg_' + role, i + ':' + role);
					const now = new Date().toISOString();
					return { id: mid, role, status: 'completed', createdAt: now, updatedAt: now, blocks: extractBlocks(row, mid), metadata: { domIndex: i } };
				});
			}
		}

		// Broader fallback: scan for visible text containers
		{
			const aux = document.getElementById('workbench.parts.auxiliarybar');
			if (aux) {
				const containers = aux.querySelectorAll('.monaco-tl-contents, .pane-body > div > div, [class*="content"] > div > div');
				const fallbackRows = Array.from(containers).filter(el => el instanceof HTMLElement && textOf(el).length > 20 && el.children.length > 0).slice(-20);
				if (fallbackRows.length > 0) {
					return fallbackRows.map((row, i) => {
						const t = textOf(row);
						const mid = stableId('msg_fb_', i + '');
						const now = new Date().toISOString();
						return { id: mid, role: 'assistant', status: 'completed', createdAt: now, updatedAt: now, blocks: [{ id: stableId('tx_', t.slice(0,64)), type: 'text', status: 'completed', format: 'markdown', content: t, _fallback: true }], metadata: { domIndex: i, _fallback: true } };
					});
				}
			}
		}

		return [];
	}

	/* ── Snapshot ── */
	function flushSnapshot() {
		const messages = extractAll();
		emit({ kind: 'snapshot', messages });
		const fingerprints = window.__copilotMirrorState.messageFingerprints;
		for (const m of messages) {
			for (const b of m.blocks) {
				if (typeof b.content === 'string') window.__copilotMirrorState.blockContent.set(b.id, b.content);
			}
			if (!fingerprints.has(m.id)) fingerprints.set(m.id, true);
		}
	}

	/* ── Delta ── */
	function flushDelta() {
		const messages = extractAll();
		const known = window.__copilotMirrorState.messageFingerprints;

		for (const m of messages) {
			const isNew = !known.has(m.id);
			if (isNew) {
				known.set(m.id, true);
				emit({ kind: 'message', message: { ...m, blocks: m.blocks } });
				for (const b of m.blocks) {
					if (typeof b.content === 'string' && b.content) {
						window.__copilotMirrorState.blockContent.set(b.id, b.content);
					}
				}
			}
			for (const b of m.blocks) {
				const prev = window.__copilotMirrorState.blockContent.get(b.id);
				const cur = b.content || '';
				if (prev === undefined) {
					window.__copilotMirrorState.blockContent.set(b.id, cur);
					if (known.has(m.id)) emit({ kind: 'block', messageId: m.id, block: { ...b, content: '' } });
					if (cur && b.type !== 'tool_call') emit({ kind: 'delta', messageId: m.id, blockId: b.id, blockType: b.type, offset: 0, chunk: cur, format: b.format || 'markdown' });
				} else if (cur !== prev) {
					const off = cur.startsWith(prev) ? prev.length : 0;
					const chunk = cur.startsWith(prev) ? cur.slice(prev.length) : cur;
					emit({ kind: 'delta', messageId: m.id, blockId: b.id, blockType: b.type, offset: off, chunk, format: b.format || 'markdown' });
					window.__copilotMirrorState.blockContent.set(b.id, cur);
				}
			}
		}
	}

/* ── Merge incremental assistant messages (same-role prefix dedup) ── */
	function mergeIncrementalMessages(messages) {
		const result = [];
		for (const msg of messages) {
			if (result.length > 0) {
				const prev = result[result.length - 1];
				if (prev.role === msg.role) {
					const prevText = prev.blocks.map(b => (typeof b.content === 'string' ? b.content : '')).join('');
					const curText = msg.blocks.map(b => (typeof b.content === 'string' ? b.content : '')).join('');
					if (prevText.length > 0 && curText.startsWith(prevText)) {
						// Current message is an extension of previous; replace prev with cur
						result[result.length - 1] = { ...prev, blocks: msg.blocks };
						continue;
					}
				}
			}
			result.push(msg);
		}
		return result;
	}

/* ── Init (async with DOM retry) ── */
	async function waitForList(retries = 15, delayMs = 400) {
		for (let i = 0; i < retries; i++) {
			const list = findList();
			if (list) return list;
			await new Promise(r => setTimeout(r, delayMs));
		}
		return null;
	}

	const list = await waitForList();
	if (!list) return { ok: false, reason: 'monaco_list_not_found' };

	// Emit full snapshot (used by both initial connect and polling)
	function emitSnapshot() {
		const messages = mergeIncrementalMessages(extractAll());
	// Detect if VS Code is actively generating (session in progress)
		try {
			const ic = document.querySelector('.chat-input-container');
			const hwc = ic instanceof HTMLElement && ic.classList.contains('working');
			const ia = ic || document.querySelector('.interactive-session') || document.body;
			const sb = ia.querySelector('button[aria-label*="stop" i], button[aria-label*="cancel" i], a[aria-label*="取消" i], a[aria-label*="stop" i], a[aria-label*="cancel" i], .codicon-stop, .codicon-stop-circle, .chat-stop-button');
			const iw = hwc || (sb instanceof HTMLElement && sb.offsetParent !== null);
			if (iw && messages.length > 0) {
				for (let i = messages.length - 1; i >= 0; i--) {
					if (messages[i].role === 'assistant') {
						messages[i].status = 'streaming';
						const blk = messages[i].blocks;
						if (blk && blk.length > 0) blk[blk.length - 1].status = 'streaming';
						break;
	}
	}
	}
	} catch (_) {}
			for (const b of m.blocks) {
				if (typeof b.content === 'string') window.__copilotMirrorState.blockContent.set(b.id, b.content);
			}
			if (!fingerprints.has(m.id)) fingerprints.set(m.id, true);
		}
	}

	emitSnapshot();

	// Poll every 300ms (reliable, no rAF throttling issues in background panels)
	setInterval(() => { emitSnapshot(); }, 300);

	return { ok: true };
})();
	`.trim();
}

/**
 * Build a one-shot snapshot script that extracts the currently visible chat
 * messages directly from the DOM. Unlike the long-lived observer, this does
 * not rely on any previously injected page state, so it is safe to use after
 * bridge restarts or when the old observer selected the wrong list.
 */
export function buildCurrentSnapshotScript(): string {
	return `(() => {
		try {
			function hash(value) {
				let h = 0;
				for (let i = 0; i < value.length; i++) { h = ((h << 5) - h) + value.charCodeAt(i); h |= 0; }
				return Math.abs(h).toString(36);
			}
			function stableId(prefix, value) { return prefix + '_' + hash(value); }
			function textOf(node) { return (node?.textContent || node?.innerText || '').replace(/\u00a0/g, ' ').trim(); }
			function cloneTextWithout(node, selectors) {
				if (!node) return '';
				const clone = node.cloneNode(true);
				for (const selector of selectors) {
					for (const child of Array.from(clone.querySelectorAll(selector))) child.remove();
				}
				return textOf(clone);
			}

			function findList() {
				const aux = document.getElementById('workbench.parts.auxiliarybar');
				if (!aux) return null;

				const preferred = aux.querySelector('.interactive-list .monaco-list, .chat-list-at-bottom .monaco-list, [class*="interactive-list"] .monaco-list');
				if (preferred) return preferred;

				const lists = Array.from(aux.querySelectorAll('.monaco-list'));
				return lists.find(list => {
					const inInteractiveList = list.closest('.interactive-list, [class*="interactive-list"], .chat-list-at-bottom');
					if (inInteractiveList) return true;

					const rows = Array.from(list.querySelectorAll('.monaco-list-row'));
					return rows.some(row => /request|response/.test((row.className || '').toLowerCase()));
				}) || null;
			}

			function getRows(list) {
				return Array.from(list.querySelectorAll('.monaco-list-row')).filter(row => row instanceof HTMLElement);
			}

			function rowRole(row) {
				return (row.className || '').toLowerCase().includes('request') ? 'user' : 'assistant';
			}

			function extractThinkingParts(el) {
				const body = el.querySelector('.chat-used-context-list') || el;
				return Array.from(body.querySelectorAll('.chat-thinking-item.markdown-content'))
					.filter(item => !item.closest('.chat-thinking-tool-wrapper'))
					.map(item => textOf(item))
					.filter(text => text && text !== '思考' && text.toLowerCase() !== 'thinking');
			}

			function extractThinkingText(el) {
				const parts = extractThinkingParts(el);
				const text = parts.join(String.fromCharCode(10) + String.fromCharCode(10)).trim();
				return text;
			}

			function normalizeWords(text) {
				return (' ' + text.toLowerCase().replace(/[^a-z\u4e00-\u9fff]+/g, ' ').trim() + ' ');
			}

			function containsWord(text, needles) {
				const normalized = normalizeWords(text);
				return needles.some(needle => normalized.includes(' ' + needle + ' '));
			}

			function inferToolName(iconClass, displayName, summary) {
				const text = (iconClass + ' ' + displayName + ' ' + summary).toLowerCase();
				if (iconClass.includes('codicon-terminal') || containsWord(text, ['run', 'running', 'execute', 'executed', 'command', 'terminal', 'build', 'open', 'switch', '执行', '运行'])) return 'run';
				if (iconClass.includes('codicon-search') || containsWord(text, ['search', 'searched', 'find', 'found', 'grep', 'scan', 'scanned', 'lookup', '搜索', '查找'])) return 'search';
				if (/codicon-(checklist|files|file|book|list-tree)/.test(iconClass) || containsWord(text, ['review', 'reviewed', 'read', 'checked', 'check', 'inspect', 'inspected', '读取', '检查', '审查'])) return 'read';
				if (/codicon-(edit|pencil|save)/.test(iconClass) || containsWord(text, ['edit', 'edited', 'write', 'wrote', 'apply', 'applied', 'patch', 'patched', 'create', 'created', '编辑', '修改', '创建'])) return 'edit';
				return 'tool';
			}

			function extractToolDescriptor(el) {
				const iconClass = el.querySelector('.chat-thinking-icon')?.className || '';
				const invocation = el.querySelector('.chat-tool-invocation-part') || el;
				const labelNode = invocation.querySelector('.chat-used-context-label [aria-label], .chat-used-context-label .monaco-button-label, .chat-used-context-label .monaco-button-mdlabel, .chat-used-context-label, [aria-label]');
				const ariaLabel = labelNode instanceof Element ? (labelNode.getAttribute('aria-label') || '').trim() : '';
				const labelText = labelNode ? textOf(labelNode) : '';
				const displayName = ariaLabel || labelText || cloneTextWithout(invocation, ['.chat-thinking-icon', '.codicon', 'svg']) || cloneTextWithout(el, ['.chat-thinking-icon', '.codicon', 'svg']) || 'Tool';
				const summary = cloneTextWithout(invocation, ['.chat-used-context-label', '.chat-thinking-icon', '.codicon', 'svg', 'style', 'script', '.xterm', '.xterm-viewport', '.xterm-screen', '.xterm-helpers', '.xterm-decoration-container', '.xterm-accessibility']) || cloneTextWithout(el, ['.chat-used-context-label', '.chat-thinking-icon', '.codicon', 'svg', 'style', 'script', '.xterm', '.xterm-viewport', '.xterm-screen', '.xterm-helpers', '.xterm-decoration-container', '.xterm-accessibility']) || displayName;
				if ((!summary || summary === 'Tool') && (!displayName || displayName === 'Tool')) return null;
				const toolName = inferToolName(iconClass, displayName, summary);
				const state = /failed|error|错误|失败/.test((displayName + ' ' + summary).toLowerCase())
					? 'failed'
					: (/running|正在运行|processing|正在处理|loading|加载/.test((displayName + ' ' + summary).toLowerCase()) ? 'running' : 'succeeded');
				return { toolName, displayName, summary, state };
			}

			function classifyActionSummary(title, content) {
				const normalized = (title + ' ' + content).toLowerCase().trim();
				if (!normalized || normalized.length > 240) return null;
				if (containsWord(normalized, ['search', 'searched', 'searching', 'find', 'found', 'grep', 'scan', 'scanned', 'scanning'])) return 'search';
				if (containsWord(normalized, ['review', 'reviewed', 'reviewing', 'read', 'reads', 'reading', 'check', 'checked', 'checking', 'inspect', 'inspected', 'inspecting'])) return 'read';
				if (containsWord(normalized, ['execute', 'executed', 'executing', 'run', 'runs', 'running', 'ran', 'build', 'built', 'building', 'open', 'opened', 'opening', 'switch', 'switched', 'switching'])) return 'run';
				if (containsWord(normalized, ['create', 'created', 'creating', 'edit', 'edited', 'editing', 'write', 'wrote', 'writing', 'apply', 'applied', 'applying', 'patch', 'patched', 'patching'])) return 'edit';
				return null;
			}

			function extractBlocks(row, messageId) {
				const blocks = [];
				const hasFineSelectors = row.querySelector('.chat-markdown-part, .chat-used-context, .rendered-markdown, .chat-thinking');
				const contents = hasFineSelectors ? row.querySelector('.monaco-tl-contents') : row;

				if (!contents && !hasFineSelectors) {
					const text = textOf(row);
					if (text) {
						blocks.push({ id: stableId('tx_', text.slice(0, 64)), type: 'text', status: 'completed', format: 'markdown', content: text });
					}
					return blocks;
				}

				if (!contents) {
					const text = textOf(row);
					if (text) {
						blocks.push({ id: stableId('tx_', text.slice(0, 64)), type: 'text', status: 'completed', format: 'markdown', content: text });
					}
					return blocks;
				}

				for (const el of Array.from(contents.querySelectorAll('.chat-used-context.chat-thinking-box'))) {
					const title = el.querySelector('.chat-thinking-title-detail-text');
					const titleText = title ? textOf(title) : '';
					const content = extractThinkingText(el);
					if (content) {
						blocks.push({
							id: stableId('th_', messageId + content.slice(0, 32)),
							type: 'thinking',
							status: 'completed',
							format: 'plain',
							content,
							visibility: 'collapsed',
							title: titleText || 'Thinking'
						});
					}
				}

				for (const el of Array.from(contents.querySelectorAll('.chat-thinking-tool-wrapper'))) {
					const tool = extractToolDescriptor(el);
					if (tool && (tool.summary || tool.displayName)) {
						blocks.push({
							id: stableId('tl_', messageId + tool.summary.slice(0, 32)),
							type: 'tool_call',
							status: 'completed',
							toolCallId: stableId('tc_', tool.displayName.slice(0, 64)),
							toolName: tool.toolName,
							displayName: tool.displayName,
							state: tool.state,
							summary: tool.summary
						});
					}
				}

				for (const el of Array.from(contents.querySelectorAll('.chat-markdown-part.rendered-markdown, .rendered-markdown'))) {
					if (el.closest('.chat-used-context.chat-thinking-box, .chat-thinking-tool-wrapper')) continue;
					const content = textOf(el);
					if (!content) continue;
					const isCode = el.classList.contains('progress-step');
					blocks.push({
						id: stableId(isCode ? 'cd_' : 'tx_', messageId + content.slice(0, 48)),
						type: isCode ? 'code_block' : 'text',
						status: 'completed',
						format: isCode ? 'plain' : 'markdown',
						content,
						...(isCode ? { language: 'plaintext' } : {})
					});
				}

				if (blocks.length === 0) {
					const text = textOf(contents);
					if (text) {
						blocks.push({ id: stableId('tx_', text.slice(0, 64)), type: 'text', status: 'completed', format: 'markdown', content: text });
					}
				}

				return blocks;
			}

			const list = findList();
			if (!list) return JSON.stringify({ ok: false, reason: 'chat_list_not_found' });

			const rows = getRows(list);
			const now = new Date().toISOString();
			let messages = rows.map((row, index) => {
				const role = rowRole(row);
				const text = textOf(row);
				const messageId = stableId('msg_' + role, index + ':' + role);
				return {
					id: messageId,
					role,
					status: 'completed',
					createdAt: now,
					updatedAt: now,
					blocks: extractBlocks(row, messageId),
					metadata: { domIndex: index, source: 'snapshot_script' }
				};
			});

			// Merge consecutive same-role messages where later content prefixes earlier
			{
				const merged = [];
				for (const msg of messages) {
					if (merged.length > 0) {
						const prev = merged[merged.length - 1];
						if (prev.role === msg.role) {
							const prevText = prev.blocks.map(b => typeof b.content === 'string' ? b.content : '').join('');
							const curText = msg.blocks.map(b => typeof b.content === 'string' ? b.content : '').join('');
							if (prevText.length > 0 && curText.startsWith(prevText)) {
								merged[merged.length - 1] = { ...prev, blocks: msg.blocks };
								continue;
							}
						}
					}
					merged.push(msg);
				}
				messages = merged;
			}

			
	// Detect if VS Code is actively generating (for stop button sync)
	const ic = document.querySelector('.chat-input-container');
	const hwc = ic instanceof HTMLElement && ic.classList.contains('working');
	const ia = ic || document.querySelector('.interactive-session') || document.body;
	const sb = ia.querySelector('button[aria-label*="stop" i], button[aria-label*="cancel" i], a[aria-label*="取消" i], a[aria-label*="stop" i], a[aria-label*="cancel" i], .codicon-stop, .codicon-stop-circle, .chat-stop-button');
	const iw = hwc || (sb instanceof HTMLElement && sb.offsetParent !== null);
	if (iw && messages.length > 0) {
	for (let i = messages.length - 1; i >= 0; i--) {
	if (messages[i].role === 'assistant') {
	messages[i].status = 'streaming';
	const blk = messages[i].blocks;
	if (blk && blk.length > 0) blk[blk.length - 1].status = 'streaming';
	break;
	}
	}
	}
return JSON.stringify({ ok: true, result: { messages } });
		} catch (error) {
			return JSON.stringify({ ok: false, reason: error instanceof Error ? error.message : String(error) });
		}
	})();`.trim();
}

/**
 * Build send-prompt script targeting Monaco .interactive-input-editor.
 */
export function buildSendPromptScript(text: string, submit: boolean): string {
	return `(() => {
		const text = ${JSON.stringify(text)};

		// Monaco input editor
		const editor = document.querySelector('.interactive-input-editor');
		if (editor) {
			const textarea = editor.querySelector('textarea');
			if (textarea) textarea.focus();

			// Set via Monaco's underlying textarea + events
			if (textarea) {
				const proto = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
				if (proto?.set) {
					proto.set.call(textarea, text);
					textarea.dispatchEvent(new Event('input', { bubbles: true }));
				}
			}

			if (${submit ? 'true' : 'false'}) {
				setTimeout(() => {
					if (textarea) textarea.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
				}, 100);
			}
			return JSON.stringify({ ok: true });
		}

		// Fallback: visible textareas (exclude Monaco and xterm helpers)
		for (const ta of document.querySelectorAll('textarea')) {
			if (ta.offsetParent === null || ta.className === 'ime-text-area' || ta.className === 'xterm-helper-textarea') continue;
			ta.focus();
			const proto = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
			if (proto?.set) {
				proto.set.call(ta, text);
				ta.dispatchEvent(new Event('input', { bubbles: true }));
			}
			if (${submit ? 'true' : 'false'}) {
				ta.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true }));
			}
			return JSON.stringify({ ok: true });
		}
		return JSON.stringify({ ok: false, reason: 'input_not_found' });
	})();
	`.trim();
}

/**
 * Build focus-input script.
 */
export function buildFocusInputScript(): string {
	return `(() => {
		const el = document.querySelector('.interactive-input-editor textarea, .interactive-input-editor [contenteditable]');
		if (el) { el.focus(); return JSON.stringify({ ok: true }); }
		return JSON.stringify({ ok: false, reason: 'input_not_found' });
	})();
	`.trim();
}

/**
 * Build stop-generation script.
 */
export function buildStopGenerationScript(): string {
	// Multi-strategy stop button detection that covers various VS Code versions.
	return `(() => {
		// Strategy 1: find the working chat input container and look for any stop-related action
		const container = document.querySelector('.chat-input-container.working');
		if (container) {
			const actions = container.querySelectorAll('a.action-label, button, [role="button"], .monaco-button, .action-label');
			for (const el of actions) {
				if (el instanceof HTMLElement && el.offsetParent !== null) {
					const label = (el.getAttribute('aria-label') || el.getAttribute('title') || el.textContent || '').toLowerCase();
					if (/stop|cancel|\\\\u53d6\\\\u6d88/.test(label) || el.querySelector('.codicon-stop, .codicon-stop-circle')) {
						el.click();
						return JSON.stringify({ ok: true, selector: 'working_container_action', label: label.slice(0, 20) });
					}
				}
			}
		}
		// Strategy 2: broad selectors covering all common VS Code stop button variants
		const sel = [
			'button[aria-label*="stop" i]', 'button[aria-label*="cancel" i]',
			'button[title*="stop" i]', 'button[title*="cancel" i]',
			'a[aria-label*="\\\\u53d6\\\\u6d88" i]', 'a[aria-label*="stop" i]', 'a[aria-label*="cancel" i]',
			'a[title*="stop" i]', 'a[title*="cancel" i]',
			'[role="button"][aria-label*="stop" i]', '[role="button"][aria-label*="cancel" i]',
			'[role="button"][title*="stop" i]', '[role="button"][title*="cancel" i]',
			'.action-label[aria-label*="stop" i]', '.action-label[aria-label*="cancel" i]',
			'.action-label[title*="stop" i]', '.action-label[title*="cancel" i]',
			'.monaco-button[aria-label*="stop" i]', '.monaco-button[aria-label*="cancel" i]',
			'.chat-stop-button', '.codicon-stop', '.codicon-stop-circle'
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
	`.trim();
}

/**
 * Build script to extract the session list from the sidebar.
 *
 * DOM (from CDP probe):
 *   .agent-sessions-container
 *     → .monaco-list (the session list, identifiable by .selection-single)
 *       → .monaco-list-row
 *         → .monaco-highlighted-label (session title)
 *     → .agent-session-section-label ("更多" section)
 *     → .agent-session-section-count
 *
 * The active chat view title: .action-label.chat-view-title-label-container
 */
export function buildSessionListScript(): string {
	return `(() => {
		try {
			const normalize = value => (value || '').replace(/\u00a0/g, ' ').replace(/\\s+/g, ' ').trim();

			const viewer = document.querySelector('[class*="agent-sessions-viewer"]');
			if (!viewer) {
				return JSON.stringify({ ok: false, reason: 'no_session_viewer' });
			}

			const sessionList = Array.from(viewer.querySelectorAll('.monaco-list')).find(list => {
				const aria = normalize(list.getAttribute('aria-label'));
				if (/智能体会话|agent sessions/i.test(aria)) return true;
				return Array.from(list.querySelectorAll('.monaco-list-row')).some(row => row.querySelector('.monaco-highlighted-label'));
			});
			if (!sessionList) {
				return JSON.stringify({ ok: false, reason: 'no_session_list' });
			}

			const rows = Array.from(sessionList.querySelectorAll('.monaco-list-row'));
			const sessions = [];
			let visibleIndex = 0;
			let activeSessionId;

			rows.forEach((row, domIndex) => {
				const title = normalize(
					row.querySelector('.monaco-highlighted-label')?.textContent ||
					row.querySelector('.label-name')?.textContent
				);

				if (!title || title === '更多' || /^更多\\d*$/.test(title)) return;

				const active =
					row.getAttribute('aria-selected') === 'true' ||
					row.classList.contains('selected') ||
					row.classList.contains('focused');

				const sessionId =
					'session_' +
					domIndex +
					'_' +
					title.replace(/[^a-zA-Z0-9\\u4e00-\\u9fff]/g, '_').slice(0, 32);

				const timeEl = row.querySelector('[class*="time"], [class*="date"], [class*="timestamp"]');
				const updatedAt = timeEl ? normalize(timeEl.textContent) : undefined;

				sessions.push({
					sessionId,
					title,
					index: visibleIndex,
					active,
					updatedAt,
					source: 'dom'
				});

				if (active) activeSessionId = sessionId;
				visibleIndex += 1;
			});

			// If no row had active marker, try fallback via title matching
			if (!activeSessionId) {
				for (const s of sessions) s.active = false;

				const activeTitle = normalize(
					document.querySelector('.action-label.chat-view-title-label-container .chat-view-title-label')?.textContent ||
					document.querySelector('.action-label.chat-view-title-label-container')?.textContent ||
					document.querySelector('[class*="chat-title"]')?.textContent
				);

				if (activeTitle) {
					const found = sessions.find(s => normalize(s.title) === activeTitle);
					if (found) {
						found.active = true;
						activeSessionId = found.sessionId;
					}
				}
			}

			return JSON.stringify({ ok: true, result: { sessions, activeSessionId } });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to ensure the agent sessions sidebar is visible.
 *
 * Strategy:
 * 1. If `agent-sessions-viewer` exists and is actually visible, do nothing.
 * 2. Otherwise click the titlebar button with aria-label like "显示智能体会话边栏".
 */
export function buildOpenSessionSidebarScript(): string {
	return `(() => {
		try {
			const existing = document.querySelector('[class*="agent-sessions-viewer"]');
			const isVisible = existing instanceof HTMLElement
				? existing.getBoundingClientRect().width > 24 && existing.getBoundingClientRect().height > 24 && existing.clientWidth > 24
				: false;
			if (isVisible) {
				return JSON.stringify({ ok: true, action: 'already_open' });
			}

			const toggle = Array.from(document.querySelectorAll('button, [role="button"], a, .action-label'))
				.find(el => {
					if (!(el instanceof HTMLElement)) return false;
					const aria = (el.getAttribute('aria-label') || '').trim();
					const text = (el.textContent || '').trim();
					return /智能体会话边栏/.test(aria) || /智能体会话边栏/.test(text);
				});

			if (!(toggle instanceof HTMLElement)) {
				return JSON.stringify({ ok: false, reason: 'no_session_sidebar_toggle' });
			}

			toggle.click();
			toggle.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }));
			return JSON.stringify({ ok: true, action: 'opened_sidebar' });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to switch to another session by index.
 */
export function buildSwitchSessionScript(index: number): string {
	const idx = Math.floor(index);
	return `(() => {
		try {
			const sessionList = Array.from(document.querySelectorAll('.monaco-list'))
				.find(l => l.closest('[class*="agent-sessions-viewer"]'));
			if (!sessionList) return JSON.stringify({ ok: false, reason: 'no_session_list' });

			// Filter out non-session rows (e.g. "更多")
			const rows = Array.from(sessionList.querySelectorAll('.monaco-list-row')).filter(row => {
				const title = (row.querySelector('.monaco-highlighted-label')?.textContent || '').trim();
				return title && !/^更多\\d*$/.test(title);
			});

			const targetRow = rows[${idx}];
			if (!targetRow) return JSON.stringify({ ok: false, reason: 'session_index_out_of_range', index: ${idx}, count: rows.length });

			if (targetRow instanceof HTMLElement) {
				targetRow.click();
				const inner = targetRow.querySelector('[role="button"], .monaco-highlighted-label');
				if (inner instanceof HTMLElement) inner.click();
				return JSON.stringify({ ok: true, title: (targetRow.querySelector('.monaco-highlighted-label')?.textContent || '').trim() });
			}
			return JSON.stringify({ ok: false, reason: 'row_not_clickable' });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to create a new session.
 */
export function buildNewSessionScript(): string {
	return `(() => {
		try {
			const btn = document.querySelector('a.monaco-button.secondary');
			if (btn && (btn.textContent || '').trim().includes('新建')) {
				if (btn instanceof HTMLElement) { btn.click(); return JSON.stringify({ ok: true }); }
			}
			// Fallback: broader new-session button search
			const all = Array.from(document.querySelectorAll('a, button, [role="button"]'));
			for (const el of all) {
				const txt = (el.textContent || '').trim().toLowerCase();
				if (txt.includes('new') || txt.includes('新建') || txt.includes('新会话')) {
					if (el instanceof HTMLElement) { el.click(); return JSON.stringify({ ok: true, source: 'broad_fallback' }); }
				}
			}
			return JSON.stringify({ ok: false, reason: 'new_session_button_not_found' });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to get the current active session ID from the chat view title.
 */
export function buildGetActiveSessionScript(): string {
	return `(() => {
		try {
			const el = document.querySelector('.action-label.chat-view-title-label-container');
			if (el) return JSON.stringify({ ok: true, title: (el.textContent || '').trim() });
			return JSON.stringify({ ok: false, reason: 'no_active_session_title' });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

// ─── Slash Commands ──────────────────────────────────────────────

/**
 * Build script to get the list of available slash commands.
 *
 * Strategy:
 * 1. Focus the chat input
 * 2. Type "/" to trigger suggest widget
 * 3. Wait for monaco suggest widget to appear
 * 4. Scan visible suggestion items
 * 5. Revert input to original state
 */
export function buildSlashListScript(query?: string): string {
	const q = query ?? '';
	return `(() => {
		try {
			const chatCtrl = document.querySelector('.chat-controls-container');
			if (!chatCtrl) return JSON.stringify({ ok: false, reason: 'no_chat_controls' });

			// Find the input textarea
			const ta = chatCtrl.querySelector('textarea.inputarea') || chatCtrl.querySelector('textarea');
			if (!ta) return JSON.stringify({ ok: false, reason: 'no_textarea' });

			// Save original value, focus, and type /
			const origValue = ta.value || '';
			ta.focus();

			// Type slash (and optional query) using value + events
			const prefix = ${JSON.stringify('/' + q)};
			const proto = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
			if (!proto?.set) return JSON.stringify({ ok: false, reason: 'no_value_setter' });
			proto.set.call(ta, prefix);
			ta.selectionStart = prefix.length;
			ta.selectionEnd = prefix.length;
			ta.dispatchEvent(new InputEvent('input', { data: prefix, inputType: 'insertText', bubbles: true }));

			// Wait for suggest widget
			return JSON.stringify({ ok: true, action: 'wait_for_suggest', prefix });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to scan visible suggest widget list items.
 * Called after buildSlashListScript has triggered the suggest widget.
 */
export function buildScanSuggestWidgetScript(): string {
	return `(() => {
		try {
			// Check for visible suggest widget / monaco list attached to the editor
			const suggestWidget = document.querySelector('.suggest-widget:not([aria-hidden="true"]), .editor-widget:not([aria-hidden="true"])');
			const list = suggestWidget ? suggestWidget.querySelector('.monaco-list') : null;

			if (!list) {
				// Check for a context-view / quick-input-widget that might hold commands
				const ctxView = document.querySelector('.context-view.visible');
				if (ctxView) {
					const items = Array.from(ctxView.querySelectorAll('[role="option"], .monaco-list-row'));
					if (items.length > 0) {
						const commands = items.map((el, i) => ({
							id: el.id || 'slash_' + i,
							label: (el.querySelector('.monaco-highlighted-label')?.textContent || el.textContent || '').trim().split('\\n')[0],
							title: el.getAttribute('aria-label') || '',
							description: el.querySelector('.monaco-icon-label-description')?.textContent?.trim() || '',
							index: i,
							source: 'dom'
						}));
						return JSON.stringify({ ok: true, result: { items: commands } });
					}
				}
				return JSON.stringify({ ok: false, reason: 'no_suggest_widget' });
			}

			const rows = Array.from(list.querySelectorAll('.monaco-list-row'));
			const commands = rows.map((row, i) => {
				const labelEl = row.querySelector('.monaco-highlighted-label');
				const label = labelEl ? (labelEl.textContent || '').trim() : (row.textContent || '').trim().split('\\n')[0];
				const ariaLabel = row.getAttribute('aria-label') || '';
				const descEl = row.querySelector('.monaco-icon-label-description');
				const description = descEl ? (descEl.textContent || '').trim() : '';
				return {
					id: row.id || 'slash_' + i,
					label,
					title: ariaLabel,
					description,
					index: i,
					source: 'dom'
				};
			});
			return JSON.stringify({ ok: true, result: { items: commands } });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to restore the chat input to its original state.
 */
export function buildRestoreInputScript(): string {
	return `(() => {
		try {
			const chatCtrl = document.querySelector('.chat-controls-container');
			const ta = chatCtrl ? (chatCtrl.querySelector('textarea.inputarea') || chatCtrl.querySelector('textarea')) : null;
			if (!ta) return JSON.stringify({ ok: false, reason: 'no_textarea' });
			const proto = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
			if (proto?.set) {
				proto.set.call(ta, '');
				ta.dispatchEvent(new Event('input', { bubbles: true }));
			}
			return JSON.stringify({ ok: true });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to apply a slash command (select from suggest widget or insert text).
 */
export function buildApplySlashScript(index: number, insertOnly: boolean): string {
	return `(() => {
		try {
			if (${insertOnly ? 'true' : 'false'}) {
				// Only insert the command text into input
				const chatCtrl = document.querySelector('.chat-controls-container');
				const ta = chatCtrl ? (chatCtrl.querySelector('textarea.inputarea') || chatCtrl.querySelector('textarea')) : null;
				if (!ta) return JSON.stringify({ ok: false, reason: 'no_textarea' });
				// The command text is already inserted by buildSlashListScript
				return JSON.stringify({ ok: true, action: 'inserted' });
			}

			// Click the Nth suggestion item
			const suggestWidget = document.querySelector('.suggest-widget:not([aria-hidden="true"]), .editor-widget:not([aria-hidden="true"])');
			const list = suggestWidget ? suggestWidget.querySelector('.monaco-list') : null;
			if (!list) return JSON.stringify({ ok: false, reason: 'no_suggest_widget' });
			const rows = Array.from(list.querySelectorAll('.monaco-list-row'));
			const target = rows[${Math.floor(index)}];
			if (!target) return JSON.stringify({ ok: false, reason: 'index_out_of_range', count: rows.length });
			if (target instanceof HTMLElement) {
				target.click();
				// Also dispatch mousedown to confirm selection
				target.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }));
			}
			return JSON.stringify({ ok: true });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

// ─── Agent Picker ────────────────────────────────────────────────

/**
 * Build script to get the list of available agents.
 *
 * Strategy (from CDP probe):
 * The real agent picker lives in the chat input toolbar as the
 * "设置智能体 / 打开智能体选取器" control, and opens a context-view list.
 */
export function buildAgentListScript(): string {
	return `(() => {
		try {
			function hasAgentMenu() {
				return Array.from(document.querySelectorAll('.context-view .monaco-list')).some(list => {
					if (list.getAttribute('role') !== 'menu') return false;
					const labels = Array.from(list.querySelectorAll('.monaco-list-row')).map(row => ((row.getAttribute('aria-label') || '').split(/[，,]/)[0] || row.textContent || '').replace(/\\s+/g, ' ').trim());
					return labels.some(label => /^(Agent|Ask|Plan)$/i.test(label));
				});
			}

			if (hasAgentMenu()) {
				return Promise.resolve(JSON.stringify({ ok: true, action: 'already_open' }));
			}

			const labelBtn = document.querySelector('li.chat-input-picker-item.chat-mode-picker-item .dropdown-label');
			const anchorBtn = document.querySelector('li.chat-input-picker-item.chat-mode-picker-item a.action-label[aria-label*="设置智能体"]');
			const dropdownBtn = document.querySelector('li.chat-input-picker-item.chat-mode-picker-item .monaco-dropdown');
			const quickInput = document.querySelector('.quick-input-widget:not([aria-hidden="true"])');
			if (quickInput) {
				document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
			}

			const attempts = [
				() => { if (labelBtn instanceof HTMLElement) labelBtn.click(); },
				() => {
					if (anchorBtn instanceof HTMLElement) {
						anchorBtn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0, buttons: 1 }));
						anchorBtn.click();
						anchorBtn.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, button: 0, buttons: 0 }));
					}
				},
				() => { if (dropdownBtn instanceof HTMLElement) dropdownBtn.click(); }
			];

			return new Promise(resolve => {
				let index = 0;
				const tryNext = () => {
					if (hasAgentMenu()) {
						resolve(JSON.stringify({ ok: true, action: 'opened_picker' }));
						return;
					}
					const attempt = attempts[index++];
					if (!attempt) {
						resolve(JSON.stringify({ ok: false, reason: 'agent_menu_not_opened' }));
						return;
					}
					attempt();
					setTimeout(tryNext, 180);
				};
				setTimeout(tryNext, 50);
			});
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to scan the agent list from the context-view or quick-input widget.
 */
export function buildScanAgentListScript(): string {
	return `(() => {
		try {
			function normalize(text) {
				return (text || '').replace(/\\s+/g, ' ').trim();
			}
			function canonicalizeAgentLabel(text) {
				const compact = (text || '').replace(/\\s+/g, '').toLowerCase();
				if (compact === 'agent' || compact === '智能体') return 'Agent';
				if (compact === 'ask') return 'Ask';
				if (compact === 'plan') return 'Plan';
				return normalize(text);
			}
			function isAgentRow(row) {
				const label = canonicalizeAgentLabel((row.getAttribute('aria-label') || '').split(/[，,]/)[0] || row.textContent || '');
				return /^(Agent|Ask|Plan)$/i.test(label) || /配置自定义智能体/.test(label);
			}

			function parseRows(rows, source) {
				const agents = rows.map((row, i) => {
					const rawText = normalize(row.textContent || '');
					const rawAria = normalize(row.getAttribute('aria-label') || '');
					const ariaLabel = canonicalizeAgentLabel(rawAria.split(/[，,]/)[0] || '');
					const textLabel = canonicalizeAgentLabel(rawText.split(/[，,]/)[0] || rawText);
					const label = ariaLabel || textLabel;
					const description = normalize(rawText.slice(label.length));
					const active = row.classList.contains('focused') || row.classList.contains('selected') || row.getAttribute('aria-selected') === 'true';
					return {
						id: label.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]+/g, '_') || ('agent_' + i),
						name: label,
						description,
						index: i,
						active,
						source
					};
				}).filter(agent => agent.name && !/配置自定义智能体/.test(agent.name) && !/昨天|今天|天前|周前|个月前|本地\\s*[•·]|正在运行/.test(agent.name + ' ' + agent.description));

				const activeAgent = agents.find(agent => agent.active);
				if (activeAgent) {
					window.__copilotMirrorLastActiveAgent = { id: activeAgent.id, name: activeAgent.name };
				}
				return { agents, activeAgentId: activeAgent ? activeAgent.id : window.__copilotMirrorLastActiveAgent?.id };
			}

			const contextList = Array.from(document.querySelectorAll('.context-view .monaco-list'))
				.find(list => list.getAttribute('role') === 'menu' && Array.from(list.querySelectorAll('.monaco-list-row')).some(row => isAgentRow(row)));
			if (contextList) {
				const rows = Array.from(contextList.querySelectorAll('.monaco-list-row')).filter(row => row.classList.contains('action'));
				return JSON.stringify({ ok: true, result: parseRows(rows, 'context_view') });
			}

			const qiWidget = document.querySelector('.quick-input-widget:not([aria-hidden="true"])');
			if (!qiWidget) return JSON.stringify({ ok: false, reason: 'no_agent_picker_overlay' });

			const list = qiWidget.querySelector('.monaco-list');
			if (!list) return JSON.stringify({ ok: false, reason: 'no_list_in_picker' });
			const rows = Array.from(list.querySelectorAll('.monaco-list-row')).filter(row => isAgentRow(row));
			if (rows.length === 0) return JSON.stringify({ ok: false, reason: 'no_agent_rows_in_quick_input' });
			return JSON.stringify({ ok: true, result: parseRows(rows, 'quick_input') });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to switch to an agent by index.
 */
export function buildSwitchAgentScript(index: number): string {
	return `(() => {
		try {
			function normalize(text) {
				return (text || '').replace(/\\s+/g, ' ').trim();
			}
			function canonicalizeAgentLabel(text) {
				const compact = (text || '').replace(/\\s+/g, '').toLowerCase();
				if (compact === 'agent' || compact === '智能体') return 'Agent';
				if (compact === 'ask') return 'Ask';
				if (compact === 'plan') return 'Plan';
				return normalize(text);
			}
			function isAgentRow(row) {
				const label = canonicalizeAgentLabel((row.getAttribute('aria-label') || '').split(/[，,]/)[0] || row.textContent || '');
				return /^(Agent|Ask|Plan)$/i.test(label) || /配置自定义智能体/.test(label);
			}
			function getAgentRows() {
				const contextList = Array.from(document.querySelectorAll('.context-view .monaco-list'))
					.find(list => list.getAttribute('role') === 'menu' && Array.from(list.querySelectorAll('.monaco-list-row')).some(row => isAgentRow(row)));
				if (contextList) {
					return Array.from(contextList.querySelectorAll('.monaco-list-row')).filter(row => {
						const text = normalize((row.getAttribute('aria-label') || '') + ' ' + (row.textContent || ''));
						return row.classList.contains('action') && isAgentRow(row) && text && !/配置自定义智能体|昨天|今天|天前|周前|个月前|本地\\s*[•·]|正在运行/.test(text);
					});
				}
				const qiWidget = document.querySelector('.quick-input-widget:not([aria-hidden="true"])');
				if (!qiWidget) return null;
				const list = qiWidget.querySelector('.monaco-list');
				if (!list) return null;
				return Array.from(list.querySelectorAll('.monaco-list-row')).filter(row => {
					const text = normalize((row.getAttribute('aria-label') || '') + ' ' + (row.textContent || ''));
					return text && !/配置自定义智能体|昨天|今天|天前|周前|个月前|本地\\s*[•·]|正在运行/.test(text);
				});
			}

			const rows = getAgentRows();
			if (!rows) return JSON.stringify({ ok: false, reason: 'no_agent_picker_overlay' });
			const target = rows[${Math.floor(index)}];
			if (!target) return JSON.stringify({ ok: false, reason: 'index_out_of_range', count: rows.length });
			if (target instanceof HTMLElement) {
				const label = canonicalizeAgentLabel(((target.getAttribute('aria-label') || '').split(/[，,]/)[0] || '').trim()) || canonicalizeAgentLabel(target.textContent || '');
				const id = label.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]+/g, '_') || ('agent_${Math.floor(index)}');
				window.__copilotMirrorLastActiveAgent = { id, name: label };
				target.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0, buttons: 1 }));
				target.click();
				target.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, button: 0, buttons: 0 }));
				return JSON.stringify({ ok: true, result: { id, name: label } });
			}
			return JSON.stringify({ ok: false, reason: 'target_not_clickable' });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to close the agent picker.
 */
export function buildCloseAgentPickerScript(): string {
	return `(() => {
		try {
			const qiWidget = document.querySelector('.quick-input-widget:not([aria-hidden="true"])');
			const contextView = Array.from(document.querySelectorAll('.context-view'))
				.find(view => view.getAttribute('aria-hidden') !== 'true' && Array.from(view.querySelectorAll('.monaco-list-row')).some(row => /^(Agent|Ask|Plan)$/i.test(((row.getAttribute('aria-label') || '').split(/[，,]/)[0] || row.textContent || '').replace(/\\s+/g, ' ').trim()) || /配置自定义智能体/.test((row.getAttribute('aria-label') || row.textContent || '').replace(/\\s+/g, ' ').trim())));
			if (qiWidget || contextView) {
				// Press Escape to close
				const ev = new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true });
				document.dispatchEvent(ev);
				return JSON.stringify({ ok: true });
			}
			return JSON.stringify({ ok: false, reason: 'no_open_picker' });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to get the current active agent from the chat view title.
 */
export function buildGetActiveAgentScript(): string {
	return `(() => {
		try {
			const inputContext = document.querySelector('.native-edit-context[role="textbox"], .interactive-input-editor .native-edit-context, .interactive-input-editor textarea');
			const inputAria = inputContext instanceof Element ? ((inputContext.getAttribute('aria-label') || '').trim()) : '';
			const ariaMatch = inputAria.match(/(?:聊天输入|Chat Input)\s*\(([^)]+)\)/i);
			if (ariaMatch?.[1]) {
				const agent = ariaMatch[1].trim().replace(/^[（(\s]+|[）)\s]+$/g, '');
				const normalizedAgent = agent === '智能体' ? 'Agent' : agent;
				const agentId = normalizedAgent.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]+/g, '_');
				window.__copilotMirrorLastActiveAgent = { id: agentId, name: normalizedAgent };
				return JSON.stringify({ ok: true, result: { agent: normalizedAgent, agentId, source: 'input_aria' } });
			}

			const cached = window.__copilotMirrorLastActiveAgent;
			if (cached && cached.id && cached.name) {
				return JSON.stringify({ ok: true, result: { agent: cached.name, agentId: cached.id, source: 'cache' } });
			}

			const contextList = Array.from(document.querySelectorAll('.context-view .monaco-list'))
				.find(list => list.getAttribute('role') === 'menu' && Array.from(list.querySelectorAll('.monaco-list-row')).some(row => /^(Agent|Ask|Plan)$/i.test(((row.getAttribute('aria-label') || '').split(/[，,]/)[0] || row.textContent || '').replace(/\\s+/g, ' ').trim()) || /配置自定义智能体/.test((row.getAttribute('aria-label') || row.textContent || '').replace(/\\s+/g, ' ').trim())));
			if (contextList) {
				const activeRow = Array.from(contextList.querySelectorAll('.monaco-list-row')).find(row => row.classList.contains('focused') || row.classList.contains('selected') || row.getAttribute('aria-selected') === 'true');
				if (activeRow) {
					const agent = ((activeRow.getAttribute('aria-label') || '').split(/[，,]/)[0] || activeRow.textContent || '').replace(/\\s+/g, ' ').trim();
					const agentId = agent.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]+/g, '_');
					window.__copilotMirrorLastActiveAgent = { id: agentId, name: agent };
					return JSON.stringify({ ok: true, result: { agent, agentId, source: 'context_view' } });
				}
			}

			return JSON.stringify({ ok: false, reason: 'active_agent_not_found' });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}
