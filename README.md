# cf-aig-logs-poller

Cloudflare AI Gateway logs to BigQuery streaming solution. This Worker fetches logs from Cloudflare AI Gateway API and streams them to BigQuery for analysis with Looker Studio.

## Features

- **Incremental log fetching** with cursor-based pagination
- **Deduplication** using KV store with TTL
- **Forward and backfill** processes running on different cron schedules
- **BigQuery streaming** with best-effort deduplication
- **Resilient error handling** with detailed logging
- **Configurable batch sizes** and processing intervals

## Architecture

```
Cloudflare AI Gateway
        ↓
  Logs API (REST)
        ↓
  Cloudflare Worker
   (Cron triggers)
        ↓
  BigQuery insertAll
        ↓
    BigQuery Table
  (Partitioned by date)
        ↓
   Looker Studio
```

## Prerequisites

1. **Cloudflare Account** with AI Gateway enabled
2. **Google Cloud Project** with BigQuery API enabled
3. **Service Account** with BigQuery Data Editor role
4. **Cloudflare API Token** with AI Gateway read permissions
5. **pnpm** package manager (`npm install -g pnpm`)
6. **Wrangler CLI** installed (`pnpm install -g wrangler`)

## Setup

### Quick Start (Automated Setup)

```bash
git clone https://github.com/yourusername/cf-aig-logs-poller.git
cd cf-aig-logs-poller
pnpm install

# Run the complete setup wizard
pnpm run setup
# Choose option 1 for complete setup (Cloudflare + GCP)
```

The setup wizard will:
- Configure Cloudflare KV namespaces with descriptive names
- Set up BigQuery dataset and tables
- Create service account with proper permissions
- Update configuration files automatically

### Manual Setup

#### 1. Clone and Install

```bash
git clone https://github.com/yourusername/cf-aig-logs-poller.git
cd cf-aig-logs-poller
pnpm install
```

#### 2. Create KV Namespaces

KV namespaces are created with descriptive names for better organization:

```bash
# Create STATE_KV namespace (stores cursor positions)
wrangler kv:namespace create "STATE_KV"
# Note the ID, it will look like: { binding = "STATE_KV", id = "abc123..." }

# Create IDS_KV namespace (stores processed log IDs for deduplication)
wrangler kv:namespace create "IDS_KV"
# Note the ID, it will look like: { binding = "IDS_KV", id = "def456..." }
```

Update the IDs in `wrangler.toml` with the output from above commands.

#### 3. Create BigQuery Table

Run this SQL in BigQuery to create the destination table:

```sql
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
```

Create a view for deduplication:

```sql
CREATE OR REPLACE VIEW `your_project.your_dataset.aig_logs` AS
SELECT * EXCEPT(rn)
FROM (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) AS rn
  FROM `your_project.your_dataset.aig_logs_raw`
)
WHERE rn = 1;
```

Or use the automated script:
```bash
./scripts/gcp-setup.sh your-project-id
```

#### 4. Configure Environment Variables

Copy the example file and fill in your values:

```bash
cp .dev.vars.example .dev.vars
```

Edit `.dev.vars` with your actual values:
- Cloudflare API token and account details
- GCP service account credentials
- BigQuery project and dataset info

#### 5. Set Secrets

```bash
# Set Cloudflare API token
wrangler secret put CF_API_TOKEN

# Set GCP service account private key
wrangler secret put GCP_SA_PRIVATE_KEY_PEM
```

#### 6. Update Configuration

Edit `wrangler.toml` to set your environment-specific values:
- KV namespace IDs
- Account IDs
- Gateway ID
- GCP project details

## Deployment

### Development

```bash
# Run locally (for testing)
pnpm run dev
```

### Production

```bash
# Deploy to Cloudflare Workers
pnpm run deploy
```

## Monitoring

### Check Worker Logs

```bash
wrangler tail
```

### Check KV State

```bash
# Check forward cursor
wrangler kv:key get --namespace-id=YOUR_STATE_KV_ID "forward"

# Check oldest timestamp for backfill
wrangler kv:key get --namespace-id=YOUR_STATE_KV_ID "oldest"
```

### BigQuery Validation

```sql
-- Check recent logs
SELECT 
  created_at,
  provider,
  model,
  success,
  tokens_in,
  tokens_out,
  cost
FROM `your_project.your_dataset.aig_logs`
WHERE created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY created_at DESC
LIMIT 100;

-- Check for duplicates
SELECT 
  id,
  COUNT(*) as count
FROM `your_project.your_dataset.aig_logs_raw`
WHERE created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY id
HAVING count > 1;
```

## Configuration Options

| Variable | Default | Description |
|----------|---------|-------------|
| `DEDUP_TTL_DAYS` | 45 | Days to keep deduplication entries |
| `LOG_LEVEL` | info | Logging level (debug, info, warn, error) |
| `FORWARD_MAX_PAGES` | 20 | Max pages per forward fetch |
| `BACKFILL_MAX_PAGES` | 40 | Max pages per backfill fetch |
| `LOGS_PER_PAGE` | 50 | Logs per API page |

## Cron Schedule

- **Every minute** (`*/1 * * * *`): Forward process - fetches new logs
- **Every hour** (`0 * * * *`): Backfill process - fetches historical logs

## Cost Considerations

- **BigQuery Streaming**: ~$0.05 per GB ingested
- **BigQuery Storage**: $0.02 per GB/month (with partitioning)
- **BigQuery Queries**: $5 per TB scanned (use partitioning to reduce)
- **Cloudflare Workers**: Free tier includes 100,000 requests/day
- **KV Storage**: Free tier includes 100,000 reads/day, 1,000 writes/day

## Troubleshooting

### Common Issues

1. **Authentication Errors**
   - Verify service account has BigQuery Data Editor role
   - Check private key format (should include newlines)
   - Ensure API token has correct permissions

2. **Duplicate Logs**
   - Check if IDS_KV is properly configured
   - Verify TTL settings are appropriate
   - Use the deduplication view instead of raw table

3. **Missing Logs**
   - Check cursor position in STATE_KV
   - Verify cron triggers are running
   - Check Worker logs for errors

4. **BigQuery Errors**
   - Ensure table exists with correct schema
   - Verify project/dataset names
   - Check quota limits

## Development

### Project Structure

```
cf-aig-logs-poller/
├── src/
│   ├── index.ts         # Main Worker entry point
│   ├── types.ts         # TypeScript type definitions
│   ├── ai-gateway.ts    # AI Gateway API client
│   ├── bigquery.ts      # BigQuery integration
│   ├── google-auth.ts   # Google OAuth2 authentication
│   ├── dedup.ts         # Deduplication logic
│   └── logger.ts        # Logging utilities
├── wrangler.toml        # Worker configuration
├── package.json         # Node dependencies
├── tsconfig.json        # TypeScript configuration
└── README.md           # This file
```

### Testing

```bash
# Type checking
pnpm run type-check

# Linting
pnpm run lint

# Format code
pnpm run format
```

## License

MIT