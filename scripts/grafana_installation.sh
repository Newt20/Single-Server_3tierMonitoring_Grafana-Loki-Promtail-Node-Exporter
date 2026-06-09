#!/bin/bash
sudo apt-get install -y apt-transport-https wget gnupg
sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
sudo chmod 644 /etc/apt/keyrings/grafana.asc

echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list

sudo apt-get update
sudo apt-get install grafana

# Provision Prometheus Data Source automatically
sudo mkdir -p /etc/grafana/provisioning/datasources
cat <<EOF | sudo tee /etc/grafana/provisioning/datasources/prometheus.yml > /dev/null
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: true
  
  - name: Loki
    type: loki
    access: proxy
    url: http://localhost:3100
    isDefault: false
    editable: true
EOF
sudo systemctl daemon-reload
sudo systemctl enable node_exporter prometheus loki promtail grafana-server
sudo systemctl start node_exporter prometheus loki promtail grafana-server
