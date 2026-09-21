const express = require('express');
const app = express();

app.get('/', (req, res) => {
  res.json({ service: 'excel-api', version: 'v1' });
});

app.get('/health', (req, res) => {
  res.json({ ok: true });
});

const PORT = 8002;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`excel-api v1 listening on port ${PORT}`);
});
