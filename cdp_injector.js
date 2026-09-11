const { chromium } = require('playwright');
const fs = require('fs');

const logPath = 'E:/TOOL/Source Code/Agent Antigravity/scratch/cdp_log.txt';
function log(msg) { fs.appendFileSync(logPath, new Date().toISOString() + ': ' + msg + '\n'); }

try {
    log('Started with args: ' + process.argv.join(' | '));
    const port = process.argv[2];
    const spoofScriptPath = process.argv[3];
    const spoofScript = fs.readFileSync(spoofScriptPath, 'utf8');
    log('Script read successfully');

    (async () => {
        let browser;
        for(let i=0; i<30; i++) {
            try {
                browser = await chromium.connectOverCDP('http://localhost:' + port);
                log('Connected to CDP');
                break;
            } catch(e) {
                await new Promise(r => setTimeout(r, 1000));
            }
        }
        
        if(!browser) {
            log('Failed to connect to CDP');
            process.exit(1);
        }
        
        const contexts = browser.contexts();
        for (const context of contexts) {
            await context.addInitScript(spoofScript);
        }
        log('Injected to existing contexts');
        
        browser.on('contextcreated', async (context) => {
            await context.addInitScript(spoofScript);
            log('Injected to new context');
        });
        
        browser.on('disconnected', () => {
            log('Disconnected, exiting');
            process.exit(0);
        });
    })();
} catch(e) {
    log('Error: ' + e.message);
}
