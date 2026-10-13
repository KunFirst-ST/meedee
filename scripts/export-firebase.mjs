import { main } from './firebase-export/export.mjs';

main(process.argv.slice(2)).catch((error) => {
  const message = String(error.message ?? 'Unknown export error')
    .replace(/-----BEGIN[^]*?-----END[^]*?-----/g, '[redacted credential]')
    .slice(0, 800);
  console.error(`Export failed: ${message}`);
  process.exitCode = 1;
});
