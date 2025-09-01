#!/bin/bash

# -----------------------------
# 1. Create project folder structure
# -----------------------------
echo "Creating project folder structure..."
mkdir -p airflow/dags airflow/logs airflow/plugins
mkdir -p spark-jobs dbt ge chatbot monitoring data report docs

# -----------------------------
# 2. Create docker-compose.yml (without GE)
# -----------------------------
echo "Creating docker-compose.yml..."
cat > docker-compose.yml <<'EOF'
version: "3.9"
services:
  spark:
    image: bitnami/spark:latest
    container_name: spark
    ports:
      - "8080:8080"
    volumes:
      - ./spark-jobs:/opt/spark/jobs
      - ./data:/opt/spark/data

  postgres:
    image: postgres:13
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow
      POSTGRES_DB: airflow
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:latest
    ports:
      - "6379:6379"

  airflow-webserver:
    image: apache/airflow:2.7.1
    depends_on:
      - postgres
      - redis
    environment:
      AIRFLOW__CORE__EXECUTOR: CeleryExecutor
      AIRFLOW__CORE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
      AIRFLOW__CELERY__BROKER_URL: redis://redis:6379/0
      AIRFLOW__CELERY__RESULT_BACKEND: db+postgresql://airflow:airflow@postgres/airflow
      AIRFLOW__WEBSERVER__RBAC: "True"
      _PIP_ADDITIONAL_REQUIREMENTS: "apache-airflow-providers-snowflake apache-airflow-providers-docker"
    ports:
      - "8081:8080"
    volumes:
      - ./airflow/dags:/opt/airflow/dags
      - ./airflow/logs:/opt/airflow/logs
      - ./airflow/plugins:/opt/airflow/plugins
    command: webserver

  airflow-scheduler:
    image: apache/airflow:2.7.1
    depends_on:
      - airflow-webserver
    environment:
      AIRFLOW__CORE__EXECUTOR: CeleryExecutor
      AIRFLOW__CORE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
      AIRFLOW__CELERY__BROKER_URL: redis://redis:6379/0
      AIRFLOW__CELERY__RESULT_BACKEND: db+postgresql://airflow:airflow@postgres/airflow
    volumes:
      - ./airflow/dags:/opt/airflow/dags
      - ./airflow/logs:/opt/airflow/logs
      - ./airflow/plugins:/opt/airflow/plugins
    command: scheduler

  airflow-worker:
    image: apache/airflow:2.7.1
    depends_on:
      - airflow-scheduler
    environment:
      AIRFLOW__CORE__EXECUTOR: CeleryExecutor
      AIRFLOW__CORE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
      AIRFLOW__CELERY__BROKER_URL: redis://redis:6379/0
      AIRFLOW__CELERY__RESULT_BACKEND: db+postgresql://airflow:airflow@postgres/airflow
    volumes:
      - ./airflow/dags:/opt/airflow/dags
      - ./airflow/logs:/opt/airflow/logs
      - ./airflow/plugins:/opt/airflow/plugins
    command: celery worker

  dbt:
    image: ghcr.io/dbt-labs/dbt-snowflake:latest
    volumes:
      - ./dbt:/usr/app
    working_dir: /usr/app
    environment:
      DBT_PROFILES_DIR: /usr/app
    command: "dbt debug"

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - grafana-storage:/var/lib/grafana

volumes:
  pgdata:
  grafana-storage:
EOF

# -----------------------------
# 3. Create basic Prometheus config
# -----------------------------
echo "Creating Prometheus config..."
cat > monitoring/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

# -----------------------------
# 4. Start Docker containers
# -----------------------------
echo "Starting Docker containers..."
docker compose up -d

# -----------------------------
# 5. Initialize Airflow DB & create user
# -----------------------------
echo "Initializing Airflow..."
docker compose run airflow-webserver airflow db init
docker compose run airflow-webserver airflow users create \
  --username admin --password admin \
  --firstname Admin --lastname User \
  --role Admin --email admin@example.com

# -----------------------------
# 6. Install Great Expectations locally
# -----------------------------
echo "Installing Great Expectations locally via pip..."
pip install great_expectations

echo "Setup complete!"
echo "Access Airflow UI at http://localhost:8081"
echo "Access Spark UI at http://localhost:8080"
echo "Access Grafana at http://localhost:3000 (admin/admin)"
echo "Access Prometheus at http://localhost:9090"
echo "Run 'great_expectations init' inside the project root to set up GE."
