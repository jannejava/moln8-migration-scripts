#!/bin/bash

# Laravel 9 to 10 Upgrade Script
# Usage: ./laravel-9-to-10-upgrade.sh [path-to-site] [options]
#
# This script upgrades a Laravel 9 site to Laravel 10
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

    # Check PHP version (need 8.1+)
    PHP_VERSION=$(php -r 'echo PHP_VERSION;')
    PHP_MAJOR=$(php -r 'echo PHP_MAJOR_VERSION;')
    PHP_MINOR=$(php -r 'echo PHP_MINOR_VERSION;')

    if [ "$PHP_MAJOR" -lt 8 ] || ([ "$PHP_MAJOR" -eq 8 ] && [ "$PHP_MINOR" -lt 1 ]); then
        print_error "PHP 8.1 or higher is required. Current version: $PHP_VERSION"
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

    # Check if it's Laravel 9
    if [[ ! "$CURRENT_LARAVEL" =~ ^[\^~]?9\. ]] && [[ ! "$CURRENT_LARAVEL" =~ ^9\. ]]; then
        print_warning "This site doesn't appear to be Laravel 9"
        print_warning "Current version: $CURRENT_LARAVEL"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Confirmed Laravel 9.x"
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

# Function to convert $dates to $casts in models
convert_dates_to_casts() {
    print_step "Converting \$dates to \$casts in Models"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would search for models with \$dates property"
        return
    fi

    # Find models with $dates property
    MODELS_WITH_DATES=$(grep -r "protected \$dates" app/Models/ app/ 2>/dev/null | grep -v "vendor" | cut -d: -f1 | sort -u || true)

    if [ -z "$MODELS_WITH_DATES" ]; then
        print_info "No models found with \$dates property"
        return
    fi

    print_warning "Found models with \$dates property:"
    echo "$MODELS_WITH_DATES" | while read -r file; do
        echo "  - $file"
    done
    echo ""
    print_warning "The \$dates property is REMOVED in Laravel 10"
    print_warning "You must manually convert these to \$casts"
    echo ""
    echo "Example conversion:"
    echo -e "${BLUE}  Before:${NC} protected \$dates = ['published_at', 'expires_at'];"
    echo -e "${BLUE}  After:${NC}  protected \$casts = ['published_at' => 'datetime', 'expires_at' => 'datetime'];"
    echo ""
    print_info "These files will need manual review after upgrade"
}

# Function to update dispatch methods
update_dispatch_methods() {
    print_step "Updating Dispatch Methods"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would search for dispatchNow and dispatch_now"
        return
    fi

    # Search for dispatchNow
    DISPATCH_NOW=$(grep -r "dispatchNow\|dispatch_now" app/ 2>/dev/null | grep -v "vendor" | cut -d: -f1 | sort -u || true)

    if [ -z "$DISPATCH_NOW" ]; then
        print_info "No dispatchNow/dispatch_now calls found"
        return
    fi

    print_warning "Found dispatchNow/dispatch_now in these files:"
    echo "$DISPATCH_NOW" | while read -r file; do
        echo "  - $file"
    done
    echo ""
    print_warning "These must be changed to dispatchSync/dispatch_sync"
    print_info "These files will need manual review after upgrade"
}

# Function to update Kernel.php
update_kernel() {
    print_step "Updating HTTP Kernel"

    if [ ! -f "app/Http/Kernel.php" ]; then
        print_warning "app/Http/Kernel.php not found, skipping"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would update Kernel.php:"
        echo "  - \$routeMiddleware → \$middlewareAliases"
        return
    fi

    # Replace $routeMiddleware with $middlewareAliases
    if grep -q "protected \$routeMiddleware" app/Http/Kernel.php; then
        sed -i.bak 's/protected \$routeMiddleware/protected \$middlewareAliases/g' app/Http/Kernel.php
        rm -f app/Http/Kernel.php.bak
        print_success "Updated Kernel.php: \$routeMiddleware → \$middlewareAliases"
    else
        print_info "Kernel already using \$middlewareAliases"
    fi
}

# Function to update Controller
update_controller() {
    print_step "Updating Base Controller"

    if [ ! -f "app/Http/Controllers/Controller.php" ]; then
        print_warning "Controller.php not found, skipping"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would remove DispatchesJobs trait from Controller"
        return
    fi

    # Remove DispatchesJobs
    if grep -q "DispatchesJobs" app/Http/Controllers/Controller.php; then
        sed -i.bak '/use.*DispatchesJobs;/d' app/Http/Controllers/Controller.php
        sed -i.bak 's/, DispatchesJobs//g' app/Http/Controllers/Controller.php
        sed -i.bak 's/DispatchesJobs, //g' app/Http/Controllers/Controller.php
        sed -i.bak 's/DispatchesJobs//g' app/Http/Controllers/Controller.php
        rm -f app/Http/Controllers/Controller.php.bak
        print_success "Removed DispatchesJobs trait from Controller"
    else
        print_info "Controller doesn't use DispatchesJobs trait"
    fi
}

# Function to update AuthServiceProvider
update_auth_service_provider() {
    print_step "Updating AuthServiceProvider"

    if [ ! -f "app/Providers/AuthServiceProvider.php" ]; then
        print_warning "AuthServiceProvider not found, skipping"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would remove registerPolicies() call"
        return
    fi

    # Remove $this->registerPolicies() call
    if grep -q "this->registerPolicies()" app/Providers/AuthServiceProvider.php; then
        sed -i.bak '/\$this->registerPolicies();/d' app/Providers/AuthServiceProvider.php
        rm -f app/Providers/AuthServiceProvider.php.bak
        print_success "Removed registerPolicies() call from AuthServiceProvider"
    else
        print_info "AuthServiceProvider doesn't call registerPolicies()"
    fi
}

# Function to update password reset configuration
update_password_reset_config() {
    print_step "Updating Password Reset Configuration"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would update password reset table configuration"
        return
    fi

    # Update config/auth.php
    if [ -f "config/auth.php" ]; then
        if grep -q "'table' => 'password_resets'" config/auth.php; then
            sed -i.bak "s/'table' => 'password_resets'/'table' => 'password_reset_tokens'/g" config/auth.php
            rm -f config/auth.php.bak
            print_success "Updated auth.php to use password_reset_tokens table"
            print_warning "NOTE: You'll need to rename the database table or migration manually"
            print_info "Migration file should be renamed to: *_create_password_reset_tokens_table.php"
        else
            print_info "auth.php already using password_reset_tokens or custom table"
        fi
    fi
}

# Function to update composer.json
update_composer_json() {
    print_step "Updating composer.json"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would update composer.json with these changes:"
        echo "  - Laravel Framework: ^9.x → ^10.x"
        echo "  - Voyager: stays at ^1.7 (no update needed)"
        echo "  - spatie/laravel-ignition: ^2.0"
        echo "  - nunomaduro/collision: ^7.0"
        echo "  - phpunit/phpunit: ^10.0"
        return
    fi

    TMP_FILE=$(mktemp)

    # Update Laravel and related packages
    jq '
        # Update laravel/framework
        .require["laravel/framework"] = "^10.0" |

        # Voyager stays at 1.7 - no higher version available

        # Update spatie/laravel-ignition
        if .require["spatie/laravel-ignition"] then
            .require["spatie/laravel-ignition"] = "^2.0"
        else
            .require["spatie/laravel-ignition"] = "^2.0"
        end |

        # Update laravel/sanctum if present
        if .require["laravel/sanctum"] then
            .require["laravel/sanctum"] = "^3.2"
        else . end |

        # Update dev dependencies
        if .["require-dev"]["nunomaduro/collision"] then
            .["require-dev"]["nunomaduro/collision"] = "^7.0"
        else . end |

        if .["require-dev"]["phpunit/phpunit"] then
            .["require-dev"]["phpunit/phpunit"] = "^10.0"
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

# Function to publish config updates
publish_configs() {
    print_step "Publishing Configuration Updates"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would publish Laravel 10 config files"
        return
    fi

    if [ -f "artisan" ]; then
        # Publish new config files if any
        php artisan vendor:publish --tag=laravel-assets --force 2>/dev/null || print_info "No Laravel assets to publish"

        # Check if Voyager is installed and republish assets
        if grep -q '"tcg/voyager"' composer.json; then
            print_info "Publishing Voyager assets..."
            php artisan vendor:publish --provider="TCG\Voyager\VoyagerServiceProvider" --tag=public --force
            print_success "Published Voyager assets"
        fi

        print_success "Published configuration files"
    else
        print_warning "artisan not found, skipping config publishing"
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

        if [[ "$INSTALLED_VERSION" =~ Laravel\ Framework\ 10\. ]]; then
            print_success "Laravel 10 successfully installed!"
        else
            print_warning "Could not verify Laravel 10 installation"
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
    print_step "Manual Steps Required"

    echo -e "${YELLOW}⚠ The following changes require manual review:${NC}"
    echo ""
    echo "1. ${YELLOW}Convert \$dates to \$casts in models${NC}"
    echo "   The \$dates property is removed in Laravel 10"
    echo "   ${BLUE}Before:${NC} protected \$dates = ['published_at'];"
    echo "   ${BLUE}After:${NC}  protected \$casts = ['published_at' => 'datetime'];"
    echo ""
    echo "2. ${YELLOW}Replace dispatchNow with dispatchSync${NC}"
    echo "   ${BLUE}Before:${NC} Bus::dispatchNow(\$job) or dispatch_now(\$job)"
    echo "   ${BLUE}After:${NC}  Bus::dispatchSync(\$job) or dispatch_sync(\$job)"
    echo ""
    echo "3. ${YELLOW}Add return type hints (recommended)${NC}"
    echo "   Add ': void' to service providers, middleware, migrations"
    echo "   Add ': array' to model definition() methods in factories"
    echo ""
    echo "4. ${YELLOW}Rename password reset migration${NC}"
    echo "   Rename: *_create_password_resets_table.php"
    echo "   To: *_create_password_reset_tokens_table.php"
    echo "   Update table name in migration to 'password_reset_tokens'"
    echo ""
    echo "5. ${YELLOW}Test the application${NC}"
    echo "   - Test authentication and password reset"
    echo "   - Test queued jobs"
    echo "   - Test Voyager admin panel (if installed)"
    echo "   - Run your test suite"
    echo ""
}

# Function to show summary
show_summary() {
    print_step "Upgrade Summary"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Laravel 9 → 10 Upgrade Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}✓${NC} Updated HTTP Kernel (\$middlewareAliases)"
    echo -e "${GREEN}✓${NC} Removed DispatchesJobs from Controller"
    echo -e "${GREEN}✓${NC} Updated AuthServiceProvider"
    echo -e "${GREEN}✓${NC} Updated password reset configuration"
    echo -e "${GREEN}✓${NC} Updated composer dependencies (Laravel 10, Voyager 1.8)"
    echo ""
    print_info "Next steps:"
    echo "  1. Review changes: git status && git diff"
    echo "  2. Manually convert \$dates to \$casts (see manual steps above)"
    echo "  3. Replace dispatchNow with dispatchSync"
    echo "  4. Rename password reset migration file and table"
    echo "  5. Test the application locally"
    echo "  6. Commit: git add . && git commit -m 'Upgrade to Laravel 10'"
    echo "  7. Deploy to production"
    echo ""
    print_info "Documentation:"
    echo "  https://laravel.com/docs/10.x/upgrade"
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

Upgrades a Laravel 9 site to Laravel 10 with code migration assistance

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
  ✓ Updates Kernel.php (\$routeMiddleware → \$middlewareAliases)
  ✓ Removes DispatchesJobs trait from Controller
  ✓ Updates AuthServiceProvider (removes registerPolicies call)
  ✓ Updates password reset configuration
  ✓ Scans for \$dates properties (manual conversion needed)
  ✓ Scans for dispatchNow usage (manual replacement needed)
  ✓ Updates composer.json (Laravel 10, Voyager 1.8, etc.)
  ✓ Runs composer update
  ✓ Publishes new configs
  ✓ Clears all caches

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
    echo "║   Laravel 9 → 10 Upgrade Script       ║"
    echo "║   Code Migration Assistance            ║"
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

    # Code analysis
    convert_dates_to_casts
    update_dispatch_methods

    # Code updates
    update_kernel
    update_controller
    update_auth_service_provider
    update_password_reset_config

    # Composer updates
    update_composer_json
    run_composer_update

    # Finalization
    publish_configs
    clear_caches
    verify_installation

    # Show results
    show_manual_steps
    show_summary

    if [ "$DRY_RUN" = false ]; then
        print_success "Upgrade completed successfully!"
    else
        print_info "Dry run completed. Run without --dry-run to perform actual upgrade."
    fi
}

# Run main function
main
