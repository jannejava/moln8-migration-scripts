#!/bin/bash

# Voyager Security Upgrade Script
# Replaces tcg/voyager with eastwest/voyager (security-patched fork)
# Package is served via Satis - no repo config needed in sites

set -e

KUNDER_DIR="/Users/janne/Sites/kunder"
DRY_RUN=false
COMPOSER_UPDATE=false

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [OPTIONS] [SITE_DIR...]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be changed"
    echo "  --update     Run composer update after"
    echo "  --all        Process all sites with tcg/voyager"
    echo ""
    echo "Examples:"
    echo "  $0 --dry-run --all"
    echo "  $0 --all --update"
    echo "  $0 ogonfonden.se sydon.se"
}

find_voyager_sites() {
    grep -l '"tcg/voyager"' "$KUNDER_DIR"/*/composer.json 2>/dev/null | while read -r f; do
        dirname "$f" | xargs basename
    done
}

process_site() {
    local site="$1"
    local file="$KUNDER_DIR/$site/composer.json"

    if [ ! -f "$file" ]; then
        echo -e "${RED}$site: composer.json not found${NC}"
        return 1
    fi

    if grep -q '"eastwest/voyager"' "$file"; then
        echo -e "${GREEN}$site: already upgraded${NC}"
        return 0
    fi

    if ! grep -q '"tcg/voyager"' "$file"; then
        echo -e "${YELLOW}$site: no tcg/voyager found${NC}"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}$site: would replace tcg/voyager -> eastwest/voyager${NC}"
        return 0
    fi

    # Replace the package
    sed -i '' 's/"tcg\/voyager": "[^"]*"/"eastwest\/voyager": "^1.8.1"/' "$file"
    echo -e "${GREEN}$site: upgraded${NC}"

    if [ "$COMPOSER_UPDATE" = true ]; then
        echo "  Running composer update..."
        (cd "$KUNDER_DIR/$site" && composer update eastwest/voyager --no-interaction 2>&1 | tail -3)
    fi
}

# Parse args
SITES=()
PROCESS_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --update) COMPOSER_UPDATE=true; shift ;;
        --all) PROCESS_ALL=true; shift ;;
        --help) usage; exit 0 ;;
        *) SITES+=("$1"); shift ;;
    esac
done

if [ "$PROCESS_ALL" = true ]; then
    while IFS= read -r site; do
        SITES+=("$site")
    done < <(find_voyager_sites)
fi

if [ ${#SITES[@]} -eq 0 ]; then
    echo "No sites specified. Use --all or provide site names."
    exit 1
fi

echo "================================"
echo "Voyager Security Upgrade"
echo "Sites: ${#SITES[@]}"
[ "$DRY_RUN" = true ] && echo -e "${YELLOW}DRY RUN${NC}"
echo "================================"

for site in "${SITES[@]}"; do
    process_site "$site"
done

echo ""
echo "Done. Remember to rebuild Satis first!"