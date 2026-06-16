import CDP from 'chrome-remote-interface';
import { buildObserverScript, buildCurrentSnapshotScript } from './dist/domInjection.js';
import { DEFAULT_BRIDGE_OPTIONS } from './dist/protocol.js';

const TARGET_ID = process.argv[2] || 'C465C706ED9B3726775E70738E8CED3D';

async function main() {
  const client = await CDP({ target: `ws://127.0.0.1:9229/devtools/page/${TARGET_ID}` });
  const { Runtime } = client;
  await Runtime.enable();
  await Runtime.addBinding({ name: '__copilotMirrorEmit' }).catch(() => undefined);

  // Listen for binding calls
  client.Runtime.bindingCalled(params => {
    if (params.name === '__copilotMirrorEmit') {
      try {
        const payload = JSON.parse(params.payload);
        if (payload.kind === 'snapshot') {
          const msgs = payload.messages || [];
          const streamingCount = msgs.filter(m => m.status === 'streaming').length;
          console.log(`[binding] snapshot kind=${payload.kind} msgs=${msgs.length} streaming=${streamingCount}`);
        } else {
          console.log(`[binding] ${payload.kind}`);
        }
      } catch (e) {
        console.log('[binding] parse error', e.message);
      }
    }
  });

  // Inject observer script
  const script = buildObserverScript(DEFAULT_BRIDGE_OPTIONS);
  const result = await Runtime.evaluate({
    expression: script,
    returnByValue: true,
    awaitPromise: true
  });
  console.log('Inject result:', JSON.stringify(result.result));
  console.log('Exception:', result.exceptionDetails ? JSON.stringify(result.exceptionDetails) : 'none');

  // Wait and force a snapshot
  await new Promise(r => setTimeout(r, 1000));
  const snap = await Runtime.evaluate({
    expression: buildCurrentSnapshotScript(),
    returnByValue: true,
    awaitPromise: true
  });
  const val = JSON.parse(snap.result.value);
  console.log('Force snapshot:', val.ok, val.reason || '', 'msgs', (val.result?.messages || []).length);
  if (val.result?.messages?.length) {
    const lastMsg = val.result.messages[val.result.messages.length - 1];
    console.log('Last msg status:', lastMsg.status, 'role:', lastMsg.role);
  }

  await new Promise(r => setTimeout(r, 3000));
  await client.close();
}

main().catch(e => { console.error(e); process.exit(1); });
