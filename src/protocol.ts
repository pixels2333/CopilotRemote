/*---------------------------------------------------------------------------------------------
 *  Copilot Mirror – Protocol Types (Phase 1)
 *  Architecture: copilot-mirror-architecture.md
 *--------------------------------------------------------------------------------------------*/

/** Supported block content types */
export type BlockType =
	| 'text'
	| 'thinking'
	| 'code_block'
	| 'tool_call'
	| 'artifact';

/** Message role */
export type MessageRole =
	| 'user'
	| 'assistant'
	| 'system'
	| 'tool';

/** Lifecycle status for messages and blocks */
export type MirrorStatus =
	| 'pending'
	| 'streaming'
	| 'completed'
	| 'failed'
	| 'cancelled';

/** Delta operation type */
export type DeltaOp = 'append' | 'replace' | 'patch';

/** Content format */
export type ContentFormat = 'markdown' | 'plain' | 'json' | 'diff';

/** Tool call state */
export type ToolState =
	| 'queued'
	| 'running'
	| 'succeeded'
	| 'failed'
	| 'cancelled';

/** Artifact sub-type */
export type ArtifactType =
	| 'file'
	| 'image'
	| 'html'
	| 'markdown'
	| 'diff'
	| 'terminal'
	| 'unknown';

/** WebSocket connection status (Flutter-side, for reference) */
export type ConnectionStatus =
	| 'disconnected'
	| 'connecting'
	| 'connected'
	| 'reconnecting'
	| 'failed';

/** Session switch reason */
export type SessionSwitchReason =
	| 'user'
	| 'client-command'
	| 'dom-detected';

// ─── Domain Models ───────────────────────────────────────────────

export interface MirrorSession {
	sessionId: string;
	title: string;
	workspace: string | null;
	createdAt: string;
	updatedAt: string;
	messages?: MirrorMessage[];
}

/** A single chat session item in the sidebar session list */
export interface MirrorChatSessionItem {
	sessionId: string;
	title: string;
	index: number;
	active: boolean;
	updatedAt?: string;
	preview?: string;
	source: 'dom' | 'synthetic';
}

export interface MirrorMessage {
	id: string;
	role: MessageRole;
	status: MirrorStatus;
	parentId?: string;
	createdAt: string;
	updatedAt: string;
	blocks: MirrorBlock[];
	metadata?: Record<string, unknown>;
}

export interface MirrorBlock {
	id: string;
	type: BlockType;
	status: MirrorStatus;
	content?: string;
	format?: ContentFormat;
	// code_block specific
	language?: string;
	fileName?: string;
	uri?: string;
	startLine?: number;
	isPatch?: boolean;
	// thinking specific
	visibility?: 'expanded' | 'collapsed' | 'hidden';
	// tool_call specific
	toolCallId?: string;
	toolName?: string;
	displayName?: string;
	state?: ToolState;
	arguments?: Record<string, unknown>;
	summary?: string;
	resultPreview?: string;
	// artifact specific
	artifactId?: string;
	artifactType?: ArtifactType;
	title?: string;
	mimeType?: string;
	previewUrl?: string;
	metadata?: Record<string, unknown>;
}

// ─── Protocol Envelope ───────────────────────────────────────────

export interface MirrorEnvelope<TPayload extends object = Record<string, unknown>> {
	v: 1;
	seq?: number;
	type: string;
	sessionId?: string;
	requestId?: string;
	timestamp: string;
	payload: TPayload;
}

// ─── Event Payloads ──────────────────────────────────────────────

export interface ClientHelloPayload {
	clientId?: string;
	clientName?: string;
	protocolVersion?: number;
	auth?: { type: 'bearer'; token: string };
	capabilities?: {
		acceptDelta?: boolean;
		acceptThinking?: boolean;
		acceptArtifacts?: boolean;
		acceptBinary?: boolean;
		maxChunkBytes?: number;
	};
	resume?: {
		sessionId?: string;
		lastSeq?: number;
	};
}

export interface ServerHelloPayload {
	serverId: string;
	protocolVersion: number;
	cdp: {
		connected: boolean;
		endpoint: string;
		targetTitle: string | null;
		targetUrl: string | null;
	};
	session: {
		sessionId: string;
		title: string;
		status: 'active' | 'disconnected';
	};
	capabilities: {
		delta: boolean;
		commands: string[];
	};
}

export interface SessionSnapshotPayload {
	mode: 'full';
	cursor: { seq: number; snapshotVersion: number };
	session: MirrorSession;
	messages: MirrorMessage[];
}

export interface SessionResumePayload {
	accepted: boolean;
	fromSeq: number;
	toSeq: number;
}

/** Server → client: current session list */
export interface SessionListPayload {
	sessions: MirrorChatSessionItem[];
	activeSessionId?: string;
}

/** Server → client: active session changed */
export interface SessionSwitchedPayload {
	fromSessionId?: string;
	toSessionId: string;
	reason: SessionSwitchReason;
}

/** Client → server: switch to another session */
export interface SwitchSessionPayload {
	sessionId?: string;
	index?: number;
	title?: string;
}

// ─── Slash Command Types ─────────────────────────────────────────

/** A slash command item from VS Code Copilot Chat suggest widget */
export interface MirrorSlashCommandItem {
	id: string;
	label: string;          // e.g. "/explain"
	title?: string;         // e.g. "Explain this code"
	description?: string;
	detail?: string;
	index: number;
	source: 'dom';
}

/** Server → client: slash command list */
export interface SlashListPayload {
	items: MirrorSlashCommandItem[];
	query?: string;
}

/** Client → server: apply a slash command */
export interface ApplySlashCommandPayload {
	id?: string;
	index?: number;
	label?: string;
	insertOnly?: boolean;   // true: only fill input; false: execute
}

// ─── Agent Types ─────────────────────────────────────────────────

/** An agent participant item from VS Code */
export interface MirrorAgentItem {
	id: string;
	name: string;
	description?: string;
	index: number;
	active: boolean;
	source: 'dom' | 'synthetic';
}

/** Server → client: agent list */
export interface AgentListPayload {
	agents: MirrorAgentItem[];
	activeAgentId?: string;
}

/** Server → client: active agent changed */
export interface AgentSwitchedPayload {
	fromAgentId?: string;
	toAgentId: string;
	reason: 'client' | 'dom';
}

/** Client → server: switch to another agent */
export interface SwitchAgentPayload {
	agentId?: string;
	index?: number;
	name?: string;
}

export interface MessageStartPayload {
	message: MirrorMessage;
}

export interface BlockStartPayload {
	messageId: string;
	block: MirrorBlock;
}

export interface BlockDeltaPayload {
	messageId: string;
	blockId: string;
	blockType: BlockType;
	op: DeltaOp;
	offset: number;
	chunk: string;
	format?: ContentFormat;
	done: boolean;
}

export interface BlockUpdatePayload {
	messageId: string;
	blockId: string;
	patch: Partial<MirrorBlock>;
}

export interface BlockEndPayload {
	messageId: string;
	blockId: string;
	status: MirrorStatus;
	finalLength?: number;
}

export interface MessageEndPayload {
	messageId: string;
	status: MirrorStatus;
	usage?: { inputTokens?: number; outputTokens?: number };
}

export interface SendMessagePayload {
	text: string;
	mode?: 'chat' | 'ask' | 'edit';
	attachments?: Array<{
		type: 'file' | 'selection' | 'text';
		uri?: string;
		name?: string;
		content?: string;
	}>;
	options?: {
		submit?: boolean;
		focus?: boolean;
	};
}

export interface StopGenerationPayload {
	messageId?: string;
}

export interface ServerAckPayload {
	ok: boolean;
	command: string;
	acceptedAt: string;
}

export interface ServerErrorPayload {
	code: string;
	message: string;
	retryable: boolean;
	details?: Record<string, unknown>;
}

export interface ServerStatusPayload {
	cdpConnected: boolean;
	wsClients: number;
	message: string;
}

// ─── Internal Bridge Event (page→Node.js) ───────────────────────

export interface BridgeDomEvent {
	kind:
		| 'snapshot'
		| 'message'
		| 'block'
		| 'delta'
		| 'blockUpdate'
		| 'messageEnd'
		| 'blockEnd'
		| 'heartbeat'
		| 'sessionList'
		| 'sessionActive'
		| 'slashList'
		| 'agentList';
	sessionId?: string;
	message?: MirrorMessage;
	messages?: MirrorMessage[];
	messageId?: string;
	block?: MirrorBlock;
	blockId?: string;
	blockType?: BlockType;
	offset?: number;
	chunk?: string;
	format?: ContentFormat;
	patch?: Partial<MirrorBlock>;
	status?: MirrorStatus;
	finalLength?: number;
	/** Session list data from DOM observer */
	sessions?: Array<{ title: string; index: number; active: boolean; _domIndex: number }>;
	activeTitle?: string;
}

// ─── Bridge Configuration ────────────────────────────────────────

export interface BridgeOptions {
	cdpHost: string;
	cdpPort: number;
	wsPort: number;
	wsPath: string;
	sessionId: string;
	targetScanIntervalMs: number;
	heartbeatMs: number;
	eventBufferLimit: number;
	authToken?: string;
}

export const DEFAULT_BRIDGE_OPTIONS: BridgeOptions = {
	cdpHost: '127.0.0.1',
	cdpPort: 9229,
	wsPort: 17321,
	wsPath: '/copilot-mirror/ws',
	sessionId: 'vscode-window-1/copilot-chat/default',
	targetScanIntervalMs: 3000,
	heartbeatMs: 15000,
	eventBufferLimit: 5000
};
