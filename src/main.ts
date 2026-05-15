/*---------------------------------------------------------------------------------------------
 *  Copilot Mirror – Entry point
 *  Launches the CDP Bridge and WebSocket Gateway.
 *--------------------------------------------------------------------------------------------*/

import { CopilotMirrorBridge } from './bridge.js';
import { DEFAULT_BRIDGE_OPTIONS } from './protocol.js';

const bridge = new CopilotMirrorBridge({
	...DEFAULT_BRIDGE_OPTIONS,
	authToken: process.env['COPILOT_MIRROR_TOKEN']
});

bridge.start().catch(error => {
	console.error('[CopilotMirror] Failed to start bridge:', error);
	process.exitCode = 1;
});

process.on('SIGINT', () => {
	void bridge.stop().finally(() => process.exit(0));
});

process.on('SIGTERM', () => {
	void bridge.stop().finally(() => process.exit(0));
});

// Prevent crash from unhandled rejections (e.g. CDP disconnect during retry)
process.on('unhandledRejection', (reason) => {
	console.error('[CopilotMirror] Unhandled rejection:', reason);
});

// Prevent crash from uncaught synchronous exceptions
process.on('uncaughtException', (error) => {
	console.error('[CopilotMirror] Uncaught exception:', error);
});
