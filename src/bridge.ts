/*---------------------------------------------------------------------------------------------
 *  Copilot Mirror – CDP Bridge main entry (Phase 2)
 *  Architecture: copilot-mirror-architecture.md, nodejs-cdp-bridge.md
 *
 *  Orchestrates:
 *    - CDP target discovery & connection
 *    - DOM observer script injection
 *    - Delta processing & broadcast via WebSocket
 *    - Reverse command handling (sendMessage, stopGeneration, focusInput)
 *    - Automatic reconnection on target loss or page refresh
 *--------------------------------------------------------------------------------------------*/

import CDP from 'chrome-remote-interface';
import { WsGateway } from './wsGateway.js';
import {
	type BridgeDomEvent,
	type BridgeOptions,
	type MirrorMessage,
	type MirrorChatSessionItem,
	DEFAULT_BRIDGE_OPTIONS
} from './protocol.js';
import { listTargets, pickBestTarget, probeForCopilot } from './cdpTargetResolver.js';
import {
	buildObserverScript,
	buildSendPromptScript,
	buildFocusInputScript,
	buildStopGenerationScript,
	buildSessionListScript,
	buildSwitchSessionScript,
	buildNewSessionScript,
	buildGetActiveSessionScript,
	buildSlashListScript,
	buildScanSuggestWidgetScript,
	buildRestoreInputScript,
	buildApplySlashScript,
	buildAgentListScript,
	buildScanAgentListScript,
	buildCloseAgentPickerScript,
	buildSwitchAgentScript,
	buildGetActiveAgentScript
} from './domInjection.js';

type Client = CDP.Client;
type Target = CDP.Target;

/** The Bridge's own internal state snapshot (for event dedup & delta) */
interface MirrorSnapshot {
	messages: MirrorMessage[];
	blockContents: Map<string, string>;
}

export class CopilotMirrorBridge {
	private seq = 0;
	private wsGateway: WsGateway;
	private cdpClient: Client | undefined;
	private currentTarget: Target | undefined;
	private targetScanTimer: ReturnType<typeof setInterval> | undefined;
	private heartbeatTimer: ReturnType<typeof setInterval> | undefined;
	private reconnecting = false;
	private injected = false;

	private snapshot: MirrorSnapshot = {
		messages: [],
		blockContents: new Map()
	};

	/** Track last active session for auto-detect switch */
	private lastActiveSessionId: string | undefined;
	private lastSessionsFingerprint: string | undefined;
	private switchingSession = false;
	private sessionScanTimer: ReturnType<typeof setInterval> | undefined;

	/** Track last active agent */
	private lastActiveAgentId: string | undefined;
	private lastAgentsFingerprint: string | undefined;
	private switchingAgent = false;
	private agentScanTimer: ReturnType<typeof setInterval> | undefined;

	constructor(private options: BridgeOptions = DEFAULT_BRIDGE_OPTIONS) {
		this.wsGateway = new WsGateway(options);
		this.wireGatewayHandlers();
	}

	async start(): Promise<void> {
		this.wsGateway.start();
		await this.connectToCopilotTarget();
		this.targetScanTimer = setInterval(() => {
			void this.ensureCdpConnected();
		}, this.options.targetScanIntervalMs);
		this.heartbeatTimer = setInterval(() => {
			this.broadcastStatus();
		}, this.options.heartbeatMs);
		// Periodic session list scan
		this.sessionScanTimer = setInterval(() => {
			void this.scanSessions();
		}, this.options.heartbeatMs * 2);
		// Periodic agent list scan
		this.agentScanTimer = setInterval(() => {
			void this.scanAgents();
		}, this.options.heartbeatMs * 3);
	}

	async stop(): Promise<void> {
		clearInterval(this.targetScanTimer);
		clearInterval(this.heartbeatTimer);
		clearInterval(this.sessionScanTimer);
		clearInterval(this.agentScanTimer);
		this.wsGateway.stop();
		if (this.cdpClient) {
			await this.cdpClient.close();
		}
	}

	// ── CDP connection ───────────────────────────────────────────

	private async ensureCdpConnected(): Promise<void> {
		if (this.reconnecting) return;
		if (this.cdpClient && this.currentTarget) return;

		this.reconnecting = true;
		try {
			await this.connectToCopilotTarget();
		} catch {
			this.broadcastStatus('Reconnect failed.');
		} finally {
			this.reconnecting = false;
		}
	}

	private async connectToCopilotTarget(): Promise<void> {
		const targets = await listTargets(this.options.cdpHost, this.options.cdpPort);
		const candidate = pickBestTarget(targets);

		if (!candidate) {
			this.currentTarget = undefined;
			this.broadcastStatus('Copilot target not found.');
			return;
		}

		// Already connected to the same target with injected observer
		if (this.currentTarget?.id === candidate.id && this.cdpClient && this.injected) {
			return;
		}

		// Close previous session
		if (this.cdpClient) {
			await this.cdpClient.close().catch(() => undefined);
			this.cdpClient = undefined;
			this.injected = false;
		}

		this.currentTarget = {
			id: candidate.id,
			url: candidate.url,
			title: candidate.title,
			type: candidate.type
		} as Target;

		const client = await CDP({
			host: this.options.cdpHost,
			port: this.options.cdpPort,
			target: this.currentTarget
		});

		this.cdpClient = client;

		client.on('disconnect', () => {
			this.cdpClient = undefined;
			this.currentTarget = undefined;
			this.injected = false;
			this.broadcastStatus('CDP disconnected.');
		});

		await client.Runtime.enable();
		await client.Page.enable().catch(() => undefined);

		// Binding callback for structured events
		client.Runtime.bindingCalled(params => {
			if (params.name !== '__copilotMirrorEmit') return;
			this.handleInjectedPayload(params.payload);
		});

		// Fallback: console.log capture
		client.Runtime.consoleAPICalled(params => {
			const first = params.args[0];
			if (first?.value && typeof first.value === 'string' && first.value.startsWith('[CopilotMirror]')) {
				this.handleInjectedPayload(first.value.slice('[CopilotMirror]'.length));
			}
		});

		// Re-inject on page load
		client.Page.loadEventFired(() => {
			this.injected = false;
			setTimeout(() => void this.injectObserverScript(), 800);
		});

		// Probe to confirm this is the Copilot page
		const probe = await probeForCopilot(async expr => {
			const r = await client.Runtime.evaluate({ expression: expr, awaitPromise: true, returnByValue: true });
			return r.result.value;
		});

		if (!probe.isCopilot) {
			await client.close().catch(() => undefined);
			this.cdpClient = undefined;
			this.currentTarget = undefined;
			this.broadcastStatus(`Probe failed (${probe.reason}), trying next target.`);
			return;
		}

		await client.Runtime.addBinding({ name: '__copilotMirrorEmit' }).catch(() => undefined);
		await this.injectObserverScript();
		this.broadcastStatus(`CDP connected: ${candidate.title}`);
	}

	private async injectObserverScript(): Promise<void> {
		const client = this.requireCdpClient();
		const script = buildObserverScript(this.options);

		const result = await client.Runtime.evaluate({
			expression: script,
			awaitPromise: true,
			returnByValue: true
		});

		const value = result.result.value as { ok?: boolean; reason?: string } | undefined;
		if (!value?.ok) {
			this.injected = false;
			this.broadcastStatus(`Observer injection failed: ${value?.reason ?? 'unknown'}`);
			return;
		}

		this.injected = true;
	}

	// ── Handle page events ──────────────────────────────────────

	private handleInjectedPayload(raw: string): void {
		let event: BridgeDomEvent;
		try {
			event = JSON.parse(raw) as BridgeDomEvent;
		} catch {
			return;
		}

		switch (event.kind) {
			case 'snapshot':
				this.handleSnapshot(event);
				break;
			case 'message':
				if (event.message) {
					this.snapshot.messages.push(event.message);
					this.wsGateway.broadcast('message.start', { message: event.message });
				}
				break;
			case 'block':
				if (event.messageId && event.block) {
					this.wsGateway.broadcast('block.start', {
						messageId: event.messageId,
						block: event.block
					});
				}
				break;
			case 'delta':
				this.handleDelta(event);
				break;
			case 'blockUpdate':
				if (event.messageId && event.blockId && event.patch) {
					this.wsGateway.broadcast('block.update', {
						messageId: event.messageId,
						blockId: event.blockId,
						patch: event.patch
					});
				}
				break;
			case 'blockEnd':
				if (event.messageId && event.blockId) {
					this.wsGateway.broadcast('block.end', {
						messageId: event.messageId,
						blockId: event.blockId,
						status: event.status ?? 'completed',
						finalLength: event.finalLength
					});
				}
				break;
			case 'messageEnd':
				if (event.messageId) {
					this.wsGateway.broadcast('message.end', {
						messageId: event.messageId,
						status: event.status ?? 'completed'
					});
				}
				break;
			case 'heartbeat':
				break;
		}
	}

	private handleSnapshot(event: BridgeDomEvent): void {
		const messages = event.messages ?? [];
		this.snapshot.messages = messages;
		this.snapshot.blockContents.clear();

		for (const message of messages) {
			for (const block of message.blocks) {
				if (typeof block.content === 'string') {
					this.snapshot.blockContents.set(block.id, block.content);
				}
			}
		}

		this.wsGateway.broadcast('session.snapshot', {
			mode: 'full',
			cursor: { seq: this.seq, snapshotVersion: Date.now() },
			session: {
				sessionId: this.options.sessionId,
				title: 'Copilot Chat',
				workspace: null,
				createdAt: new Date().toISOString(),
				updatedAt: new Date().toISOString()
			},
			messages
		});
	}

	private handleDelta(event: BridgeDomEvent): void {
		if (!event.messageId || !event.blockId || !event.blockType) return;

		const offset = event.offset ?? 0;
		const chunk = event.chunk ?? '';
		const previous = this.snapshot.blockContents.get(event.blockId) ?? '';

		if (offset === previous.length) {
			this.snapshot.blockContents.set(event.blockId, previous + chunk);
		} else if (event.format !== 'json') {
			this.snapshot.blockContents.set(event.blockId, chunk);
		}

		this.wsGateway.broadcast('block.delta', {
			messageId: event.messageId,
			blockId: event.blockId,
			blockType: event.blockType,
			op: offset === previous.length ? 'append' : 'replace',
			offset,
			chunk,
			format: event.format ?? 'markdown',
			done: false
		});
	}

	// ── Reverse command handlers ─────────────────────────────────

	private wireGatewayHandlers(): void {
		this.wsGateway.onSendMessage = async (payload, requestId) => {
			await this.sendPromptToCopilot(payload.text, payload.options?.submit ?? true);
		};

		this.wsGateway.onStopGeneration = async () => {
			await this.evaluateInCopilotPage(buildStopGenerationScript());
		};

		this.wsGateway.onFocusInput = async () => {
			await this.evaluateInCopilotPage(buildFocusInputScript());
		};

		this.wsGateway.onOpenArtifact = async (artifactId) => {
			// Try to click the artifact via CDP
			const client = this.requireCdpClient();
			const result = await client.Runtime.evaluate({
				expression: `
					(() => {
						// Search for artifact element containing this ID
						const el = document.querySelector('[id*="${artifactId}" i], [data-id="${artifactId}"], [data-artifact-id="${artifactId}"]');
						if (el instanceof HTMLElement) { el.click(); return { ok: true }; }
						// Broader: find elements whose text or class suggests this artifact
						const all = document.querySelectorAll('[class*="artifact"], [class*="preview"]');
						for (const a of all) {
							if ((a.textContent || '').includes('${artifactId.replace(/'/g, "\\'")}')) {
								if (a instanceof HTMLElement) { a.click(); return { ok: true }; }
							}
						}
						return { ok: false, reason: 'artifact_element_not_found' };
					})()
				`,
				awaitPromise: true,
				returnByValue: true
			});
			const value = result.result.value as { ok?: boolean; reason?: string } | undefined;
			if (!value?.ok) {
				throw new Error(value?.reason ?? 'artifact not found in page DOM');
			}
		};

		// ── Session handlers ──
		this.wsGateway.onListSessions = async (requestId) => {
			await this.handleListSessionsCommand(requestId);
		};

		this.wsGateway.onSwitchSession = async (sessionId, index, title, requestId) => {
			await this.handleSwitchSessionCommand(sessionId, index, title, requestId);
		};

		this.wsGateway.onNewSession = async (requestId) => {
			await this.handleNewSessionCommand(requestId);
		};

		// ── Slash command handlers ──
		this.wsGateway.onListSlashCommands = async (query, requestId) => {
			await this.handleListSlashCommandsCommand(query, requestId);
		};

		this.wsGateway.onApplySlashCommand = async (index, insertOnly, requestId) => {
			await this.handleApplySlashCommand(index, insertOnly, requestId);
		};

		// ── Agent handlers ──
		this.wsGateway.onListAgents = async (requestId) => {
			await this.handleListAgentsCommand(requestId);
		};

		this.wsGateway.onSwitchAgent = async (agentId, index, name, requestId) => {
			await this.handleSwitchAgentCommand(agentId, index, name, requestId);
		};
	}

	async sendPromptToCopilot(text: string, submit = true): Promise<void> {
		const client = this.requireCdpClient();
		const script = buildSendPromptScript(text, submit);

		const result = await client.Runtime.evaluate({
			expression: script,
			awaitPromise: true,
			returnByValue: true
		});

		const value = result.result.value as { ok?: boolean; reason?: string } | undefined;
		if (!value?.ok) {
			throw new Error(`sendPrompt failed: ${value?.reason ?? 'unknown'}`);
		}
	}

	// ── Status broadcast ────────────────────────────────────────

	private broadcastStatus(message?: string): void {
		this.wsGateway.broadcast('server.status', {
			cdpConnected: Boolean(this.cdpClient),
			wsClients: this.wsGateway.clientCount,
			message: message ?? (this.cdpClient ? 'CDP connected.' : 'CDP disconnected.')
		});
	}

	// ── Helpers ─────────────────────────────────────────────────

	private async evaluateInCopilotPage(expression: string): Promise<void> {
		const client = this.requireCdpClient();
		await client.Runtime.evaluate({
			expression,
			awaitPromise: true,
			returnByValue: true
		});
	}

	private requireCdpClient(): Client {
		if (!this.cdpClient) {
			throw new Error('CDP client is not connected.');
		}
		return this.cdpClient;
	}

	// ── Session management ──────────────────────────────────────

	private async evaluateWithResult<T = unknown>(expression: string): Promise<{ ok: boolean; reason?: string; result?: T }> {
		const client = this.requireCdpClient();
		const r = await client.Runtime.evaluate({
			expression,
			awaitPromise: true,
			returnByValue: true
		});
		const val = r.result.value as ({ ok: boolean; reason?: string } & Record<string, unknown>) | undefined;
		if (!val) return { ok: false, reason: 'no_result' };
		const { ok, reason, ...rest } = val;
		return { ok: !!ok, reason: reason as string | undefined, result: rest as unknown as T };
	}

	private async scanSessions(): Promise<void> {
		if (!this.cdpClient || !this.injected || this.switchingSession) return;
		try {
			const result = await this.evaluateWithResult<{ sessions: MirrorChatSessionItem[]; activeSessionId?: string }>(buildSessionListScript());
			if (!result.ok || !result.result) return;

			const { sessions, activeSessionId } = result.result;

			// Broadcast session list periodically
			this.wsGateway.broadcast('session.list', { sessions, activeSessionId } as Record<string, unknown>);

			// Detect active session change → session switch
			if (activeSessionId && activeSessionId !== this.lastActiveSessionId) {
				const fromSessionId = this.lastActiveSessionId;
				this.lastActiveSessionId = activeSessionId;

				// Don't trigger on first detection
				if (fromSessionId) {
					this.switchingSession = true;
					// Clear message state
					this.snapshot.messages = [];
					this.snapshot.blockContents.clear();

					this.wsGateway.broadcast('session.switched', {
						fromSessionId,
						toSessionId: activeSessionId,
						reason: 'dom-detected'
					} as Record<string, unknown>);

					// Wait for DOM to settle, then re-snapshot
					setTimeout(() => {
						void this.forceSnapshot();
						this.switchingSession = false;
					}, 600);
				} else {
					this.lastActiveSessionId = activeSessionId;
				}
			}
		} catch {
			// Silently ignore scan errors
		}
	}

	private async forceSnapshot(): Promise<void> {
		if (!this.cdpClient) return;
		try {
			await this.evaluateInCopilotPage(`
				window.__copilotMirrorState.messageFingerprints = new Map();
				window.__copilotMirrorState.blockContent = new Map();
			`);
			// Re-run flushSnapshot
			await this.evaluateInCopilotPage(`
				(() => {
					if (typeof flushSnapshot === 'function') flushSnapshot();
					else {
						// Re-inject observer to get fresh snapshot
						const list = document.querySelector('[id*="auxiliarybar"] .monaco-list');
						if (list) {
							const obs = new MutationObserver(() => {});
							obs.disconnect();
						}
					}
				})()
			`);
		} catch {
			// Silently attempt
		}
	}

	private async handleListSessionsCommand(requestId?: string): Promise<void> {
		const result = await this.evaluateWithResult<{ sessions: MirrorChatSessionItem[]; activeSessionId?: string }>(buildSessionListScript());
		if (!result.ok || !result.result) {
			throw new Error(result.reason || 'Failed to list sessions');
		}
		this.wsGateway.broadcast('session.list', result.result as Record<string, unknown>, undefined, requestId);
	}

	private async handleSwitchSessionCommand(sessionId?: string, index?: number, title?: string, requestId?: string): Promise<void> {
		if (!this.cdpClient) throw new Error('CDP not connected');

		// If sessionId or title provided, first scan sessions to find the index
		let targetIndex = index;
		if (targetIndex === undefined && (sessionId || title)) {
			const listResult = await this.evaluateWithResult<{ sessions: MirrorChatSessionItem[]; activeSessionId?: string }>(buildSessionListScript());
			if (listResult.ok && listResult.result) {
				const found = listResult.result.sessions.find(s =>
					s.sessionId === sessionId || s.title === title
				);
				if (found) targetIndex = found.index;
			}
		}

		if (targetIndex === undefined) {
			throw new Error('Could not determine session index');
		}

		const script = buildSwitchSessionScript(targetIndex);
		const result = await this.evaluateWithResult(buildSwitchSessionScript(targetIndex));
		if (!result.ok) {
			throw new Error(result.reason || 'Failed to switch session');
		}

		// Wait for DOM to update, then re-snapshot
		this.switchingSession = true;
		await new Promise(resolve => setTimeout(resolve, 800));

		// Re-scan to update active session
		const rescan = await this.evaluateWithResult<{ sessions: MirrorChatSessionItem[]; activeSessionId?: string }>(buildSessionListScript());
		if (rescan.ok && rescan.result) {
			const newActive = rescan.result.activeSessionId;
			const fromSessionId = this.lastActiveSessionId;
			this.lastActiveSessionId = newActive;

			this.snapshot.messages = [];
			this.snapshot.blockContents.clear();

			this.wsGateway.broadcast('session.switched', {
				fromSessionId,
				toSessionId: newActive,
				reason: 'client-command'
			} as Record<string, unknown>, undefined, requestId);
		}

		// Force fresh snapshot
		setTimeout(() => void this.forceSnapshot(), 300);
		setTimeout(() => { this.switchingSession = false; }, 1500);
	}

	private async handleNewSessionCommand(requestId?: string): Promise<void> {
		const result = await this.evaluateWithResult(buildNewSessionScript());
		if (!result.ok) {
			throw new Error(result.reason || 'Failed to create new session');
		}
	}

	// ── Slash command methods ─────────────────────────────────────

	private async handleListSlashCommandsCommand(query?: string, requestId?: string): Promise<void> {
		// Step 1: Type / to trigger suggest widget
		const triggerResult = await this.evaluateWithResult(buildSlashListScript(query));
		if (!triggerResult.ok) {
			// If can't type, try just scanning any visible suggest widget
			const scanResult = await this.evaluateWithResult<{ items: import('./protocol.js').MirrorSlashCommandItem[] }>(buildScanSuggestWidgetScript());
			if (scanResult.ok && scanResult.result) {
				this.wsGateway.broadcast('slash.list', { items: scanResult.result.items, query } as Record<string, unknown>, undefined, requestId);
				return;
			}
			throw new Error(triggerResult.reason || 'Failed to trigger slash menu');
		}

		// Step 2: Wait for suggest widget to appear
		await new Promise(resolve => setTimeout(resolve, 600));

		// Step 3: Scan the suggest widget items
		const scanResult = await this.evaluateWithResult(buildScanSuggestWidgetScript());

		// Step 4: Restore the input (clear the / we typed)
		await this.evaluateWithResult(buildRestoreInputScript()).catch(() => undefined);

		if (scanResult.ok && scanResult.result) {
			this.wsGateway.broadcast('slash.list', { items: (scanResult.result as Record<string, unknown>)['items'], query } as Record<string, unknown>, undefined, requestId);
		} else {
			this.wsGateway.broadcast('slash.list', { items: [], query } as Record<string, unknown>, undefined, requestId);
		}
	}

	private async handleApplySlashCommand(index: number, insertOnly: boolean, requestId?: string): Promise<void> {
		// Step 1: Type / to trigger suggest widget (if not already open)
		const triggerResult = await this.evaluateWithResult(buildSlashListScript());
		if (!triggerResult.ok) {
			throw new Error(triggerResult.reason || 'Failed to trigger slash menu');
		}

		// Step 2: Wait for suggest widget
		await new Promise(resolve => setTimeout(resolve, 400));

		// Step 3: Apply the command
		const applyResult = await this.evaluateWithResult(buildApplySlashScript(index, insertOnly));
		if (!applyResult.ok) {
			throw new Error(applyResult.reason || 'Failed to apply slash command');
		}
	}

	// ── Agent methods ─────────────────────────────────────────────

	private async scanAgents(): Promise<void> {
		if (!this.cdpClient || !this.injected || this.switchingAgent) return;
		try {
			// Use ariaLabel from chat input to detect agent changes (non-invasive)
			const result = await this.evaluateWithResult<{ agent: string; title: string; rawAria: string }>(buildGetActiveAgentScript());
			if (!result.ok || !result.result) return;

			const { agent } = result.result;
			const agentId = agent.toLowerCase().replace(/[^a-z0-9]/g, '_');

			// Detect active agent change
			if (agentId && agentId !== this.lastActiveAgentId) {
				const fromAgentId = this.lastActiveAgentId;
				this.lastActiveAgentId = agentId;

				if (fromAgentId) {
					this.wsGateway.broadcast('agent.switched', {
						fromAgentId,
						toAgentId: agentId,
						reason: 'dom'
					} as Record<string, unknown>);
				}
			}
		} catch {
			// Silently ignore scan errors
		}
	}

	private async handleListAgentsCommand(requestId?: string): Promise<void> {
		// Step 1: Open agent picker by clicking title
		const openResult = await this.evaluateWithResult(buildAgentListScript());
		if (!openResult.ok) {
			throw new Error(openResult.reason || 'Failed to open agent picker');
		}

		// Step 2: Wait for quick input widget
		await new Promise(resolve => setTimeout(resolve, 500));

		// Step 3: Scan agents
		const scanResult = await this.evaluateWithResult(buildScanAgentListScript());

		// Step 4: Close the picker
		await this.evaluateWithResult(buildCloseAgentPickerScript()).catch(() => undefined);

		if (scanResult.ok && scanResult.result) {
			const activeAgent = this.lastActiveAgentId;
			const agentsList = (scanResult.result as Record<string, unknown>)['agents'] as Record<string, unknown>[];
			this.wsGateway.broadcast('agent.list', { agents: agentsList, activeAgentId: activeAgent } as Record<string, unknown>, undefined, requestId);
		} else {
			// Fallback: return current agent from ariaLabel
			const fallback = await this.evaluateWithResult<{ agent: string; title: string }>(buildGetActiveAgentScript());
			const fallbackAgent = fallback.ok && fallback.result ? [{
				id: (fallback.result.agent || 'unknown').toLowerCase().replace(/[^a-z0-9]/g, '_'),
				name: fallback.result.agent || 'Unknown',
				description: '',
				index: 0,
				active: true,
				source: 'synthetic' as const
			}] : [];
			this.wsGateway.broadcast('agent.list', {
				agents: fallbackAgent as Record<string, unknown>[],
				activeAgentId: this.lastActiveAgentId
			} as Record<string, unknown>, undefined, requestId);
		}
	}

	private async handleSwitchAgentCommand(agentId?: string, index?: number, name?: string, requestId?: string): Promise<void> {
		// Step 1: Open agent picker
		const openResult = await this.evaluateWithResult(buildAgentListScript());
		if (!openResult.ok) {
			throw new Error(openResult.reason || 'Failed to open agent picker');
		}

		// Step 2: Wait for picker
		await new Promise(resolve => setTimeout(resolve, 500));

		// Step 3: If index not given, scan to find the agent by id/name
		let targetIndex = index;
		if (targetIndex === undefined && (agentId || name)) {
			const scanResult = await this.evaluateWithResult(buildScanAgentListScript());
			if (scanResult.ok && scanResult.result) {
				const agents = (scanResult.result as Record<string, unknown>)['agents'] as Array<Record<string, unknown>>;
				const found = agents.find(a =>
					a.id === agentId || a.name === name
				);
				if (found) targetIndex = found.index as number;
			}
		}

		if (targetIndex === undefined) {
			// Close picker before throwing
			await this.evaluateWithResult(buildCloseAgentPickerScript()).catch(() => undefined);
			throw new Error('Could not determine agent index');
		}

		// Step 4: Click the agent
		const switchResult = await this.evaluateWithResult(buildSwitchAgentScript(targetIndex));
		if (!switchResult.ok) {
			await this.evaluateWithResult(buildCloseAgentPickerScript()).catch(() => undefined);
			throw new Error(switchResult.reason || 'Failed to switch agent');
		}

		// Step 5: Wait and detect the change
		this.switchingAgent = true;
		await new Promise(resolve => setTimeout(resolve, 600));

		const confirmResult = await this.evaluateWithResult<{ agent: string; title: string }>(buildGetActiveAgentScript());
		if (confirmResult.ok && confirmResult.result) {
			const newAgent = confirmResult.result.agent.toLowerCase().replace(/[^a-z0-9]/g, '_');
			const fromAgentId = this.lastActiveAgentId;
			this.lastActiveAgentId = newAgent;

			this.wsGateway.broadcast('agent.switched', {
				fromAgentId,
				toAgentId: newAgent,
				reason: 'client'
			} as Record<string, unknown>, undefined, requestId);
		}

		this.switchingAgent = false;
	}
}
