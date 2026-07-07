const express = require('express');

const PORT = parseInt(process.env.PORT || '8080', 10);
const LOG_LEVEL = (process.env.LOG_LEVEL || 'info').toLowerCase();

const levels = { debug: 0, info: 1, warn: 2 };
function log(level, msg) {
  if (levels[level] >= levels[LOG_LEVEL]) {
    console.log(JSON.stringify({ t: new Date().toISOString(), level, msg }));
  }
}

const students = [
  { id: 1, nom: 'Adèle Ferrand',  promo: 'M2 IW' },
  { id: 2, nom: 'Bachir Saadi',   promo: 'M2 IW' },
  { id: 3, nom: 'Claire Dupond',  promo: 'M2 IW' },
];

const app = express();

app.get('/healthz', (_, res) => res.json({ ok: true, service: 'annuaire' }));
app.get('/students', (_, res) => res.json(students));

app.listen(PORT, () => log('info', `annuaire up on :${PORT}`));
log('debug', `LOG_LEVEL=${LOG_LEVEL}`);
