#!/bin/bash

# Test connection script for cf-aig-logs-poller
# Tests Cloudflare API and BigQuery connectivity

set -e

echo "🔍 Testing Connections"
echo "====================="
echo ""

# Load environment variables
if [ -f ".dev.vars" ]; then
    export $(cat .dev.vars | grep -v '^#' | xargs)
else
    echo "❌ .dev.vars file not found"
    exit 1
fi

# Test Cloudflare API
echo "Testing Cloudflare AI Gateway API..."
CF_API_URL="https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/ai-gateway/gateways/${AIG_GATEWAY_ID}/logs?per_page=1"

response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer ${CF_API_TOKEN}" "$CF_API_URL")
http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | head -n-1)

if [ "$http_code" = "200" ]; then
    echo "✅ Cloudflare API connection successful"
    echo "   Found logs: $(echo "$body" | grep -o '"result":\[' | wc -l)"
else
    echo "❌ Cloudflare API connection failed (HTTP $http_code)"
    echo "   Response: $body"
fi

echo ""

# Test BigQuery (using bq CLI if available)
if command -v bq &> /dev/null; then
    echo "Testing BigQuery connection..."
    
    if bq ls -p "${GCP_BQ_PROJECT}" &> /dev/null; then
        echo "✅ BigQuery connection successful"
        
        # Check if dataset exists
        if bq ls -d "${GCP_BQ_PROJECT}:${GCP_BQ_DATASET}" &> /dev/null; then
            echo "✅ Dataset ${GCP_BQ_DATASET} exists"
            
            # Check if table exists
            if bq ls "${GCP_BQ_PROJECT}:${GCP_BQ_DATASET}.${GCP_BQ_TABLE}" &> /dev/null; then
                echo "✅ Table ${GCP_BQ_TABLE} exists"
            else
                echo "⚠️  Table ${GCP_BQ_TABLE} does not exist - create it using sql/bigquery-setup.sql"
            fi
        else
            echo "⚠️  Dataset ${GCP_BQ_DATASET} does not exist"
        fi
    else
        echo "❌ BigQuery connection failed"
    fi
else
    echo "ℹ️  bq CLI not found - skipping BigQuery test"
    echo "   Install with: gcloud components install bq"
fi

echo ""
echo "🎉 Connection tests complete!"