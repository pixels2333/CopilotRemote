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
}

/**
 * Score a CDP target for likelihood of being the Copilot Chat webview.
 * Higher = more likely.
 */
export function scoreTarget(url: string, title: string, type: string): number {
	const lowerUrl = url.toLowerCase();
	const lowerTitle = title.toLowerCase();

	let score = 0;

	// URL signals
	if (lowerUrl.includes('github') && lowerUrl.includes('copilot')) {
		score += 100;
	}
	if (lowerUrl.includes('copilot')) {
		score += 80;
	}
	if (lowerUrl.includes('webview') || lowerUrl.includes('vscode-webview')) {
		score += 20;
	}

	// Title signals
	if (lowerTitle.includes('copilot')) {
		score += 80;
	}
	if (lowerTitle.includes('chat')) {
		score += 20;
	}
	if (lowerTitle.includes('visual studio code')) {
		score += 5;
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
	}>;

	return list.map(t => ({
		id: t.id ?? '',
		url: t.url ?? '',
		title: t.title ?? '',
		type: t.type ?? '',
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
				return {
					hasChatRoot: !!root,
					hasTextarea: textareas.length > 0,
					hasRoleTextbox: roleTextboxes.length > 0,
					hasCopilotInClass: !!(document.body.className || '').toLowerCase().includes('copilot'),
					fullText: (document.body.innerText || '').slice(0, 200)
				};
			})()
		`) as {
			hasChatRoot: boolean;
			hasTextarea: boolean;
			hasRoleTextbox: boolean;
			hasCopilotInClass: boolean;
			fullText: string;
		};

		let score = 0;
		const signals: string[] = [];

		if (result.hasChatRoot) { score += 50; signals.push('chat_root'); }
		if (result.hasTextarea) { score += 20; signals.push('textarea'); }
		if (result.hasRoleTextbox) { score += 15; signals.push('role_textbox'); }
		if (result.hasCopilotInClass) { score += 30; signals.push('copilot_class'); }
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
