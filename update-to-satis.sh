#!/bin/bash

# Script to update existing sites to use new Satis repository
# Usage: ./update-to-satis.sh [path-to-site]

SATIS_URL="https://satis.eastwest.se"
SATIS_USERNAME="moln8-packages"
SATIS_PASSWORD="ocEAQk2y3bXJv4mSZljN"
OLD_REPO_URL="https://repo.packagist.com/moln8/"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to update a single site
update_site() {
    local SITE_PATH="$1"
    
    echo -e "${YELLOW}Updating site: ${SITE_PATH}${NC}"
    
    # Check if composer.json exists
    if [ ! -f "$SITE_PATH/composer.json" ]; then
        echo -e "${RED}Error: composer.json not found in $SITE_PATH${NC}"
        return 1
    fi
    
    # Change to site directory
    cd "$SITE_PATH" || return 1
    
    # Backup composer.json
    cp composer.json composer.json.backup.$(date +%Y%m%d_%H%M%S)
    echo "Created backup of composer.json"
    
    # Update repository URL in composer.json
    if grep -q "$OLD_REPO_URL" composer.json; then
        # Use sed to replace the old URL with the new one
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s|$OLD_REPO_URL|$SATIS_URL|g" composer.json
        else
            # Linux
            sed -i "s|$OLD_REPO_URL|$SATIS_URL|g" composer.json
        fi
        echo "Updated repository URL from $OLD_REPO_URL to $SATIS_URL"
    else
        echo "Old repository URL not found, checking if Satis URL already exists..."
        if grep -q "$SATIS_URL" composer.json; then
            echo "Satis URL already configured"
        else
            echo -e "${YELLOW}Warning: Neither old nor new repository URL found in composer.json${NC}"
        fi
    fi
    
    # Remove packagist.org: false if we want to keep using public packages
    if grep -q '"packagist.org": false' composer.json; then
        echo "Removing 'packagist.org: false' to allow public packages..."
        # Use jq to properly remove the packagist.org: false entry from repositories
        if command -v jq &> /dev/null; then
            jq 'if .repositories then .repositories |= map(select(has("packagist.org") | not)) else . end' composer.json > composer.json.tmp && mv composer.json.tmp composer.json
        else
            echo -e "${RED}Warning: jq not installed. Please install jq or manually remove 'packagist.org: false' from composer.json${NC}"
        fi
    fi
    
    # Create or update auth.json
    if [ -f "auth.json" ]; then
        cp auth.json auth.json.backup.$(date +%Y%m%d_%H%M%S)
        echo "Created backup of auth.json"
    fi
    
    # Create auth.json with credentials
    cat > auth.json <<EOF
{
    "http-basic": {
        "satis.eastwest.se": {
            "username": "$SATIS_USERNAME",
            "password": "$SATIS_PASSWORD"
        }
    }
}
EOF
    echo "Created/updated auth.json with Satis credentials"
    
    # Add auth.json to .gitignore if not already there
    if [ -f ".gitignore" ]; then
        if ! grep -q "^auth.json$" .gitignore; then
            echo "auth.json" >> .gitignore
            echo "Added auth.json to .gitignore"
        fi
    else
        echo "auth.json" > .gitignore
        echo "Created .gitignore with auth.json"
    fi
    
    # Clear composer cache
    composer clear-cache
    echo "Cleared composer cache"
    
    # Test the configuration
    echo -e "${YELLOW}Testing configuration...${NC}"
    if composer validate --no-check-all --no-check-publish 2>/dev/null; then
        echo -e "${GREEN}composer.json is valid${NC}"
        
        # Try to update dependencies
        echo -e "${YELLOW}Testing package resolution (dry-run)...${NC}"
        if composer update --dry-run 2>&1 | grep -q "Your requirements could not be resolved"; then
            echo -e "${RED}Warning: Some packages might not be available in the new repository${NC}"
            echo "You may need to check which packages are missing from Satis"
        else
            echo -e "${GREEN}Package resolution successful!${NC}"
        fi
    else
        echo -e "${RED}composer.json validation failed${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Site updated successfully!${NC}"
    echo "---"
    
    return 0
}

# Main script
main() {
    if [ $# -eq 0 ]; then
        # No arguments, update current directory
        update_site "."
    elif [ $# -eq 1 ]; then
        if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
            echo "Usage: $0 [path-to-site]"
            echo "       $0 --batch sites.txt"
            echo ""
            echo "Updates composer.json to use new Satis repository"
            echo ""
            echo "Options:"
            echo "  path-to-site    Path to the site to update (default: current directory)"
            echo "  --batch FILE    Update multiple sites listed in FILE (one path per line)"
            echo "  --help, -h      Show this help message"
            exit 0
        elif [ "$1" == "--batch" ]; then
            echo -e "${RED}Error: --batch requires a file path${NC}"
            echo "Usage: $0 --batch sites.txt"
            exit 1
        else
            # Single site path provided
            update_site "$1"
        fi
    elif [ $# -eq 2 ] && [ "$1" == "--batch" ]; then
        # Batch mode
        BATCH_FILE="$2"
        if [ ! -f "$BATCH_FILE" ]; then
            echo -e "${RED}Error: Batch file not found: $BATCH_FILE${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}Starting batch update...${NC}"
        echo "Reading sites from: $BATCH_FILE"
        echo ""
        
        SUCCESS_COUNT=0
        FAIL_COUNT=0
        
        while IFS= read -r site_path || [ -n "$site_path" ]; do
            # Skip empty lines and comments
            [[ -z "$site_path" || "$site_path" =~ ^# ]] && continue
            
            # Expand tilde to home directory
            site_path="${site_path/#\~/$HOME}"
            
            if [ -d "$site_path" ]; then
                if update_site "$site_path"; then
                    ((SUCCESS_COUNT++))
                else
                    ((FAIL_COUNT++))
                fi
            else
                echo -e "${RED}Directory not found: $site_path${NC}"
                ((FAIL_COUNT++))
            fi
        done < "$BATCH_FILE"
        
        echo ""
        echo -e "${GREEN}Batch update complete!${NC}"
        echo "Successfully updated: $SUCCESS_COUNT sites"
        [ $FAIL_COUNT -gt 0 ] && echo -e "${RED}Failed: $FAIL_COUNT sites${NC}"
    else
        echo -e "${RED}Error: Invalid arguments${NC}"
        echo "Usage: $0 [path-to-site]"
        echo "       $0 --batch sites.txt"
        exit 1
    fi
}

# Run main function
main "$@"