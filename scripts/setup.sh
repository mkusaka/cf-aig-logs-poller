#!/bin/bash

# Master setup script for cf-aig-logs-poller
# This script orchestrates the complete setup process

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🚀 Cloudflare AI Gateway to BigQuery - Complete Setup"
echo "===================================================="
echo ""
echo "This will set up both Cloudflare and Google Cloud Platform"
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js not found. Please install it first.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Node.js found: $(node --version)${NC}"

# Check if npm dependencies are installed
if [ ! -d "node_modules" ]; then
    echo ""
    echo "📦 Installing npm dependencies..."
    npm install
else
    echo -e "${GREEN}✅ npm dependencies already installed${NC}"
fi

# Create .dev.vars if it doesn't exist
if [ ! -f ".dev.vars" ]; then
    echo ""
    echo "📝 Creating .dev.vars file..."
    cp .dev.vars.example .dev.vars
    echo -e "${GREEN}✅ Created .dev.vars${NC}"
else
    echo -e "${GREEN}✅ .dev.vars already exists${NC}"
fi

# Main menu
echo ""
echo "=========================================="
echo "Choose setup option:"
echo "=========================================="
echo ""
echo "1) Complete Setup (Cloudflare + GCP)"
echo "2) Cloudflare Setup Only"
echo "3) Google Cloud Platform Setup Only"
echo "4) Test Connections"
echo "5) Exit"
echo ""
read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        echo ""
        echo -e "${BLUE}Starting complete setup...${NC}"
        echo ""
        
        # Run Cloudflare setup
        echo "Step 1/2: Cloudflare Setup"
        echo "------------------------"
        ./scripts/cf-setup.sh
        
        echo ""
        echo "Step 2/2: Google Cloud Platform Setup"
        echo "-----------------------------------"
        ./scripts/gcp-setup.sh
        
        echo ""
        echo -e "${GREEN}🎉 Complete setup finished!${NC}"
        echo ""
        echo "Final steps:"
        echo "1. Set secrets:"
        echo "   wrangler secret put CF_API_TOKEN"
        echo "   wrangler secret put GCP_SA_PRIVATE_KEY_PEM"
        echo ""
        echo "2. Deploy:"
        echo "   npm run deploy"
        echo ""
        echo "3. Monitor:"
        echo "   wrangler tail"
        ;;
        
    2)
        echo ""
        echo -e "${BLUE}Starting Cloudflare setup...${NC}"
        ./scripts/cf-setup.sh
        ;;
        
    3)
        echo ""
        echo -e "${BLUE}Starting GCP setup...${NC}"
        ./scripts/gcp-setup.sh
        ;;
        
    4)
        echo ""
        echo -e "${BLUE}Testing connections...${NC}"
        ./scripts/test-connection.sh
        ;;
        
    5)
        echo ""
        echo "Exiting setup..."
        exit 0
        ;;
        
    *)
        echo ""
        echo -e "${RED}Invalid choice. Please run the script again.${NC}"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "Setup Help:"
echo "=========================================="
echo ""
echo "📚 Documentation: README.md"
echo "🔧 Manual config: wrangler.toml"
echo "🔑 Secrets: Use 'wrangler secret put'"
echo "📊 BigQuery: sql/bigquery-setup.sql"
echo "🐛 Debug: wrangler tail"
echo ""
echo "For issues, check the troubleshooting section in README.md"