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
(() => {
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

	/* ── Find chat panel root ── */
	function findList() {
		const aux = document.getElementById('workbench.parts.auxiliarybar');
		if (!aux) return null;
		return aux.querySelector('.monaco-list');
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
			const body = el.querySelector('.chat-used-context-list') || el;
			const title = el.querySelector('.chat-thinking-title-detail-text');
			const c = textOf(body);
			if (c) { blocks.push({ id: stableId('th_', msgId + c.slice(0,32)), type: 'thinking', status: 'completed', format: 'plain', content: c, visibility: 'collapsed', title: title ? textOf(title) : 'Thinking' }); specializedCount++; }
		}

		// Tool wrappers
		for (const el of Array.from(contents.querySelectorAll('.chat-thinking-tool-wrapper'))) {
			const c = textOf(el);
			if (c) {
				const name = c.split('\\n')[0] || 'Tool';
				blocks.push({
					id: stableId('tl_', msgId + c.slice(0,32)), type: 'tool_call', status: 'completed',
					toolCallId: stableId('tc_', c.slice(0,64)), toolName: name.split(' ')[0],
					displayName: name, state: c.toLowerCase().includes('failed') ? 'failed' : 'succeeded', summary: c
				});
				specializedCount++;
			}
		}

		// Markdown content (text + code)
		for (const el of Array.from(contents.querySelectorAll('.chat-markdown-part.rendered-markdown, .rendered-markdown'))) {
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

		// Fallback
		if (blocks.length === 0) {
			const t = textOf(contents); if (t) blocks.push({ id: stableId('tx_', t.slice(0,64)), type: 'text', status: 'completed', format: 'markdown', content: t });
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
					const mid = stableId('msg_' + role, i + ':' + role + ':' + t.slice(0,80));
					const now = new Date().toISOString();
					return { id: mid, role, status: 'completed', createdAt: now, updatedAt: now, blocks: extractBlocks(row, mid), metadata: { domIndex: i } };
				});
			}
		}

		// 🔻 Broader fallback: no monaco-list found, use findFallbackRows
		if (!window.__copilotMirrorState.fineMode) {
			const fallbackRows = findFallbackRows();
			if (fallbackRows.length > 0) {
				return fallbackRows.map((row, i) => {
					const t = textOf(row);
					const mid = stableId('msg_fb_', i + ':' + t.slice(0,80));
					const now = new Date().toISOString();
					return { id: mid, role: 'assistant', status: 'completed', createdAt: now, updatedAt: now, blocks: [{ id: stableId('tx_', t.slice(0,64)), type: 'text', status: 'completed', format: 'markdown', content: t, _fallback: true }], metadata: { domIndex: i, _fallback: true } };
				});
			}
		}

		return [];
	}

	/* ── Snapshot ── */
	function flushSnapshot() {
		const messages = extractAll();
		emit({ kind: 'snapshot', messages });
		for (const m of messages) for (const b of m.blocks) {
			if (typeof b.content === 'string') window.__copilotMirrorState.blockContent.set(b.id, b.content);
		}
	}

	/* ── Delta ── */
	function flushDelta() {
		const messages = extractAll();
		const known = window.__copilotMirrorState.messageFingerprints;

		for (const m of messages) {
			if (!known.has(m.id)) { known.set(m.id, true); emit({ kind: 'message', message: { ...m, blocks: [] } }); }
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

	/* ── Init ── */
	const list = findList();
	if (!list) return { ok: false, reason: 'monaco_list_not_found' };
	flushSnapshot();

	let scheduled = false;
	const schedule = () => {
		if (scheduled) return;
		scheduled = true;
		requestAnimationFrame(() => { scheduled = false; flushDelta(); });
	};

	const obsTarget = list.closest('.auxiliarybar') || document.getElementById('workbench.parts.auxiliarybar') || list;
	const observer = new MutationObserver(schedule);
	observer.observe(obsTarget, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['class', 'style'] });

	setInterval(() => { flushDelta(); emit({ kind: 'heartbeat' }); }, ${options.heartbeatMs});

	return { ok: true };
})();
	`.trim();
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
	return `(() => {
		const sel = ['button[aria-label*="stop" i]', 'button[aria-label*="cancel" i]', '.chat-stop-button', '[aria-label*="Stop Generation"]'];
		for (const s of sel) { const el = document.querySelector(s); if (el instanceof HTMLElement) { el.click(); return JSON.stringify({ ok: true }); } }
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
			const aux = document.querySelector('#workbench.parts.auxiliarybar') || document.querySelector('[id*="auxiliarybar"]');
			if (!aux) return JSON.stringify({ ok: false, reason: 'no_auxiliary_bar' });

			// Find the session list monaco-list (not the messages list)
			const lists = Array.from(aux.querySelectorAll('.monaco-list'));
			const sessionList = lists.find(l => l.classList.contains('selection-single'));
			if (!sessionList) return JSON.stringify({ ok: false, reason: 'no_session_list' });

			const rows = Array.from(sessionList.querySelectorAll('.monaco-list-row'));
			const sessions = rows.map((row, index) => {
				const titleEl = row.querySelector('.monaco-highlighted-label');
				const title = titleEl ? (titleEl.textContent || '').trim() : ('会话 ' + (index + 1));
				const active = row.classList.contains('focused') || row.classList.contains('selected');
				const sessionId = row.id || 'session_' + index + '_' + title.replace(/[^a-zA-Z0-9\\u4e00-\\u9fff]/g, '_').slice(0, 32);
				const timeEl = row.querySelector('.agent-session-status-time');
				const updatedAt = timeEl ? (timeEl.textContent || '').trim() : undefined;
				const descEl = row.querySelector('.agent-session-description');
				const preview = descEl ? (descEl.textContent || '').trim().slice(0, 60) : undefined;
				return { sessionId, title, index, active, updatedAt, preview, source: 'dom' };
			});

			// Get active session from chat view title
			let activeSessionId = sessions.find(s => s.active)?.sessionId;
			if (!activeSessionId) {
				const activeTitleEl = document.querySelector('.action-label.chat-view-title-label-container');
				if (activeTitleEl) {
					const activeTitle = (activeTitleEl.textContent || '').trim();
					const found = sessions.find(s => s.title === activeTitle);
					if (found) activeSessionId = found.sessionId;
				}
			}
			if (!activeSessionId && sessions.length > 0) {
				activeSessionId = sessions[0].sessionId;
			}

			return JSON.stringify({ ok: true, result: { sessions, activeSessionId } });
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
			const aux = document.querySelector('#workbench.parts.auxiliarybar') || document.querySelector('[id*="auxiliarybar"]');
			if (!aux) return JSON.stringify({ ok: false, reason: 'no_auxiliary_bar' });

			const lists = Array.from(aux.querySelectorAll('.monaco-list'));
			const sessionList = lists.find(l => l.classList.contains('selection-single'));
			if (!sessionList) return JSON.stringify({ ok: false, reason: 'no_session_list' });

			const rows = Array.from(sessionList.querySelectorAll('.monaco-list-row'));
			const targetRow = rows[${idx}];
			if (!targetRow) return JSON.stringify({ ok: false, reason: 'session_index_out_of_range', index: ${idx}, count: rows.length });

			// Click the session row
			if (targetRow instanceof HTMLElement) {
				targetRow.click();
				// Also try to focus on the inner clickable element
				const inner = targetRow.querySelector('[role="button"], .monaco-highlighted-label');
				if (inner instanceof HTMLElement) inner.click();
				return JSON.stringify({ ok: true, sessionId: targetRow.id || 'session_${idx}', title: (targetRow.querySelector('.monaco-highlighted-label')?.textContent || '').trim() });
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
 * The agent picker is accessed by clicking the chat view title label
 * (aria-label="选取代理会话"), which opens a quick-input list.
 */
export function buildAgentListScript(): string {
	return `(() => {
		try {
			// Click the agent picker button
			const pickerBtn = document.querySelector('.action-label.chat-view-title-label-container');
			if (!pickerBtn) return JSON.stringify({ ok: false, reason: 'no_agent_picker_button' });
			if (pickerBtn instanceof HTMLElement) {
				pickerBtn.click();
			}
			// Wait for quick input widget to open (will be scanned after delay via agentList response)
			return JSON.stringify({ ok: true, action: 'opened_picker' });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}

/**
 * Build script to scan the agent list from the quick-input-widget.
 */
export function buildScanAgentListScript(): string {
	return `(() => {
		try {
			// Check quick-input-widget which is the standard VS Code agent picker
			const qiWidget = document.querySelector('.quick-input-widget:not([aria-hidden="true"])');
			if (!qiWidget) return JSON.stringify({ ok: false, reason: 'no_quick_input_widget' });

			const list = qiWidget.querySelector('.monaco-list');
			if (!list) return JSON.stringify({ ok: false, reason: 'no_list_in_picker' });

			const rows = Array.from(list.querySelectorAll('.monaco-list-row'));
			const agents = rows.map((row, i) => {
				const labelEl = row.querySelector('.monaco-highlighted-label');
				const label = labelEl ? (labelEl.textContent || '').trim() : (row.textContent || '').trim().split('\\n')[0];
				const active = row.classList.contains('focused') || row.classList.contains('selected');
				const descEl = row.querySelector('.monaco-icon-label-description-row');
				const description = descEl ? (descEl.textContent || '').trim() : '';
				return {
					id: row.id || 'agent_' + i,
					name: label,
					description,
					index: i,
					active,
					source: 'dom'
				};
			});

			return JSON.stringify({ ok: true, result: { agents } });
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
			const qiWidget = document.querySelector('.quick-input-widget:not([aria-hidden="true"])');
			if (!qiWidget) return JSON.stringify({ ok: false, reason: 'no_quick_input_widget' });

			const list = qiWidget.querySelector('.monaco-list');
			if (!list) return JSON.stringify({ ok: false, reason: 'no_list_in_picker' });

			const rows = Array.from(list.querySelectorAll('.monaco-list-row'));
			const target = rows[${Math.floor(index)}];
			if (!target) return JSON.stringify({ ok: false, reason: 'index_out_of_range', count: rows.length });
			if (target instanceof HTMLElement) {
				target.click();
				target.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }));
			}
			return JSON.stringify({ ok: true });
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
			if (qiWidget) {
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
			const el = document.querySelector('.action-label.chat-view-title-label-container');
			if (!el) return JSON.stringify({ ok: false, reason: 'no_title' });
			const text = (el.textContent || '').trim();
			// The label may contain session title or agent name - extract agent info
			// Also check the chat input placeholder for agent hints
			const chatCtrl = document.querySelector('.chat-controls-container');
			const input = chatCtrl ? chatCtrl.querySelector('[aria-label]') : null;
			const ariaLabel = input ? input.getAttribute('aria-label') || '' : '';
			// ariaLabel contains format: "聊天输入 (智能体)，编辑工作区中的文件。，AgentName。..."
			let agentMatch = ariaLabel.match(/，([^，。]+)。/);
			let agent = agentMatch ? agentMatch[1].trim() : text;
			return JSON.stringify({ ok: true, result: { agent, title: text, rawAria: ariaLabel } });
		} catch (e) {
			return JSON.stringify({ ok: false, reason: e instanceof Error ? e.message : String(e) });
		}
	})();
	`.trim();
}
