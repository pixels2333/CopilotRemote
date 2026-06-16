import CDP from 'chrome-remote-interface';

async function main() {
  const client = await CDP({ target: 'ws://127.0.0.1:9229/devtools/page/C465C706ED9B3726775E70738E8CED3D' });
  await client.Runtime.enable();
  const r = await client.Runtime.evaluate({
    expression: 'window.__copilotMirrorInstalled=false; window.__copilotMirrorState=null; ({reset:true})',
    returnByValue: true,
    awaitPromise: true
  });
  console.log('reset', r.result.value);
  await client.close();
}

main().catch(e => { console.error(e); process.exit(1); });
