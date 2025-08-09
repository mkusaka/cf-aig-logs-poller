#!/bin/bash

# Cloudflare Setup Script for cf-aig-logs-poller
# This script sets up everything needed on Cloudflare

set -e

echo "🔥 Cloudflare Setup for AI Gateway Logs"
echo "======================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if wrangler is installed
if ! command -v wrangler &> /dev/null; then
    echo -e "${RED}❌ Wrangler CLI not found. Installing...${NC}"
    npm install -g wrangler
fi

echo -e "${GREEN}✅ Wrangler CLI found${NC}"

# Step 1: Login to Cloudflare
echo ""
echo "🔐 Step 1: Authenticating with Cloudflare..."
if wrangler whoami &>/dev/null; then
    ACCOUNT_INFO=$(wrangler whoami 2>&1 | grep -E "Account|Email" || true)
    echo -e "${GREEN}Already logged in:${NC}"
    echo "$ACCOUNT_INFO"
else
    echo "Please login to Cloudflare:"
    wrangler login
fi

# Step 2: Get Account and Gateway information
echo ""
echo "📋 Step 2: Getting account information..."

# Get account ID
ACCOUNT_ID=$(wrangler whoami 2>&1 | grep -oP '(?<=Account ID:\s)[\w-]+' || echo "")
if [ -z "$ACCOUNT_ID" ]; then
    read -p "Enter your Cloudflare Account ID: " ACCOUNT_ID
fi
echo -e "${GREEN}Account ID: $ACCOUNT_ID${NC}"

# Get AI Gateway ID
echo ""
echo "To find your AI Gateway ID:"
echo "1. Go to https://dash.cloudflare.com/"
echo "2. Navigate to AI > AI Gateway"
echo "3. Click on your gateway"
echo "4. Copy the ID from the URL or settings"
echo ""
read -p "Enter your AI Gateway ID: " GATEWAY_ID

# Step 3: Create KV namespaces with descriptive names
echo ""
echo "📚 Step 3: Creating KV namespaces..."

# Create STATE_KV namespace
echo ""
echo "Creating cursor state namespace..."
STATE_OUTPUT=$(wrangler kv:namespace create "STATE_KV" 2>&1 || true)
STATE_ID=$(echo "$STATE_OUTPUT" | grep -oP '(?<=id = ")[\w-]+' || echo "")

if [ -z "$STATE_ID" ]; then
    # Try to list existing namespaces
    echo "Checking existing namespaces..."
    EXISTING_STATE=$(wrangler kv:namespace list 2>&1 | grep -E "AIG_LOGS_BQ_STATE|cf-aig-logs-to-bq-STATE_KV" || echo "")
    if [ -n "$EXISTING_STATE" ]; then
        STATE_ID=$(echo "$EXISTING_STATE" | grep -oP '"id":\s*"([^"]+)"' | grep -oP '[\w-]+$' || echo "")
        echo -e "${YELLOW}Found existing STATE_KV namespace: $STATE_ID${NC}"
    fi
fi

if [ -n "$STATE_ID" ]; then
    echo -e "${GREEN}✅ STATE_KV namespace ID: $STATE_ID${NC}"
else
    echo -e "${RED}❌ Failed to create/find STATE_KV namespace${NC}"
fi

# Create IDS_KV namespace
echo ""
echo "Creating deduplication namespace..."
IDS_OUTPUT=$(wrangler kv:namespace create "IDS_KV" 2>&1 || true)
IDS_ID=$(echo "$IDS_OUTPUT" | grep -oP '(?<=id = ")[\w-]+' || echo "")

if [ -z "$IDS_ID" ]; then
    # Try to list existing namespaces
    EXISTING_IDS=$(wrangler kv:namespace list 2>&1 | grep -E "AIG_LOGS_BQ_DEDUP|cf-aig-logs-to-bq-IDS_KV" || echo "")
    if [ -n "$EXISTING_IDS" ]; then
        IDS_ID=$(echo "$EXISTING_IDS" | grep -oP '"id":\s*"([^"]+)"' | grep -oP '[\w-]+$' || echo "")
        echo -e "${YELLOW}Found existing IDS_KV namespace: $IDS_ID${NC}"
    fi
fi

if [ -n "$IDS_ID" ]; then
    echo -e "${GREEN}✅ IDS_KV namespace ID: $IDS_ID${NC}"
else
    echo -e "${RED}❌ Failed to create/find IDS_KV namespace${NC}"
fi

# Step 4: Create API Token (if needed)
echo ""
echo "🔑 Step 4: API Token Setup..."
echo ""
echo "You need a Cloudflare API token with these permissions:"
echo "  - Account: AI Gateway:Read"
echo "  - Account: Account Analytics:Read"
echo ""
echo "Create one at: https://dash.cloudflare.com/profile/api-tokens"
echo ""
echo "Token template: Custom token with:"
echo "  - Permissions:"
echo "    * Account > AI Gateway > Read"
echo "  - Account Resources:"
echo "    * Include > Your Account"
echo ""
read -p "Do you have an API token ready? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Great! You'll set it as a secret later.${NC}"
else
    echo "Please create one and come back!"
    echo "Opening browser..."
    open "https://dash.cloudflare.com/profile/api-tokens" 2>/dev/null || \
    xdg-open "https://dash.cloudflare.com/profile/api-tokens" 2>/dev/null || \
    echo "Please visit: https://dash.cloudflare.com/profile/api-tokens"
fi

# Step 5: Update wrangler.toml
echo ""
echo "📝 Step 5: Updating wrangler.toml..."

# Backup existing wrangler.toml
cp wrangler.toml wrangler.toml.bak

# Update wrangler.toml with actual values
if [ -n "$STATE_ID" ] && [ -n "$IDS_ID" ]; then
    # Use sed to update the file
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/id = \"YOUR_STATE_KV_ID\"/id = \"$STATE_ID\"/" wrangler.toml
        sed -i '' "s/id = \"YOUR_IDS_KV_ID\"/id = \"$IDS_ID\"/" wrangler.toml
        sed -i '' "s/CF_ACCOUNT_ID = \"YOUR_CF_ACCOUNT_ID\"/CF_ACCOUNT_ID = \"$ACCOUNT_ID\"/" wrangler.toml
        sed -i '' "s/AIG_GATEWAY_ID = \"YOUR_AIG_GATEWAY_ID\"/AIG_GATEWAY_ID = \"$GATEWAY_ID\"/" wrangler.toml
    else
        # Linux
        sed -i "s/id = \"YOUR_STATE_KV_ID\"/id = \"$STATE_ID\"/" wrangler.toml
        sed -i "s/id = \"YOUR_IDS_KV_ID\"/id = \"$IDS_ID\"/" wrangler.toml
        sed -i "s/CF_ACCOUNT_ID = \"YOUR_CF_ACCOUNT_ID\"/CF_ACCOUNT_ID = \"$ACCOUNT_ID\"/" wrangler.toml
        sed -i "s/AIG_GATEWAY_ID = \"YOUR_AIG_GATEWAY_ID\"/AIG_GATEWAY_ID = \"$GATEWAY_ID\"/" wrangler.toml
    fi
    echo -e "${GREEN}✅ wrangler.toml updated with your values${NC}"
else
    echo -e "${YELLOW}⚠️  Please manually update wrangler.toml with the KV namespace IDs${NC}"
fi

# Step 6: Summary and next steps
echo ""
echo "=========================================="
echo "📋 Configuration Summary"
echo "=========================================="
echo ""
echo -e "${BLUE}Cloudflare Settings:${NC}"
echo "  Account ID: $ACCOUNT_ID"
echo "  AI Gateway ID: $GATEWAY_ID"
echo "  STATE_KV ID: ${STATE_ID:-<NEEDS MANUAL UPDATE>}"
echo "  IDS_KV ID: ${IDS_ID:-<NEEDS MANUAL UPDATE>}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Set your Cloudflare API token:"
echo -e "   ${GREEN}wrangler secret put CF_API_TOKEN${NC}"
echo ""
echo "2. Run GCP setup (if not done yet):"
echo -e "   ${GREEN}./scripts/gcp-setup.sh${NC}"
echo ""
echo "3. Set your GCP service account key:"
echo -e "   ${GREEN}wrangler secret put GCP_SA_PRIVATE_KEY_PEM${NC}"
echo ""
echo "4. Deploy the worker:"
echo -e "   ${GREEN}npm run deploy${NC}"
echo ""
echo "5. Monitor logs:"
echo -e "   ${GREEN}wrangler tail${NC}"
echo ""
echo "=========================================="

# Create a config summary file
cat > cf-config.txt << EOF
# Cloudflare Configuration
# Generated on $(date)

CF_ACCOUNT_ID=$ACCOUNT_ID
AIG_GATEWAY_ID=$GATEWAY_ID
STATE_KV_ID=$STATE_ID
IDS_KV_ID=$IDS_ID

# Add these to wrangler.toml if not already updated
EOF

echo ""
echo -e "${GREEN}✅ Configuration saved to cf-config.txt${NC}"
echo ""
echo "🎉 Cloudflare setup complete!"