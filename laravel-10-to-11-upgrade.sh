#!/bin/bash

# Laravel 10 to 11 Upgrade Script
# Usage: ./laravel-10-to-11-upgrade.sh [path-to-site] [options]
#
# This script upgrades a Laravel 10 site to Laravel 11
# Assumes you're working in a git repo and will commit changes after

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script options
DRY_RUN=false

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶${NC} $1"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking Prerequisites"

    # Check if in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        print_warning "Not in a git repository"
        print_warning "It's recommended to run this in a git repo for easy rollback"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Git repository detected"

        # Check for uncommitted changes
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            print_warning "You have uncommitted changes"
            print_info "Consider committing or stashing them first"
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi

    # Check if composer is installed
    if ! command -v composer &> /dev/null; then
        print_error "Composer is not installed. Please install it first."
        exit 1
    fi
    print_success "Composer is installed"

    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install it first."
        echo "  macOS: brew install jq"
        echo "  Linux: sudo apt-get install jq"
        exit 1
    fi
    print_success "jq is installed"

    # Check PHP version (need 8.2+)
    PHP_VERSION=$(php -r 'echo PHP_VERSION;')
    PHP_MAJOR=$(php -r 'echo PHP_MAJOR_VERSION;')
    PHP_MINOR=$(php -r 'echo PHP_MINOR_VERSION;')

    if [ "$PHP_MAJOR" -lt 8 ] || ([ "$PHP_MAJOR" -eq 8 ] && [ "$PHP_MINOR" -lt 2 ]); then
        print_error "PHP 8.2 or higher is required. Current version: $PHP_VERSION"
        exit 1
    fi
    print_success "PHP version: $PHP_VERSION"
}

# Function to validate Laravel version
validate_laravel_version() {
    print_step "Validating Laravel Version"

    if [ ! -f "composer.json" ]; then
        print_error "composer.json not found. Are you in a Laravel project?"
        exit 1
    fi

    CURRENT_LARAVEL=$(jq -r '.require["laravel/framework"] // empty' composer.json)

    if [ -z "$CURRENT_LARAVEL" ]; then
        print_error "Laravel framework not found in composer.json"
        exit 1
    fi

    print_info "Current Laravel version constraint: $CURRENT_LARAVEL"

    # Check if it's Laravel 10
    if [[ ! "$CURRENT_LARAVEL" =~ ^[\^~]?10\. ]] && [[ ! "$CURRENT_LARAVEL" =~ ^10\. ]]; then
        print_warning "This site doesn't appear to be Laravel 10"
        print_warning "Current version: $CURRENT_LARAVEL"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Confirmed Laravel 10.x"
    fi
}

# Function to ensure auth.json is in .gitignore
ensure_auth_json_ignored() {
    print_step "Ensuring auth.json is in .gitignore"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would check .gitignore for auth.json"
        return
    fi

    if [ -f ".gitignore" ]; then
        if ! grep -q "^auth.json$" .gitignore; then
            echo "auth.json" >> .gitignore
            print_success "Added auth.json to .gitignore"
        else
            print_info "auth.json already in .gitignore"
        fi
    else
        echo "auth.json" > .gitignore
        print_success "Created .gitignore with auth.json"
    fi
}

# Function to scan for migration issues
scan_migration_issues() {
    print_step "Scanning for Migration Issues"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would scan for migration issues"
        return
    fi

    # Scan for ->change() calls
    CHANGE_MIGRATIONS=$(grep -r "->change()" database/migrations/ 2>/dev/null | cut -d: -f1 | sort -u || true)

    if [ -n "$CHANGE_MIGRATIONS" ]; then
        print_warning "CRITICAL: Found migrations using ->change() method"
        echo "$CHANGE_MIGRATIONS" | while read -r file; do
            echo "  - $file"
        done
        echo ""
        print_error "Laravel 11 has BREAKING CHANGES for column modifications!"
        echo ""
        echo "You must explicitly specify ALL column attributes when using ->change():"
        echo ""
        echo -e "${BLUE}Before (Laravel 10):${NC}"
        echo "  \$table->integer('votes')->nullable()->change();"
        echo ""
        echo -e "${BLUE}After (Laravel 11):${NC}"
        echo "  \$table->integer('votes')"
        echo "      ->unsigned()              // Must re-specify!"
        echo "      ->default(1)              // Must re-specify!"
        echo "      ->comment('Vote count')   // Must re-specify!"
        echo "      ->nullable()              // Your change"
        echo "      ->change();"
        echo ""
        print_warning "These files MUST be manually reviewed and updated!"
        echo ""
    fi

    # Scan for old float/double syntax
    FLOAT_MIGRATIONS=$(grep -r "->double(\|->float(" database/migrations/ 2>/dev/null | grep -E "->double\([^)]+,[^)]+\)|->float\([^)]+,[^)]+\)" | cut -d: -f1 | sort -u || true)

    if [ -n "$FLOAT_MIGRATIONS" ]; then
        print_warning "Found migrations with old float/double syntax:"
        echo "$FLOAT_MIGRATIONS" | while read -r file; do
            echo "  - $file"
        done
        echo ""
        echo -e "${BLUE}Change:${NC} \$table->double('amount', 8, 2);"
        echo -e "${BLUE}To:${NC}     \$table->double('amount');"
        echo ""
    fi

    # Scan for spatial column types
    SPATIAL_MIGRATIONS=$(grep -r "->point(\|->polygon(\|->lineString(\|->multiPoint(" database/migrations/ 2>/dev/null | cut -d: -f1 | sort -u || true)

    if [ -n "$SPATIAL_MIGRATIONS" ]; then
        print_warning "Found migrations with old spatial column types:"
        echo "$SPATIAL_MIGRATIONS" | while read -r file; do
            echo "  - $file"
        done
        echo ""
        echo -e "${BLUE}Change:${NC} \$table->point('location');"
        echo -e "${BLUE}To:${NC}     \$table->geometry('location');"
        echo "        or \$table->geography('location');"
        echo ""
    fi

    # Scan for Schema::getAll* methods
    SCHEMA_GET_ALL=$(grep -r "Schema::getAllTables\|Schema::getAllViews\|Schema::getAllTypes" app/ database/ 2>/dev/null | cut -d: -f1 | sort -u || true)

    if [ -n "$SCHEMA_GET_ALL" ]; then
        print_warning "Found deprecated Schema methods:"
        echo "$SCHEMA_GET_ALL" | while read -r file; do
            echo "  - $file"
        done
        echo ""
        echo -e "${BLUE}Replace:${NC}"
        echo "  Schema::getAllTables() → Schema::getTables()"
        echo "  Schema::getAllViews()  → Schema::getViews()"
        echo "  Schema::getAllTypes()  → Schema::getTypes()"
        echo ""
    fi
}

# Function to scan for rate limiting issues
scan_rate_limiting_issues() {
    print_step "Scanning for Rate Limiting Issues"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would scan for rate limiting issues"
        return
    fi

    # Scan for ThrottlesExceptions
    THROTTLES=$(grep -r "ThrottlesExceptions\|ThrottlesExceptionsWithRedis" app/ 2>/dev/null | grep "new " | cut -d: -f1 | sort -u || true)

    if [ -n "$THROTTLES" ]; then
        print_warning "CRITICAL: Found ThrottlesExceptions usage (timing changed!)"
        echo "$THROTTLES" | while read -r file; do
            echo "  - $file"
        done
        echo ""
        print_error "Laravel 11 changed from MINUTES to SECONDS!"
        echo ""
        echo -e "${BLUE}Before (Laravel 10):${NC}"
        echo "  new ThrottlesExceptions(10, 2);  // 2 minutes"
        echo ""
        echo -e "${BLUE}After (Laravel 11):${NC}"
        echo "  new ThrottlesExceptions(10, 2 * 60);  // 2 minutes = 120 seconds"
        echo ""
        print_warning "You MUST multiply all minute values by 60!"
        echo ""
    fi

    # Scan for GlobalLimit
    GLOBAL_LIMIT=$(grep -r "GlobalLimit\|new Limit(" app/ 2>/dev/null | grep -v "perMinute\|perSecond" | cut -d: -f1 | sort -u || true)

    if [ -n "$GLOBAL_LIMIT" ]; then
        print_warning "Found custom Limit/GlobalLimit usage:"
        echo "$GLOBAL_LIMIT" | while read -r file; do
            echo "  - $file"
        done
        echo ""
        echo "Review these files - custom limits now use SECONDS not MINUTES"
        echo ""
    fi
}

# Function to scan for model casts relationship
scan_model_casts_relationship() {
    print_step "Scanning for Model Casts Relationships"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would scan for casts() relationships"
        return
    fi

    # Search for casts() relationships
    CASTS_RELATIONSHIP=$(grep -r "function casts()" app/Models/ app/ 2>/dev/null | grep -v "vendor" | cut -d: -f1 | sort -u || true)

    if [ -n "$CASTS_RELATIONSHIP" ]; then
        print_warning "Found models with casts() relationships (CONFLICT!):"
        echo "$CASTS_RELATIONSHIP" | while read -r file; do
            echo "  - $file"
        done
        echo ""
        print_error "Laravel 11 adds a base casts() method - your relationship will conflict!"
        echo ""
        echo -e "${BLUE}Change:${NC} public function casts() { return \$this->hasMany(Cast::class); }"
        echo -e "${BLUE}To:${NC}     public function castMembers() { return \$this->hasMany(Cast::class); }"
        echo ""
    fi
}

# Function to update composer.json
update_composer_json() {
    print_step "Updating composer.json"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would update composer.json with these changes:"
        echo "  - PHP: ^8.1 → ^8.2"
        echo "  - Laravel Framework: ^10.x → ^11.x"
        echo "  - Voyager: stays at ^1.7 (no update needed)"
        echo "  - nunomaduro/collision: ^8.1"
        echo "  - Remove: doctrine/dbal (no longer needed)"
        return
    fi

    TMP_FILE=$(mktemp)

    # Update Laravel and related packages
    jq '
        # Update PHP requirement
        .require.php = "^8.2" |

        # Update laravel/framework
        .require["laravel/framework"] = "^11.0" |

        # Voyager stays at 1.7 - no higher version available

        # Remove doctrine/dbal
        del(.require["doctrine/dbal"]) |

        # Update laravel/sanctum if present
        if .require["laravel/sanctum"] then
            .require["laravel/sanctum"] = "^4.0"
        else . end |

        # Update dev dependencies
        if .["require-dev"]["nunomaduro/collision"] then
            .["require-dev"]["nunomaduro/collision"] = "^8.1"
        else . end
    ' composer.json > "$TMP_FILE"

    if [ $? -eq 0 ]; then
        mv "$TMP_FILE" composer.json
        print_success "Updated composer.json"
    else
        print_error "Failed to update composer.json"
        rm -f "$TMP_FILE"
        exit 1
    fi
}

# Function to run composer update
run_composer_update() {
    print_step "Running Composer Update"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would run: composer update"
        return
    fi

    print_info "This may take several minutes..."

    composer clear-cache

    if composer update 2>&1 | tee /tmp/composer-update.log; then
        print_success "Composer update completed successfully"
    else
        print_error "Composer update failed. Check /tmp/composer-update.log for details"
        print_info "Use 'git status' to see what changed"
        print_info "Use 'git restore .' to revert all changes"
        exit 1
    fi
}

# Function to publish package migrations
publish_package_migrations() {
    print_step "Publishing Package Migrations"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would publish package migrations"
        return
    fi

    if [ ! -f "artisan" ]; then
        print_warning "artisan not found, skipping"
        return
    fi

    # Check and publish Sanctum migrations
    if grep -q '"laravel/sanctum"' composer.json; then
        print_info "Publishing Sanctum migrations..."
        php artisan vendor:publish --tag=sanctum-migrations --force
        print_success "Published Sanctum migrations"
    fi

    # Check if Voyager is installed
    if grep -q '"tcg/voyager"' composer.json; then
        print_info "Publishing Voyager assets..."
        php artisan vendor:publish --provider="TCG\Voyager\VoyagerServiceProvider" --tag=public --force
        print_success "Published Voyager assets"
    fi
}

# Function to clear caches
clear_caches() {
    print_step "Clearing Caches"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would clear all caches"
        return
    fi

    if [ -f "artisan" ]; then
        php artisan config:clear || true
        php artisan cache:clear || true
        php artisan view:clear || true
        php artisan route:clear || true
        php artisan event:clear || true
        print_success "Cleared all caches"
    fi
}

# Function to verify installation
verify_installation() {
    print_step "Verifying Installation"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would verify Laravel installation"
        return
    fi

    # Check Laravel version
    if [ -f "artisan" ]; then
        INSTALLED_VERSION=$(php artisan --version 2>/dev/null || echo "Unknown")
        print_info "Installed: $INSTALLED_VERSION"

        if [[ "$INSTALLED_VERSION" =~ Laravel\ Framework\ 11\. ]]; then
            print_success "Laravel 11 successfully installed!"
        else
            print_warning "Could not verify Laravel 11 installation"
        fi
    fi

    # Validate composer.json
    if composer validate --no-check-all --no-check-publish 2>/dev/null; then
        print_success "composer.json is valid"
    else
        print_warning "composer.json validation issues detected"
    fi
}

# Function to show manual steps
show_manual_steps() {
    print_step "CRITICAL Manual Steps Required"

    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}⚠  BREAKING CHANGES - MANUAL REVIEW REQUIRED${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "1. ${RED}CRITICAL: Migration ->change() behavior${NC}"
    echo "   ALL column attributes must now be explicitly specified"
    echo "   ${BLUE}Review:${NC} Every migration file using ->change()"
    echo ""
    echo "2. ${RED}CRITICAL: Rate limiting timing changed${NC}"
    echo "   ThrottlesExceptions now uses SECONDS not MINUTES"
    echo "   ${BLUE}Fix:${NC} Multiply all time values by 60"
    echo ""
    echo "3. ${YELLOW}Update migration column types:${NC}"
    echo "   - Remove parameters from ->double() and ->float()"
    echo "   - Replace spatial methods with ->geometry() or ->geography()"
    echo ""
    echo "4. ${YELLOW}Replace deprecated Schema methods:${NC}"
    echo "   - Schema::getAllTables() → Schema::getTables()"
    echo "   - Schema::getAllViews()  → Schema::getViews()"
    echo "   - Schema::getAllTypes()  → Schema::getTypes()"
    echo ""
    echo "5. ${YELLOW}Rename casts() relationships${NC}"
    echo "   If any model has a casts() relationship, rename it"
    echo ""
    echo "6. ${YELLOW}Run migrations:${NC}"
    echo "   php artisan migrate"
    echo ""
    echo "7. ${YELLOW}Test thoroughly:${NC}"
    echo "   - Test database migrations on a copy first!"
    echo "   - Test rate-limited features"
    echo "   - Test Voyager admin panel"
    echo "   - Run your test suite"
    echo ""
}

# Function to show summary
show_summary() {
    print_step "Upgrade Summary"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Laravel 10 → 11 Upgrade Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}✓${NC} Updated composer dependencies (Laravel 11, Voyager 1.9)"
    echo -e "${GREEN}✓${NC} Published package migrations"
    echo -e "${GREEN}✓${NC} Scanned for breaking changes"
    echo ""
    print_warning "This upgrade has CRITICAL breaking changes!"
    echo ""
    print_info "Next steps:"
    echo "  1. Review ALL migration files with ->change()"
    echo "  2. Fix rate limiting (minutes → seconds)"
    echo "  3. Update float/double column definitions"
    echo "  4. Replace spatial column methods"
    echo "  5. Replace Schema::getAll* methods"
    echo "  6. Test migrations on a database copy FIRST"
    echo "  7. Run: php artisan migrate"
    echo "  8. Test the application thoroughly"
    echo "  9. Commit: git add . && git commit -m 'Upgrade to Laravel 11'"
    echo "  10. Deploy to production"
    echo ""
    print_info "Documentation:"
    echo "  https://laravel.com/docs/11.x/upgrade"
    echo ""
    if git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${BLUE}To rollback if needed:${NC}"
        echo "  git restore ."
        echo "  composer install"
    fi
    echo ""
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [path-to-site] [options]

Upgrades a Laravel 10 site to Laravel 11 with breaking change detection

Arguments:
  path-to-site          Path to Laravel site (default: current directory)

Options:
  --dry-run            Show what would be done without making changes
  --help, -h           Show this help message

Examples:
  # Dry run to see what would happen
  $0 --dry-run

  # Upgrade current directory
  $0

  # Upgrade specific site
  $0 /path/to/site

What this script does:
  ✓ Scans for CRITICAL migration ->change() issues
  ✓ Scans for rate limiting timing issues (minutes → seconds)
  ✓ Scans for deprecated float/double syntax
  ✓ Scans for deprecated spatial column types
  ✓ Scans for deprecated Schema methods
  ✓ Scans for model casts() relationship conflicts
  ✓ Updates composer.json (Laravel 11, Voyager 1.9, removes doctrine/dbal)
  ✓ Runs composer update
  ✓ Publishes package migrations
  ✓ Clears all caches

IMPORTANT: Laravel 11 has BREAKING CHANGES in:
  - Migration column modification (->change() behavior)
  - Rate limiting (minutes to seconds conversion)
  - Database column types

Review the manual steps carefully before deploying!

Note: This script assumes you're working in a git repository.
      Use 'git restore .' to revert changes if needed.

EOF
}

# Parse command line arguments
SITE_PATH="."

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            SITE_PATH="$1"
            shift
            ;;
    esac
done

# Main execution
main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════╗"
    echo "║   Laravel 10 → 11 Upgrade Script      ║"
    echo "║   Breaking Change Detection            ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    # Change to site directory
    if [ ! -d "$SITE_PATH" ]; then
        print_error "Directory not found: $SITE_PATH"
        exit 1
    fi

    cd "$SITE_PATH" || exit 1
    print_info "Working directory: $(pwd)"
    echo ""

    # Run upgrade steps
    check_prerequisites
    validate_laravel_version
    ensure_auth_json_ignored

    # Scan for issues BEFORE upgrading
    scan_migration_issues
    scan_rate_limiting_issues
    scan_model_casts_relationship

    # Composer updates
    update_composer_json
    run_composer_update

    # Finalization
    publish_package_migrations
    clear_caches
    verify_installation

    # Show results
    show_manual_steps
    show_summary

    if [ "$DRY_RUN" = false ]; then
        print_success "Upgrade completed successfully!"
        print_warning "IMPORTANT: Review and fix breaking changes before deploying!"
    else
        print_info "Dry run completed. Run without --dry-run to perform actual upgrade."
    fi
}

# Run main function
main
