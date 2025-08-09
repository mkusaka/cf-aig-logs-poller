#!/bin/bash

# GCP Setup Script for cf-aig-logs-poller
# This script sets up everything needed on Google Cloud Platform

set -e

echo "☁️  Google Cloud Platform Setup for AI Gateway Logs"
echo "=================================================="
echo ""

# Configuration variables
PROJECT_ID="${1:-}"
DATASET_NAME="${2:-aig_logs}"
SERVICE_ACCOUNT_NAME="${3:-aig-logs-bq-writer}"
TABLE_NAME="aig_logs_raw"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}❌ gcloud CLI not found. Please install it first:${NC}"
    echo "   https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if bq is installed
if ! command -v bq &> /dev/null; then
    echo -e "${YELLOW}⚠️  bq CLI not found. Installing...${NC}"
    gcloud components install bq
fi

# Get or set project ID
if [ -z "$PROJECT_ID" ]; then
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
    if [ -n "$CURRENT_PROJECT" ]; then
        echo "Current GCP project: $CURRENT_PROJECT"
        read -p "Use this project? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            PROJECT_ID=$CURRENT_PROJECT
        else
            read -p "Enter your GCP project ID: " PROJECT_ID
        fi
    else
        read -p "Enter your GCP project ID: " PROJECT_ID
    fi
fi

echo -e "${GREEN}Using project: $PROJECT_ID${NC}"
gcloud config set project $PROJECT_ID

# Step 1: Enable required APIs
echo ""
echo "📦 Step 1: Enabling required APIs..."
gcloud services enable bigquery.googleapis.com --project=$PROJECT_ID || true
gcloud services enable iam.googleapis.com --project=$PROJECT_ID || true
echo -e "${GREEN}✅ APIs enabled${NC}"

# Step 2: Create BigQuery dataset
echo ""
echo "📊 Step 2: Creating BigQuery dataset..."
if bq ls -d --project_id=$PROJECT_ID | grep -q "^[[:space:]]*$DATASET_NAME[[:space:]]*$"; then
    echo -e "${YELLOW}Dataset $DATASET_NAME already exists${NC}"
else
    bq mk --dataset \
        --location=US \
        --description="Cloudflare AI Gateway logs dataset" \
        --project_id=$PROJECT_ID \
        $DATASET_NAME
    echo -e "${GREEN}✅ Dataset $DATASET_NAME created${NC}"
fi

# Step 3: Create BigQuery tables
echo ""
echo "📋 Step 3: Creating BigQuery tables..."

# Create raw table
cat > /tmp/bq_table_schema.sql << 'EOF'
CREATE TABLE IF NOT EXISTS `PROJECT_ID.DATASET_NAME.aig_logs_raw`
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
EOF

# Replace placeholders
sed -i.bak "s/PROJECT_ID/$PROJECT_ID/g" /tmp/bq_table_schema.sql
sed -i.bak "s/DATASET_NAME/$DATASET_NAME/g" /tmp/bq_table_schema.sql

# Create table
bq query --use_legacy_sql=false < /tmp/bq_table_schema.sql
echo -e "${GREEN}✅ Table aig_logs_raw created${NC}"

# Create deduplicated view
echo ""
echo "👁️  Creating deduplicated view..."
bq query --use_legacy_sql=false << EOF
CREATE OR REPLACE VIEW \`$PROJECT_ID.$DATASET_NAME.aig_logs\` AS
SELECT * EXCEPT(rn)
FROM (
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY id ORDER BY created_at DESC) AS rn
  FROM \`$PROJECT_ID.$DATASET_NAME.aig_logs_raw\`
)
WHERE rn = 1;
EOF
echo -e "${GREEN}✅ View aig_logs created${NC}"

# Step 4: Create service account
echo ""
echo "🔐 Step 4: Creating service account..."
SA_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe $SA_EMAIL --project=$PROJECT_ID &>/dev/null; then
    echo -e "${YELLOW}Service account $SA_EMAIL already exists${NC}"
else
    gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name="AI Gateway Logs to BigQuery Writer" \
        --project=$PROJECT_ID
    echo -e "${GREEN}✅ Service account created${NC}"
fi

# Step 5: Grant permissions
echo ""
echo "🔑 Step 5: Granting BigQuery permissions..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/bigquery.dataEditor" \
    --condition=None \
    --quiet

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/bigquery.jobUser" \
    --condition=None \
    --quiet

echo -e "${GREEN}✅ Permissions granted${NC}"

# Step 6: Create service account key
echo ""
echo "🔑 Step 6: Creating service account key..."
KEY_FILE="gcp-service-account-key.json"

if [ -f "$KEY_FILE" ]; then
    echo -e "${YELLOW}⚠️  Key file already exists. Skipping...${NC}"
    echo "   If you need a new key, delete $KEY_FILE first"
else
    gcloud iam service-accounts keys create $KEY_FILE \
        --iam-account=$SA_EMAIL \
        --project=$PROJECT_ID
    echo -e "${GREEN}✅ Key saved to $KEY_FILE${NC}"
    
    # Extract private key for Cloudflare Worker
    echo ""
    echo "📝 Extracting private key for Cloudflare Worker..."
    PRIVATE_KEY=$(cat $KEY_FILE | jq -r '.private_key')
    
    echo ""
    echo "=========================================="
    echo "IMPORTANT: Save these values for wrangler.toml and secrets:"
    echo "=========================================="
    echo ""
    echo "For wrangler.toml:"
    echo "  GCP_BQ_PROJECT = \"$PROJECT_ID\""
    echo "  GCP_BQ_DATASET = \"$DATASET_NAME\""
    echo "  GCP_BQ_TABLE = \"aig_logs_raw\""
    echo "  GCP_SA_EMAIL = \"$SA_EMAIL\""
    echo ""
    echo "For secrets (run this command):"
    echo "  wrangler secret put GCP_SA_PRIVATE_KEY_PEM"
    echo ""
    echo "Then paste this private key (including BEGIN/END lines):"
    echo "$PRIVATE_KEY"
    echo ""
    echo "=========================================="
fi

# Step 7: Test BigQuery access
echo ""
echo "🧪 Step 7: Testing BigQuery access..."
TEST_QUERY="SELECT 1 as test FROM \`$PROJECT_ID.$DATASET_NAME.aig_logs_raw\` LIMIT 1"
if bq query --use_legacy_sql=false "$TEST_QUERY" &>/dev/null; then
    echo -e "${GREEN}✅ BigQuery access test successful${NC}"
else
    echo -e "${YELLOW}⚠️  BigQuery test query failed (this is normal if table is empty)${NC}"
fi

# Summary
echo ""
echo "🎉 GCP Setup Complete!"
echo ""
echo "Summary:"
echo "  Project: $PROJECT_ID"
echo "  Dataset: $DATASET_NAME"
echo "  Table: aig_logs_raw"
echo "  View: aig_logs"
echo "  Service Account: $SA_EMAIL"
if [ -f "$KEY_FILE" ]; then
    echo "  Key File: $KEY_FILE"
fi
echo ""
echo "Next steps:"
echo "1. Update wrangler.toml with the values shown above"
echo "2. Set the private key as a secret using wrangler"
echo "3. Deploy the worker with: pnpm run deploy"
echo ""
echo "To monitor in BigQuery:"
echo "  bq query --use_legacy_sql=false 'SELECT COUNT(*) FROM \`$PROJECT_ID.$DATASET_NAME.aig_logs\`'"