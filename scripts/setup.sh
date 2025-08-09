#!/bin/bash

# Setup script for cf-aig-logs-poller
# This script helps with initial setup and configuration

set -e

echo "🚀 Cloudflare AI Gateway to BigQuery Setup"
echo "==========================================="
echo ""

# Check if wrangler is installed
if ! command -v wrangler &> /dev/null; then
    echo "❌ Wrangler CLI not found. Please install it first:"
    echo "   npm install -g wrangler"
    exit 1
fi

echo "✅ Wrangler CLI found"

# Check if npm dependencies are installed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing npm dependencies..."
    npm install
else
    echo "✅ npm dependencies already installed"
fi

# Create KV namespaces
echo ""
echo "📚 Creating KV namespaces..."
echo "Note: Save the IDs for updating wrangler.toml"
echo ""

echo "Creating STATE_KV namespace..."
wrangler kv:namespace create "STATE_KV" 2>/dev/null || echo "STATE_KV might already exist"

echo ""
echo "Creating IDS_KV namespace..."
wrangler kv:namespace create "IDS_KV" 2>/dev/null || echo "IDS_KV might already exist"

# Create .dev.vars if it doesn't exist
if [ ! -f ".dev.vars" ]; then
    echo ""
    echo "📝 Creating .dev.vars file..."
    cp .dev.vars.example .dev.vars
    echo "✅ Created .dev.vars - please edit it with your actual values"
else
    echo "✅ .dev.vars already exists"
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "1. Update KV namespace IDs in wrangler.toml"
echo "2. Edit .dev.vars with your actual credentials"
echo "3. Create BigQuery table using the SQL in README.md"
echo "4. Set secrets using:"
echo "   wrangler secret put CF_API_TOKEN"
echo "   wrangler secret put GCP_SA_PRIVATE_KEY_PEM"
echo "5. Deploy with: npm run deploy"