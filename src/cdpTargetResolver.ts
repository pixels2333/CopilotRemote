/*---------------------------------------------------------------------------------------------
 *  Copilot Mirror – CDP Target Resolver (Phase 2)
 *  Architecture: nodejs-cdp-bridge.md
 *--------------------------------------------------------------------------------------------*/

export interface ScoredTarget {
	id: string;
	url: string;
	title: string;
	score: number;
	type: string;
	webSocketDebuggerUrl?: string;
}

/**
 * Score a CDP target for likelihood of being the Copilot Chat webview.
 * Higher = more likely.
 *
 * Key heuristics:
 * - vscode-file:// pages are the actual VS Code workbench (strong positive signal)
 * - localhost/127.0.0.1 pages are likely our own Flutter web app, not the real Copilot Chat
 * - "Copilot Mirror" in the title means it's our Flutter app title, not VS Code Copilot
 */
export function scoreTarget(url: string, title: string, type: string): number {
	const lowerUrl = url.toLowerCase();
	const lowerTitle = title.toLowerCase();

	let score = 0;

	// Strong signal: vscode-file:// means this IS the VS Code workbench
	const isVscodeFile = lowerUrl.startsWith('vscode-file://');
	if (isVscodeFile) {
		score += 50;
	}

	// Penalize pages that are just serving our Flutter web app
	// "Copilot Mirror" is the Flutter app's title — not the real Copilot Chat
	const isMirrorAppPage = lowerTitle.includes('copilot mirror') || lowerTitle === 'copilot_mirror';
	if (isMirrorAppPage) {
		score -= 40;
	}

	// localhost/127.0.0.1 pages are served content (Flutter app), not VS Code internals
	const isLocalhost = lowerUrl.includes('localhost') || lowerUrl.includes('127.0.0.1');

	// URL signals (only meaningful for non-localhost, non-mirror pages)
	if (!isLocalhost) {
		if (lowerUrl.includes('github') && lowerUrl.includes('copilot')) {
			score += 100;
		}
		if (lowerUrl.includes('copilot')) {
			score += 80;
		}
		if (lowerUrl.includes('webview') || lowerUrl.includes('vscode-webview')) {
			score += 20;
		}
	}

	// Title signals (skip for pages that are our own Flutter app)
	if (!isMirrorAppPage) {
		if (lowerTitle.includes('copilot') && !isLocalhost) {
			score += 80;
		}
		if (lowerTitle.includes('chat') && !isLocalhost) {
			score += 20;
		}
		if (lowerTitle.includes('visual studio code')) {
			score += 5;
		}
	}

	// Type signal: prefer page or webview
	if (type === 'webview') {
		score += 15;
	}
	if (type === 'page') {
		score += 5;
	}

	return score;
}

/**
 * Fetch the CDP target list from a remote debugging endpoint.
 * Returns raw targets for scoring.
 */
export async function listTargets(host: string, port: number): Promise<ScoredTarget[]> {
	const url = `http://${host}:${port}/json/list`;
	const response = await fetch(url, { signal: AbortSignal.timeout(5000) });

	if (!response.ok) {
		throw new Error(`CDP /json/list returned ${response.status}`);
	}

	const list = await response.json() as Array<{
		id: string;
		url?: string;
		title?: string;
		type?: string;
		webSocketDebuggerUrl?: string;
	}>;

	return list.map(t => ({
		id: t.id ?? '',
		url: t.url ?? '',
		title: t.title ?? '',
		type: t.type ?? '',
		webSocketDebuggerUrl: t.webSocketDebuggerUrl,
		score: scoreTarget(t.url ?? '', t.title ?? '', t.type ?? '')
	}));
}

/**
 * Pick the best Copilot target from the list.
 * Returns undefined if no target scores above 0.
 */
export function pickBestTarget(targets: ScoredTarget[]): ScoredTarget | undefined {
	const pageTargets = targets.filter(t => t.type === 'page' || t.type === 'webview');
	const scored = pageTargets.filter(t => t.score > 0).sort((a, b) => b.score - a.score);
	return scored[0];
}

/**
 * Get the WebSocket debugger URL for a target.
 */
export async function getTargetWebSocketUrl(host: string, port: number, targetId: string): Promise<string | undefined> {
	const url = `http://${host}:${port}/json/list`;
	const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
	if (!response.ok) {
		return undefined;
	}
	const list = await response.json() as Array<{ id: string; webSocketDebuggerUrl?: string }>;
	const entry = list.find(t => t.id === targetId);
	return entry?.webSocketDebuggerUrl;
}

/**
 * Quick DOM probe: evaluate a small expression to check if this page
 * has Copilot Chat characteristics.
 */
export async function probeForCopilot(
	fetchEval: (expression: string) => Promise<unknown>
): Promise<{ isCopilot: boolean; score: number; reason: string }> {
	try {
		const result = await fetchEval(`
			(() => {
				const root = document.querySelector(
					'[data-testid*="chat"], [class*="chat"], [class*="conversation"], .interactive-session'
				);
				const textareas = document.querySelectorAll('textarea');
				const roleTextboxes = document.querySelectorAll('[role="textbox"]');
				const sessionViewer = document.querySelector('[class*="agent-sessions-viewer"]');
				const chatTitle = document.querySelector('[class*="chat-view-title-label-container"], [class*="chat-title"]');
				const interactiveList = document.querySelector('[class*="interactive-list"], .interactive-session');
				return {
					hasChatRoot: !!root,
					hasTextarea: textareas.length > 0,
					hasRoleTextbox: roleTextboxes.length > 0,
					hasCopilotInClass: !!(document.body.className || '').toLowerCase().includes('copilot'),
					hasSessionViewer: !!sessionViewer,
					hasChatTitle: !!chatTitle,
					hasInteractiveList: !!interactiveList,
					fullText: (document.body.innerText || '').slice(0, 200)
				};
			})()
		`) as {
			hasChatRoot: boolean;
			hasTextarea: boolean;
			hasRoleTextbox: boolean;
			hasCopilotInClass: boolean;
			hasSessionViewer: boolean;
			hasChatTitle: boolean;
			hasInteractiveList: boolean;
			fullText: string;
		};

		let score = 0;
		const signals: string[] = [];

		if (result.hasChatRoot) { score += 50; signals.push('chat_root'); }
		if (result.hasTextarea) { score += 20; signals.push('textarea'); }
		if (result.hasRoleTextbox) { score += 15; signals.push('role_textbox'); }
		if (result.hasCopilotInClass) { score += 30; signals.push('copilot_class'); }
		if (result.hasSessionViewer) { score += 45; signals.push('session_viewer'); }
		if (result.hasChatTitle) { score += 35; signals.push('chat_title'); }
		if (result.hasInteractiveList) { score += 20; signals.push('interactive_list'); }
		if (result.fullText.toLowerCase().includes('copilot')) { score += 40; signals.push('copilot_text'); }
		if (result.fullText.toLowerCase().includes('chat')) { score += 10; signals.push('chat_text'); }

		return {
			isCopilot: score >= 50,
			score,
			reason: signals.join(', ') || 'no_copilot_signals'
		};
	} catch {
		return { isCopilot: false, score: 0, reason: 'eval_error' };
	}
}
