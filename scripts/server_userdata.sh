#!/bin/bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "===== [Native Stack Setup] Start ====="

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y wget curl unzip adduser libfontconfig1 software-properties-common

# ─────────────────────────────────────────────────────────────
# 1. Install Node Exporter (System Metrics)
# ─────────────────────────────────────────────────────────────
echo "[1/7] Installing Node Exporter..."
useradd --no-create-home --shell /bin/false node_exporter
wget -q https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz -O /tmp/node_exporter.tar.gz
tar -xf /tmp/node_exporter.tar.gz -C /tmp/
cp /tmp/node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Node Exporter
After=network.target
[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter
[Install]
WantedBy=multi-user.target
EOF

# ─────────────────────────────────────────────────────────────
# 2. Install Prometheus (Metrics Database)
# ─────────────────────────────────────────────────────────────
echo "[2/7] Installing Prometheus..."
useradd --no-create-home --shell /bin/false prometheus
mkdir -p /etc/prometheus /var/lib/prometheus
wget -q https://github.com/prometheus/prometheus/releases/download/v2.48.0/prometheus-2.48.0.linux-amd64.tar.gz -O /tmp/prometheus.tar.gz
tar -xf /tmp/prometheus.tar.gz -C /tmp/
cp /tmp/prometheus-2.48.0.linux-amd64/prometheus /usr/local/bin/
cp /tmp/prometheus-2.48.0.linux-amd64/promtool /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus
chown prometheus:prometheus /usr/local/bin/promtool
chown -R prometheus:prometheus /etc/prometheus
chown -R prometheus:prometheus /var/lib/prometheus

cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'node_app'
    static_configs:
      - targets: ['localhost:9453']
EOF

chown prometheus:prometheus /etc/prometheus/prometheus.yml

cat > /etc/systemd/system/prometheus.service <<'EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target
[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file /etc/prometheus/prometheus.yml \
  --storage.tsdb.path /var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries
[Install]
WantedBy=multi-user.target
EOF

# ─────────────────────────────────────────────────────────────
# 3. Install Loki (Log Database)
# ─────────────────────────────────────────────────────────────
echo "[3/7] Installing Loki..."
useradd --no-create-home --shell /bin/false loki
wget -q https://github.com/grafana/loki/releases/download/v2.9.6/loki-linux-amd64.zip -O /tmp/loki.zip
unzip -q /tmp/loki.zip -d /tmp/
mv /tmp/loki-linux-amd64 /usr/local/bin/loki
chown loki:loki /usr/local/bin/loki
mkdir -p /etc/loki /var/lib/loki
chown -R loki:loki /etc/loki /var/lib/loki

cat > /etc/loki/loki-config.yml <<EOF
auth_enabled: false
server:
  http_listen_port: 3100
common:
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory
schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h
ruler:
  alertmanager_url: http://localhost:9093
EOF

cat > /etc/systemd/system/loki.service <<'EOF'
[Unit]
Description=Loki
After=network.target
[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yml
[Install]
WantedBy=multi-user.target
EOF

# ─────────────────────────────────────────────────────────────
# 4. Install Promtail (Log Shipper)
# ─────────────────────────────────────────────────────────────
echo "[4/7] Installing Promtail..."
useradd --no-create-home --shell /bin/false promtail
wget -q https://github.com/grafana/loki/releases/download/v2.9.6/promtail-linux-amd64.zip -O /tmp/promtail.zip
unzip -q /tmp/promtail.zip -d /tmp/
mv /tmp/promtail-linux-amd64 /usr/local/bin/promtail
chown promtail:promtail /usr/local/bin/promtail

sudo mkdir -p /etc/promtail

sudo usermod -aG adm promtail

cat > /etc/promtail/config.yml <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
- job_name: system
  static_configs:
  - targets:
      - localhost
    labels:
      job: varlogs
      __path__: /var/log/syslog

- job_name: system_logs
  static_configs:
  - targets:
      - localhost
    labels:
      job: varlogs
      __path__: /var/log/*log

- job_name: nginx
  static_configs:
  - targets:
      - localhost
    labels:
      job: nginx
      __path__: /var/log/nginx/*log
EOF

cat > /etc/systemd/system/promtail.service <<'EOF'
[Unit]
Description=Promtail
After=network.target
[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail -config.file /etc/promtail/config.yml
[Install]
WantedBy=multi-user.target
EOF

# ─────────────────────────────────────────────────────────────
# 5. Install App Stack
# ─────────────────────────────────────────────────────────────
echo "[5/7] Installing App Stack..."

# MySQL Pre-config
echo "mysql-server mysql-server/root_password_again password rootpass" | debconf-set-selections
apt-get install -y nginx mysql-server git build-essential

# Setup MySQL
sed -i 's/bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql
mysql -u root -prootpass -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\`;"
mysql -u root -prootpass -e "CREATE USER IF NOT EXISTS '${db_username}'@'%' IDENTIFIED BY '${db_password}';"
mysql -u root -prootpass -e "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_username}'@'%';"
mysql -u root -prootpass -e "FLUSH PRIVILEGES;"

# Node.js & NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 18
nvm use 18
nvm alias default 18

npm install -g pm2
npm install dotenv

# Setup App
mkdir -p /var/app/backend
cat > /var/app/backend/package.json << 'PKGJSON'
{
  "name": "nt-backend",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": { 
    "mysql2": "^3.9.7",
    "dotenv": "^16.4.5",
    "prom-client": "^15.1.0" 
  }
}
PKGJSON

cat > /var/app/backend/.env << ENVFILE
NODE_ENV=production
PORT=8080
DB_HOST=127.0.0.1
DB_PORT=${db_port}
DB_NAME=${db_name}
DB_USER=${db_username}
DB_PASSWORD=${db_password}
ENVFILE

cat > /var/app/backend/server.js << 'SERVERJS'
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
  console.log('[seed] Inserted 8 seed members');
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
SERVERJS

cd /var/app/backend
npm install
pm2 start server.js --name nt-api
pm2 startup systemd -u root --hp /root
env PATH=$PATH:/home/ubuntu/.nvm/versions/node/v18.20.8/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu


pm2 save

# 4. Nginx Frontend
mkdir -p /var/www/html/app
cat > /var/www/html/app/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Team Directory</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Segoe UI', system-ui, sans-serif; background: #0f172a; color: #e2e8f0; min-height: 100vh; padding: 2rem; }
    header { text-align: center; margin-bottom: 3rem; }
    header h1 { font-size: 2.5rem; font-weight: 700; background: linear-gradient(135deg, #38bdf8, #818cf8); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
    header p { color: #64748b; margin-top: 0.5rem; }
    #status { text-align: center; padding: 1rem; border-radius: 8px; margin-bottom: 1.5rem; font-size: 0.9rem; display: none; }
    #status.error   { background: #450a0a; color: #fca5a5; display: block; }
    #status.loading { background: #172554; color: #93c5fd; display: block; }
    #grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 1.25rem; max-width: 1100px; margin: 0 auto; }
    .card { background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 1.5rem; transition: transform 0.2s, border-color 0.2s; }
    .card:hover { transform: translateY(-4px); border-color: #38bdf8; }
    .avatar { width: 52px; height: 52px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 1.4rem; font-weight: 700; margin-bottom: 1rem; background: linear-gradient(135deg, #0ea5e9, #6366f1); color: #fff; }
    .card h2 { font-size: 1.1rem; font-weight: 600; color: #f1f5f9; }
    .role { font-size: 0.82rem; color: #38bdf8; margin: 0.25rem 0 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; }
    .dept { font-size: 0.85rem; color: #94a3b8; }
    .joined { font-size: 0.78rem; color: #475569; margin-top: 0.5rem; }
    .tag { display: inline-block; background: #0f172a; border: 1px solid #334155; color: #94a3b8; font-size: 0.75rem; padding: 0.2rem 0.6rem; border-radius: 999px; margin-top: 0.75rem; }
    #meta { text-align: center; color: #334155; font-size: 0.78rem; margin-top: 2.5rem; }
  </style>
</head>
<body>
<header>
  <h1>Team Directory</h1>
  <p>Live data pulled from Database MySQL via Node.js API</p>
</header>
<div id="status" class="loading">Fetching data...</div>
<div id="grid"></div>
<div id="meta"></div>
<script>
  async function load() {
    const status = document.getElementById('status');
    const grid   = document.getElementById('grid');
    const meta   = document.getElementById('meta');
    status.className = 'loading'; status.textContent = 'Fetching team data from API...'; status.style.display = 'block';
    try {
      const res  = await fetch('/api/members');
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const data = await res.json();
      status.style.display = 'none';
      data.members.forEach(m => {
        const initials = m.name.split(' ').map(w=>w[0]).join('').slice(0,2).toUpperCase();
        grid.innerHTML += '<div class="card"><div class="avatar">'+initials+'</div><h2>'+m.name+'</h2><div class="role">'+m.role+'</div><div class="dept">'+m.department+'</div><div class="joined">Joined '+new Date(m.joined_at).toLocaleDateString('en-US',{year:'numeric',month:'short'})+'</div><span class="tag">'+m.location+'</span></div>';
      });
      meta.textContent = data.members.length+' members loaded from '+data.source+' in '+data.query_ms+'ms';
    } catch(e) {
      status.className = 'error'; status.textContent = 'Error: '+e.message;
    }
  }
  load();
</script>
</body>
</html>
HTML

cat > /etc/nginx/sites-available/nt-app <<NGINX
server {
    listen 80;
    server_name _;

    root /var/www/html/app;
    index index.html;

    # Serve frontend SPA
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Proxy all /api/* calls to backend Node.js
    location /api/ {
        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 30s;
        proxy_read_timeout    30s;
    }

    access_log /var/log/nginx/nt-app-access.log;
    error_log  /var/log/nginx/nt-app-error.log;
}
NGINX
ln -sf /etc/nginx/sites-available/nt-app /etc/nginx/sites-enabled/nt-app
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

echo "===== [Setup Complete] ====="


# ─────────────────────────────────────────────────────────────
# Fix Permissions for the 'ubuntu' user
# ─────────────────────────────────────────────────────────────
echo "[Final] Fixing permissions..."
chown -R ubuntu:ubuntu /var/app
chown -R ubuntu:ubuntu /var/www/html
chown -R ubuntu:ubuntu /home/ubuntu/.pm2
sudo chown -R ubuntu:ubuntu /var/www/html/app
sudo chmod -R 755 /var/www/html/app

sudo chown -R ubuntu:ubuntu /var/app/backend
sudo systemctl restart nginx