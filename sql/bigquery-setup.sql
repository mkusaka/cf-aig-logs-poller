-- BigQuery setup SQL for cf-aig-logs-poller
-- Run these queries in your BigQuery console

-- 1. Create the raw logs table (partitioned and clustered)
CREATE TABLE IF NOT EXISTS `your_project.your_dataset.aig_logs_raw`
PARTITION BY DATE(created_at)
CLUSTER BY provider, model, success, id AS
SELECT
  CAST(NULL AS STRING) AS id,
  TIMESTAMP(NULL) AS created_at,
  STRING(NULL) AS provider,
  STRING(NULL) AS model,
  STRING(NULL) AS model_type,
  BOOL(NULL) AS success,
  INT64(NULL) AS status_code,
  BOOL(NULL) AS cached,
  FLOAT64(NULL) AS duration,
  INT64(NULL) AS tokens_in,
  INT64(NULL) AS tokens_out,
  FLOAT64(NULL) AS cost,
  STRING(NULL) AS request_type,
  STRING(NULL) AS request_content_type,
  STRING(NULL) AS response_content_type,
  STRING(NULL) AS path,
  INT64(NULL) AS step,
  CURRENT_TIMESTAMP() AS ingested_at;

-- 2. Create deduplicated view (use this for queries)
CREATE OR REPLACE VIEW `your_project.your_dataset.aig_logs` AS
SELECT * EXCEPT(rn)
FROM (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) AS rn
  FROM `your_project.your_dataset.aig_logs_raw`
)
WHERE rn = 1;

-- 3. Optional: Create materialized table with MERGE (for better query performance)
-- Run this as a scheduled query if needed
CREATE TABLE IF NOT EXISTS `your_project.your_dataset.aig_logs_canonical`
LIKE `your_project.your_dataset.aig_logs_raw`;

-- Merge query to run periodically (e.g., hourly)
MERGE `your_project.your_dataset.aig_logs_canonical` T
USING (
  SELECT * FROM `your_project.your_dataset.aig_logs_raw`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) = 1
) S
ON T.id = S.id
WHEN MATCHED THEN UPDATE SET
  created_at = S.created_at,
  provider = S.provider,
  model = S.model,
  model_type = S.model_type,
  success = S.success,
  status_code = S.status_code,
  cached = S.cached,
  duration = S.duration,
  tokens_in = S.tokens_in,
  tokens_out = S.tokens_out,
  cost = S.cost,
  request_type = S.request_type,
  request_content_type = S.request_content_type,
  response_content_type = S.response_content_type,
  path = S.path,
  step = S.step,
  ingested_at = S.ingested_at
WHEN NOT MATCHED THEN INSERT ROW;

-- 4. Sample queries for analysis

-- Recent activity by model
SELECT 
  TIMESTAMP_TRUNC(created_at, MINUTE) AS minute,
  model,
  COUNT(*) AS requests,
  SUM(tokens_in) AS total_tokens_in,
  SUM(tokens_out) AS total_tokens_out,
  SUM(cost) AS total_cost,
  AVG(duration) AS avg_duration_ms,
  SUM(CASE WHEN success THEN 1 ELSE 0 END) / COUNT(*) AS success_rate
FROM `your_project.your_dataset.aig_logs`
WHERE created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY minute, model
ORDER BY minute DESC;

-- Top providers and models
SELECT 
  provider,
  model,
  COUNT(*) AS requests,
  SUM(cost) AS total_cost,
  AVG(duration) AS avg_duration_ms
FROM `your_project.your_dataset.aig_logs`
WHERE created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY provider, model
ORDER BY requests DESC
LIMIT 20;

-- Error analysis
SELECT 
  status_code,
  provider,
  model,
  COUNT(*) AS error_count,
  MIN(created_at) AS first_seen,
  MAX(created_at) AS last_seen
FROM `your_project.your_dataset.aig_logs`
WHERE NOT success
  AND created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY status_code, provider, model
ORDER BY error_count DESC;

-- Cost breakdown by hour
SELECT 
  TIMESTAMP_TRUNC(created_at, HOUR) AS hour,
  provider,
  SUM(cost) AS hourly_cost,
  SUM(tokens_in + tokens_out) AS total_tokens
FROM `your_project.your_dataset.aig_logs`
WHERE created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY hour, provider
ORDER BY hour DESC;