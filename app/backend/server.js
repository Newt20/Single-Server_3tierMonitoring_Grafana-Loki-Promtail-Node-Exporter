require('dotenv').config();
const http = require('http');
const mysql = require('mysql2/promise');
const client = require('prom-client');

// 1. Metrics Setup
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics({ register: client.register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'code'],
  buckets: [0.1, 0.5, 1, 2, 5] // Buckets for <100ms, <500ms, etc.
});

// 2. MySQL Setup
const pool = mysql.createPool({
  host: process.env.DB_HOST, 
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD, 
  database: process.env.DB_NAME
});

// Seed
(async () => {
  // Create table with FULL columns
  await pool.execute(`
    CREATE TABLE IF NOT EXISTS members (
      id         INT AUTO_INCREMENT PRIMARY KEY,
      name       VARCHAR(100) NOT NULL,
      role       VARCHAR(100) NOT NULL,
      department VARCHAR(100) NOT NULL,
      location   VARCHAR(100) NOT NULL,
      joined_at  DATE NOT NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
  `);

  const [rows] = await pool.execute('SELECT COUNT(*) AS cnt FROM members');
  
  // Only insert if table is empty
  if (rows[0].cnt > 0) return;

  const seed = [
    ['Alice Nguyen',   'Lead Engineer',      'Engineering', 'Singapore',   '2021-03-15'],
    ['Bob Rahman',     'Product Manager',    'Product',     'Kuala Lumpur','2020-07-01'],
    ['Clara Osei',     'UX Designer',        'Design',      'Accra',       '2022-01-10'],
    ['David Kim',      'Backend Developer',  'Engineering', 'Seoul',       '2021-11-22'],
    ['Eva Santos',     'Data Analyst',       'Analytics',   'Sao Paulo',   '2023-02-28'],
    ['Frank Müller',   'DevOps Engineer',    'Platform',    'Berlin',      '2020-09-05'],
    ['Grace Okonkwo',  'Frontend Developer', 'Engineering', 'Lagos',       '2022-06-17'],
    ['Hassan Ali',     'QA Engineer',        'Quality',     'Cairo',       '2021-08-30'],
  ];

  for (const [name, role, department, location, joined_at] of seed) {
    await pool.execute(
      'INSERT INTO members (name, role, department, location, joined_at) VALUES (?, ?, ?, ?, ?)',
      [name, role, department, location, joined_at]
    );
  }
  console.log('[seed] Inserted: 8 seed the members');
})();

// 3. Main App Server (Port 8080)
const appServer = http.createServer(async (req, res) => {
  const end = httpRequestDuration.startTimer();

  if (req.url === '/api/members' && req.method === 'GET') {
    const t0 = Date.now();
    const [rows] = await pool.execute('SELECT * FROM members');
    const ms = Date.now() - t0;

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      source: 'mysql://127.0.0.1/teamdb',
      query_ms: ms,
      members: rows
    }));
    end({ method: req.method, route: '/api/members', code: 200 });
  }else {
    res.writeHead(404); 
    res.end('Not Found');
    end({ route: '404', code: 404 });
  }
});

appServer.listen(8080, () => console.log('App running on port 8080'));

// 4. Metrics Server (Port 9453) - Required for Prometheus
const metricsServer = http.createServer(async (req, res) => {
  if (req.url === '/metrics') {
    res.setHeader('Content-Type', client.register.contentType);
    res.end(await client.register.metrics());
  } else {
    res.writeHead(404);
    res.end('Not Found');
  }
});

metricsServer.listen(9453, () => console.log('Metrics server listening on 9453'));