/*---------------------------------------------------------------------------------------------
 *  Copilot Mirror – WebSocket Gateway (Phase 1)
 *  Architecture: copilot-mirror-architecture.md
 *--------------------------------------------------------------------------------------------*/

import { WebSocketServer, WebSocket } from 'ws';
import {
	type MirrorEnvelope,
	type BridgeOptions,
	type ClientHelloPayload,
	type SendMessagePayload,
	type ServerHelloPayload,
	type ServerAckPayload,
	type ServerErrorPayload,
	type MirrorBlock,
	DEFAULT_BRIDGE_OPTIONS
} from './protocol.js';

export type ClientCommandHandler = (
	type: string,
	payload: Record<string, unknown>,
	requestId?: string,
	sessionId?: string
) => Promise<void>;

export type SendMessageHandler = (
	payload: SendMessagePayload,
	requestId?: string
) => Promise<void>;

export class WsGateway {
	private wss: WebSocketServer | undefined;
	private readonly clients = new Set<WebSocket>();
	private readonly eventBuffer: MirrorEnvelope[] = [];
	private seq = 0;
	private currentOptions: BridgeOptions;

	onSendMessage: SendMessageHandler | undefined;
	onStopGeneration: (() => Promise<void>) | undefined;
	onFocusInput: (() => Promise<void>) | undefined;
	onOpenArtifact: ((artifactId: string) => Promise<void>) | undefined;
	onListSessions: ((requestId?: string) => Promise<void>) | undefined;
	onSwitchSession: ((sessionId: string | undefined, index: number | undefined, title: string | undefined, requestId?: string) => Promise<void>) | undefined;
	onNewSession: ((requestId?: string) => Promise<void>) | undefined;
	onListSlashCommands: ((query: string | undefined, requestId?: string) => Promise<void>) | undefined;
	onApplySlashCommand: ((index: number, insertOnly: boolean, requestId?: string) => Promise<void>) | undefined;
	onListAgents: ((requestId?: string) => Promise<void>) | undefined;
	onSwitchAgent: ((agentId: string | undefined, index: number | undefined, name: string | undefined, requestId?: string) => Promise<void>) | undefined;
	onRefresh: ((requestId?: string) => Promise<void>) | undefined;
	onClientHello: ((ws: WebSocket, requestId?: string) => Promise<boolean | void>) | undefined;
	onCommand: ClientCommandHandler | undefined;

	constructor(private options: BridgeOptions = DEFAULT_BRIDGE_OPTIONS) {
		this.currentOptions = options;
	}

	start(): void {
		this.wss = new WebSocketServer({
			port: this.options.wsPort,
			path: this.options.wsPath
		});

		this.wss.on('connection', ws => {
			this.clients.add(ws);

			ws.on('message', raw => {
				this.handleClientMessage(ws, raw.toString());
			});

			ws.on('close', () => {
				this.clients.delete(ws);
			});

			ws.on('error', () => {
				this.clients.delete(ws);
			});
		});

		this.wss.on('error', (err) => {
			console.error('[WsGateway] Server error:', err);
		});
	}

	stop(): void {
		if (this.wss) {
			this.wss.close();
		}
	}

	get clientCount(): number {
		return this.clients.size;
	}

	/** Encode and track a server event, then broadcast to all clients */
	broadcast(type: string, payload: Record<string, unknown>, sessionId?: string, requestId?: string): void {
		const envelope = this.createEnvelope(type, payload, sessionId, requestId);
		this.rememberEvent(envelope);
		for (const client of this.clients) {
			this.sendEnvelope(client, envelope);
		}
	}

	/** Send an event to a single client */
	sendTo(client: WebSocket, type: string, payload: Record<string, unknown>, requestId?: string, sessionId?: string): void {
		const envelope = this.createEnvelope(type, payload, sessionId, requestId);
		this.sendEnvelope(client, envelope);
	}

	/** Send a snapshot to a specific client (for initial sync) */
	sendSnapshot(client: WebSocket, messages: MirrorEnvelope['payload']['messages'], sessionId?: string): void {
		const snapshotSeq = ++this.seq;
		this.sendTo(client, 'session.snapshot', {
			mode: 'full',
			cursor: {
				seq: snapshotSeq,
				snapshotVersion: Date.now()
			},
			session: {
				sessionId: sessionId ?? this.options.sessionId,
				title: 'Copilot Chat',
				workspace: null,
				createdAt: new Date().toISOString(),
				updatedAt: new Date().toISOString()
			},
			messages
		}, undefined, sessionId);
	}

	private handleClientMessage(ws: WebSocket, raw: string): void {
		let envelope: MirrorEnvelope;
		try {
			envelope = JSON.parse(raw) as MirrorEnvelope;
		} catch {
			this.sendTo(ws, 'server.error', {
				code: 'INVALID_JSON',
				message: 'WebSocket payload is not valid JSON.',
				retryable: false
			});
			return;
		}

		if (envelope.v !== 1) {
			this.sendTo(ws, 'server.error', {
				code: 'UNSUPPORTED_PROTOCOL_VERSION',
				message: 'Only protocol version 1 is supported.',
				retryable: false
			}, envelope.requestId);
			return;
		}

		switch (envelope.type) {
			case 'client.hello':
				void this.handleHello(ws, envelope.payload as ClientHelloPayload, envelope.requestId);
				break;

			case 'client.ping':
				this.handlePing(ws, envelope.requestId);
				break;

			case 'client.command.sendMessage':
				void this.handleSendMessage(ws, envelope.payload as unknown as SendMessagePayload, envelope.requestId, envelope.sessionId);
				break;

			case 'client.command.stopGeneration':
				void this.handleStopGeneration(ws, envelope.requestId);
				break;

			case 'client.command.focusInput':
				void this.handleFocusInput(ws, envelope.requestId);
				break;

			case 'client.command.openArtifact':
				void this.handleOpenArtifact(ws, envelope.payload as Record<string, unknown>, envelope.requestId);
				break;

			case 'client.command.listSessions':
				void this.handleListSessions(ws, envelope.requestId);
				break;

			case 'client.command.switchSession':
				void this.handleSwitchSession(ws, envelope.payload as Record<string, unknown>, envelope.requestId);
				break;

			case 'client.command.newSession':
				void this.handleNewSession(ws, envelope.requestId);
				break;

			case 'client.command.listSlashCommands':
				void this.handleListSlashCommands(ws, (envelope.payload as Record<string, unknown>)?.['query'] as string | undefined, envelope.requestId);
				break;

			case 'client.command.applySlashCommand':
				void this.handleApplySlashCommand(ws, envelope.payload as Record<string, unknown>, envelope.requestId);
				break;

			case 'client.command.listAgents':
				void this.handleListAgents(ws, envelope.requestId);
				break;

			case 'client.command.switchAgent':
				void this.handleSwitchAgent(ws, envelope.payload as Record<string, unknown>, envelope.requestId);
				break;

			case 'client.command.refresh':
				void this.handleRefresh(ws, envelope.requestId);
				break;

			default:
				if (this.onCommand) {
					void this.onCommand(envelope.type, envelope.payload, envelope.requestId, envelope.sessionId);
				} else {
					this.sendTo(ws, 'server.error', {
						code: 'UNKNOWN_CLIENT_MESSAGE',
						message: `Unsupported client message: ${envelope.type}`,
						retryable: false
					}, envelope.requestId);
				}
		}
	}

	private async handleHello(ws: WebSocket, payload: ClientHelloPayload, requestId?: string): Promise<void> {
		// Auth check
		if (this.currentOptions.authToken && payload.auth?.token !== this.currentOptions.authToken) {
			this.sendTo(ws, 'server.error', {
				code: 'UNAUTHORIZED',
				message: 'Invalid pairing token.',
				retryable: false
			}, requestId);
			ws.close();
			return;
		}

		// Respond with server.hello
		this.sendTo(ws, 'server.hello', {
			serverId: 'node-copilot-mirror',
			protocolVersion: 1,
			cdp: {
				connected: false,
				endpoint: `${this.options.cdpHost}:${this.options.cdpPort}`,
				targetTitle: null,
				targetUrl: null
			},
			session: {
				sessionId: this.options.sessionId,
				title: 'Copilot Chat',
				status: 'active'
			},
			capabilities: {
				delta: true,
				commands: ['sendMessage', 'stopGeneration', 'focusInput', 'openArtifact', 'listSessions', 'switchSession', 'newSession', 'listSlashCommands', 'applySlashCommand', 'listAgents', 'switchAgent']
			}
		} satisfies ServerHelloPayload, requestId);

		// Resume logic
		const lastSeq = payload.resume?.lastSeq;
		if (typeof lastSeq === 'number') {
			const missed = this.eventBuffer.filter(
				event => typeof event.seq === 'number' && event.seq > lastSeq
			);
			if (missed.length > 0) {
				this.sendTo(ws, 'session.resume', {
					accepted: true,
					fromSeq: lastSeq + 1,
					toSeq: this.seq
				}, requestId);
				for (const event of missed) {
					this.sendEnvelope(ws, event);
				}
				return;
			}
		}

		// Prefer a live bridge-provided snapshot for fresh connections.
		// This avoids replaying a stale buffered snapshot captured before the
		// bridge reattached to the correct DOM list.
		if (this.onClientHello) {
			try {
				const handled = await this.onClientHello(ws, requestId);
				if (handled) {
					return;
				}
			} catch {
				// onClientHello may throw if CDP is disconnected; fall through to buffered events below
			}
		}

		// Fresh connections do not currently send resume.lastSeq.
		// Send the latest full snapshot so the client can render existing chat content immediately.
		const latestSnapshot = [...this.eventBuffer]
			.reverse()
			.find(event => event.type === 'session.snapshot');
		if (latestSnapshot) {
			this.sendEnvelope(ws, latestSnapshot);
			return;
		}
	}

	private async handleSendMessage(
		ws: WebSocket,
		payload: SendMessagePayload,
		requestId?: string,
		_sessionId?: string
	): Promise<void> {
		if (!payload.text || typeof payload.text !== 'string') {
			this.sendTo(ws, 'server.error', {
				code: 'INVALID_ARGUMENT',
				message: 'payload.text is required.',
				retryable: false
			}, requestId);
			return;
		}

		if (this.onSendMessage) {
			try {
				await this.onSendMessage(payload, requestId);
				this.sendTo(ws, 'server.ack', {
					ok: true,
					command: 'sendMessage',
					acceptedAt: new Date().toISOString()
				} satisfies ServerAckPayload, requestId);
			} catch (error) {
				this.sendTo(ws, 'server.error', {
					code: 'SEND_MESSAGE_FAILED',
					message: error instanceof Error ? error.message : 'Failed to send message.',
					retryable: true
				} satisfies ServerErrorPayload, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', {
				code: 'NOT_READY',
				message: 'Bridge not connected to Copilot.',
				retryable: true
			}, requestId);
		}
	}

	private async handleStopGeneration(ws: WebSocket, requestId?: string): Promise<void> {
		if (this.onStopGeneration) {
			try {
				await this.onStopGeneration();
				this.sendTo(ws, 'server.ack', {
					ok: true,
					command: 'stopGeneration',
					acceptedAt: new Date().toISOString()
				}, requestId);
			} catch {
				this.sendTo(ws, 'server.error', {
					code: 'STOP_FAILED',
					message: 'Failed to stop generation.',
					retryable: true
				}, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', {
				code: 'NOT_READY',
				message: 'Bridge not connected.',
				retryable: true
			}, requestId);
		}
	}

	private async handleFocusInput(ws: WebSocket, requestId?: string): Promise<void> {
		if (this.onFocusInput) {
			try {
				await this.onFocusInput();
				this.sendTo(ws, 'server.ack', {
					ok: true,
					command: 'focusInput',
					acceptedAt: new Date().toISOString()
				}, requestId);
			} catch {
				this.sendTo(ws, 'server.error', {
					code: 'FOCUS_FAILED',
					message: 'Failed to focus input.',
					retryable: true
				}, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', {
				code: 'NOT_READY',
				message: 'Bridge not connected.',
				retryable: true
			}, requestId);
		}
	}

	private handlePing(ws: WebSocket, requestId?: string): void {
		this.sendTo(ws, 'server.pong', {
			replyTo: requestId ?? '',
			timestamp: new Date().toISOString()
		}, requestId);
	}

	private async handleListSessions(ws: WebSocket, requestId?: string): Promise<void> {
		if (this.onListSessions) {
			try {
				await this.onListSessions(requestId);
			} catch {
				this.sendTo(ws, 'server.error', {
					code: 'LIST_SESSIONS_FAILED',
					message: 'Failed to list sessions.',
					retryable: true
				}, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', {
				code: 'NOT_READY',
				message: 'Session list not available.',
				retryable: true
			}, requestId);
		}
	}

	private async handleSwitchSession(ws: WebSocket, payload: Record<string, unknown>, requestId?: string): Promise<void> {
		const sessionId = payload['sessionId'] as string | undefined;
		const index = payload['index'] as number | undefined;
		const title = payload['title'] as string | undefined;

		if (sessionId === undefined && index === undefined && title === undefined) {
			this.sendTo(ws, 'server.error', {
				code: 'INVALID_ARGUMENT',
				message: 'payload requires sessionId, index, or title.',
				retryable: false
			}, requestId);
			return;
		}

		if (this.onSwitchSession) {
			try {
				await this.onSwitchSession(sessionId, index, title, requestId);
				this.sendTo(ws, 'server.ack', {
					ok: true,
					command: 'switchSession',
					acceptedAt: new Date().toISOString()
				}, requestId);
			} catch (error) {
				this.sendTo(ws, 'server.error', {
					code: 'SWITCH_SESSION_FAILED',
					message: error instanceof Error ? error.message : 'Failed to switch session.',
					retryable: true
				}, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', {
				code: 'NOT_READY',
				message: 'Bridge not ready to switch sessions.',
				retryable: true
			}, requestId);
		}
	}

	private async handleNewSession(ws: WebSocket, requestId?: string): Promise<void> {
		if (this.onNewSession) {
			try {
				await this.onNewSession(requestId);
				this.sendTo(ws, 'server.ack', {
					ok: true,
					command: 'newSession',
					acceptedAt: new Date().toISOString()
				}, requestId);
			} catch (error) {
				this.sendTo(ws, 'server.error', {
					code: 'NEW_SESSION_FAILED',
					message: error instanceof Error ? error.message : 'Failed to create new session.',
					retryable: true
				}, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', {
				code: 'NOT_READY',
				message: 'Bridge not ready.',
				retryable: true
			}, requestId);
		}
	}

	private async handleListSlashCommands(ws: WebSocket, query: string | undefined, requestId?: string): Promise<void> {
		if (this.onListSlashCommands) {
			try {
				await this.onListSlashCommands(query, requestId);
			} catch {
				this.sendTo(ws, 'server.error', {
					code: 'LIST_SLASH_FAILED',
					message: 'Failed to list slash commands.',
					retryable: true
				}, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', {
				code: 'NOT_READY',
				message: 'Bridge not ready.',
				retryable: true
			}, requestId);
		}
	}

	private async handleApplySlashCommand(ws: WebSocket, payload: Record<string, unknown>, requestId?: string): Promise<void> {
		const index = payload['index'] as number | undefined;
		const insertOnly = payload['insertOnly'] as boolean | undefined;

		if (index === undefined) {
			this.sendTo(ws, 'server.error', {
				code: 'INVALID_ARGUMENT',
				message: 'payload.index is required.',
				retryable: false
			}, requestId);
			return;
		}

		if (this.onApplySlashCommand) {
			try {
				await this.onApplySlashCommand(index, insertOnly ?? false, requestId);
				this.sendTo(ws, 'server.ack', {
					ok: true,
					command: 'applySlashCommand',
					acceptedAt: new Date().toISOString()
				}, requestId);
			} catch (error) {
				this.sendTo(ws, 'server.error', {
					code: 'APPLY_SLASH_FAILED',
					message: error instanceof Error ? error.message : 'Failed to apply slash command.',
					retryable: true
				}, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', {
				code: 'NOT_READY',
				message: 'Bridge not ready.',
				retryable: true
			}, requestId);
		}
	}

	private async handleListAgents(ws: WebSocket, requestId?: string): Promise<void> {
		if (this.onListAgents) {
			try {
				await this.onListAgents(requestId);
			} catch {
				this.sendTo(ws, 'server.error', {
					code: 'LIST_AGENTS_FAILED',
					message: 'Failed to list agents.',
					retryable: true
				}, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', {
				code: 'NOT_READY',
				message: 'Bridge not ready.',
				retryable: true
			}, requestId);
		}
	}

	private async handleSwitchAgent(ws: WebSocket, payload: Record<string, unknown>, requestId?: string): Promise<void> {
		const agentId = payload['agentId'] as string | undefined;
		const index = payload['index'] as number | undefined;
		const name = payload['name'] as string | undefined;

		if (agentId === undefined && index === undefined && name === undefined) {
			this.sendTo(ws, 'server.error', {
				code: 'INVALID_ARGUMENT',
				message: 'payload requires agentId, index, or name.',
				retryable: false
			}, requestId);
			return;
		}

		if (this.onSwitchAgent) {
			try {
				await this.onSwitchAgent(
					payload['agentId'] as string | undefined,
					payload['index'] as number | undefined,
					payload['name'] as string | undefined,
					requestId
				);
				this.sendTo(ws, 'server.ack', { ok: true, command: 'switchAgent', acceptedAt: new Date().toISOString() }, requestId);
			} catch {
				this.sendTo(ws, 'server.error', { code: 'SWITCH_AGENT_FAILED', message: 'Failed to switch agent.', retryable: true }, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', { code: 'NOT_READY', message: 'Bridge not connected.', retryable: true }, requestId);
		}
	}

	private async handleRefresh(ws: WebSocket, requestId?: string): Promise<void> {
		if (this.onRefresh) {
			try {
				await this.onRefresh(requestId);
				this.sendTo(ws, 'server.ack', { ok: true, command: 'refresh', acceptedAt: new Date().toISOString() }, requestId);
			} catch (error) {
				this.sendTo(ws, 'server.error', { code: 'REFRESH_FAILED', message: error instanceof Error ? error.message : 'Failed to refresh.', retryable: true }, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', { code: 'NOT_READY', message: 'Bridge not connected.', retryable: true }, requestId);
		}
	}

	private async handleOpenArtifact(
		ws: WebSocket,
		payload: Record<string, unknown>,
		requestId?: string
	): Promise<void> {
		const artifactId = payload['artifactId'] as string | undefined;
		if (!artifactId) {
			this.sendTo(ws, 'server.error', {
				code: 'INVALID_ARGUMENT',
				message: 'payload.artifactId is required.',
				retryable: false
			}, requestId);
			return;
		}

		if (this.onOpenArtifact) {
			try {
				await this.onOpenArtifact(artifactId);
				this.sendTo(ws, 'server.ack', {
					ok: true,
					command: 'openArtifact',
					acceptedAt: new Date().toISOString()
				}, requestId);
			} catch (error) {
				this.sendTo(ws, 'server.error', {
					code: 'OPEN_ARTIFACT_FAILED',
					message: error instanceof Error ? error.message : 'Failed to open artifact.',
					retryable: true
				}, requestId);
			}
		} else {
			this.sendTo(ws, 'server.error', {
				code: 'NOT_READY',
				message: 'Bridge not connected.',
				retryable: true
			}, requestId);
		}
	}

	private createEnvelope(
		type: string,
		payload: Record<string, unknown>,
		sessionId?: string,
		requestId?: string
	): MirrorEnvelope {
		return {
			v: 1,
			seq: ++this.seq,
			type,
			sessionId: sessionId ?? this.options.sessionId,
			requestId,
			timestamp: new Date().toISOString(),
			payload
		};
	}

	private sendEnvelope(client: WebSocket, envelope: MirrorEnvelope): void {
		try {
			if (client.readyState !== WebSocket.OPEN) {
				return;
			}
			client.send(JSON.stringify(envelope));
		} catch {
			// Client socket may be in bad state; silently skip
		}
	}

	private rememberEvent(envelope: MirrorEnvelope): void {
		this.eventBuffer.push(envelope);
		if (this.eventBuffer.length > this.options.eventBufferLimit) {
			this.eventBuffer.shift();
		}
	}
}

