#!/bin/bash

# Laravel 8 to 9 Upgrade Script
# Usage: ./laravel-8-to-9-upgrade.sh [path-to-site] [options]
#
# This script upgrades a Laravel 8 site to Laravel 9
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

    # Check PHP version (need 8.0+)
    PHP_VERSION=$(php -r 'echo PHP_VERSION;')
    PHP_MAJOR=$(php -r 'echo PHP_MAJOR_VERSION;')

    if [ "$PHP_MAJOR" -lt 8 ]; then
        print_error "PHP 8.0 or higher is required. Current version: $PHP_VERSION"
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

    # Check if it's Laravel 8
    if [[ ! "$CURRENT_LARAVEL" =~ ^[\^~]?8\. ]] && [[ ! "$CURRENT_LARAVEL" =~ ^8\. ]]; then
        print_warning "This site doesn't appear to be Laravel 8"
        print_warning "Current version: $CURRENT_LARAVEL"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "Confirmed Laravel 8.x"
    fi
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
        echo "  - CheckForMaintenanceMode → PreventRequestsDuringMaintenance"
        return
    fi

    # Replace CheckForMaintenanceMode with PreventRequestsDuringMaintenance
    if grep -q "CheckForMaintenanceMode" app/Http/Kernel.php; then
        sed -i.bak 's/\\Illuminate\\Foundation\\Http\\Middleware\\CheckForMaintenanceMode/\\Illuminate\\Foundation\\Http\\Middleware\\PreventRequestsDuringMaintenance/g' app/Http/Kernel.php
        rm -f app/Http/Kernel.php.bak
        print_success "Updated maintenance mode middleware"
    else
        print_info "Kernel already using PreventRequestsDuringMaintenance"
    fi
}

# Function to update TrustProxies middleware
update_trust_proxies() {
    print_step "Updating TrustProxies Middleware"

    if [ ! -f "app/Http/Middleware/TrustProxies.php" ]; then
        print_warning "TrustProxies.php not found, skipping"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would update TrustProxies middleware to use Laravel's built-in version"
        return
    fi

    # Check if using old fideloper/proxy
    if grep -q "Fideloper\\\\Proxy" app/Http/Middleware/TrustProxies.php; then
        cat > app/Http/Middleware/TrustProxies.php << 'EOF'
<?php

namespace App\Http\Middleware;

use Illuminate\Http\Middleware\TrustProxies as Middleware;
use Illuminate\Http\Request;

class TrustProxies extends Middleware
{
    /**
     * The trusted proxies for this application.
     *
     * @var array<int, string>|string|null
     */
    protected $proxies;

    /**
     * The headers that should be used to detect proxies.
     *
     * @var int
     */
    protected $headers =
        Request::HEADER_X_FORWARDED_FOR |
        Request::HEADER_X_FORWARDED_HOST |
        Request::HEADER_X_FORWARDED_PORT |
        Request::HEADER_X_FORWARDED_PROTO |
        Request::HEADER_X_FORWARDED_AWS_ELB;
}
EOF
        print_success "Updated TrustProxies to use Laravel's built-in middleware"
    else
        print_info "TrustProxies already using Laravel's built-in version"
    fi
}

# Function to update mail config
update_mail_config() {
    print_step "Updating Mail Configuration"

    if [ ! -f "config/mail.php" ]; then
        print_warning "config/mail.php not found, skipping"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would update mail.php:"
        echo "  - 'driver' → 'mailer'"
        echo "  - MAIL_DRIVER → MAIL_MAILER"
        return
    fi

    # Update mail.php config
    if grep -q "'driver'" config/mail.php; then
        sed -i.bak "s/'driver' => env('MAIL_DRIVER'/'mailer' => env('MAIL_MAILER'/g" config/mail.php
        rm -f config/mail.php.bak
        print_success "Updated mail.php config"
    else
        print_info "mail.php already using 'mailer'"
    fi

    # Update .env file
    if [ -f ".env" ]; then
        if grep -q "^MAIL_DRIVER=" .env; then
            sed -i.bak 's/^MAIL_DRIVER=/MAIL_MAILER=/g' .env
            rm -f .env.bak
            print_success "Updated .env MAIL_DRIVER → MAIL_MAILER"
        fi
    fi
}

# Function to update filesystem config
update_filesystem_config() {
    print_step "Updating Filesystem Configuration"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would update filesystems.php:"
        echo "  - FILESYSTEM_DRIVER → FILESYSTEM_DISK"
        return
    fi

    # Update filesystems.php
    if [ -f "config/filesystems.php" ]; then
        if grep -q "FILESYSTEM_DRIVER" config/filesystems.php; then
            sed -i.bak "s/FILESYSTEM_DRIVER/FILESYSTEM_DISK/g" config/filesystems.php
            rm -f config/filesystems.php.bak
            print_success "Updated filesystems.php"
        fi
    fi

    # Update voyager.php if it exists
    if [ -f "config/voyager.php" ]; then
        if grep -q "FILESYSTEM_DRIVER" config/voyager.php; then
            sed -i.bak "s/FILESYSTEM_DRIVER/FILESYSTEM_DISK/g" config/voyager.php
            rm -f config/voyager.php.bak
            print_success "Updated voyager.php"
        fi
    fi

    # Update .env file
    if [ -f ".env" ]; then
        if grep -q "^FILESYSTEM_DRIVER=" .env; then
            sed -i.bak 's/^FILESYSTEM_DRIVER=/FILESYSTEM_DISK=/g' .env
            rm -f .env.bak
            print_success "Updated .env FILESYSTEM_DRIVER → FILESYSTEM_DISK"
        fi
    fi
}

# Function to update RouteServiceProvider
update_route_service_provider() {
    print_step "Updating RouteServiceProvider"

    if [ ! -f "app/Providers/RouteServiceProvider.php" ]; then
        print_warning "RouteServiceProvider not found, skipping"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would update RouteServiceProvider:"
        echo "  - Remove namespace property and routing"
        echo "  - Update route definitions"
        return
    fi

    # Check if still using old namespace routing
    if grep -q "protected \$namespace" app/Providers/RouteServiceProvider.php; then
        # Create updated RouteServiceProvider
        cat > app/Providers/RouteServiceProvider.php << 'EOF'
<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Foundation\Support\Providers\RouteServiceProvider as ServiceProvider;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Route;

class RouteServiceProvider extends ServiceProvider
{
    /**
     * The path to the "home" route for your application.
     *
     * @var string
     */
    public const HOME = '/home';

    /**
     * Define your route model bindings, pattern filters, etc.
     *
     * @return void
     */
    public function boot()
    {
        $this->configureRateLimiting();

        $this->routes(function () {
            Route::middleware('api')
                ->prefix('api')
                ->group(base_path('routes/api.php'));

            Route::middleware('web')
                ->group(base_path('routes/web.php'));
        });
    }

    /**
     * Configure the rate limiters for the application.
     *
     * @return void
     */
    protected function configureRateLimiting()
    {
        RateLimiter::for('api', function (Request $request) {
            return Limit::perMinute(60)->by($request->user()?->id ?: $request->ip());
        });
    }
}
EOF
        print_success "Updated RouteServiceProvider"
        print_warning "NOTE: You'll need to update route files to use full controller class names"
        print_info "Example: Route::get('/schema', [App\\Http\\Controllers\\SchemaController::class, 'index']);"
    else
        print_info "RouteServiceProvider already using Laravel 9 structure"
    fi
}

# Function to move database seeders
move_database_seeders() {
    print_step "Moving Database Seeders"

    if [ ! -d "database/seeds" ]; then
        print_info "No database/seeds directory found, skipping"
        return
    fi

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would move seeders:"
        echo "  - database/seeds → database/seeders"
        echo "  - Update namespaces"
        return
    fi

    # Create seeders directory if it doesn't exist
    mkdir -p database/seeders

    # Move and update seeders
    for file in database/seeds/*.php; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")

            # Update namespace in the file
            sed 's/namespace Database\\Seeds;/namespace Database\\Seeders;/g' "$file" > "database/seeders/$filename"
            print_success "Moved and updated $filename"
        fi
    done

    print_info "Original files kept in database/seeds (you can remove them after testing)"
}

# Function to update composer.json
update_composer_json() {
    print_step "Updating composer.json"

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN - Would update composer.json with these changes:"
        echo "  - Laravel Framework: ^8.x → ^9.x"
        echo "  - Voyager: 1.6.* → ^1.7"
        echo "  - Remove: fideloper/proxy"
        echo "  - Update: facade/ignition → ^2.17"
        echo "  - Update: nunomaduro/collision → ^6.1"
        echo "  - Update: phpunit/phpunit → ^9.5.10"
        return
    fi

    TMP_FILE=$(mktemp)

    # Update Laravel and related packages
    jq '
        # Update laravel/framework
        .require["laravel/framework"] = "^9.0" |

        # Update Voyager if present
        if .require["tcg/voyager"] then
            .require["tcg/voyager"] = "^1.7"
        else . end |

        # Remove fideloper/proxy
        del(.require["fideloper/proxy"]) |

        # Update facade/ignition if present
        if .require["facade/ignition"] then
            .require["facade/ignition"] = "^2.17"
        else . end |

        # Update flare/flare-client-php if present
        if .require["flare/flare-client-php"] then
            .require["flare/flare-client-php"] = "^1.0.1"
        else . end |

        # Update dev dependencies
        if .["require-dev"]["nunomaduro/collision"] then
            .["require-dev"]["nunomaduro/collision"] = "^6.1"
        else . end |

        if .["require-dev"]["phpunit/phpunit"] then
            .["require-dev"]["phpunit/phpunit"] = "^9.5.10"
        else . end |

        if .["require-dev"]["mockery/mockery"] then
            .["require-dev"]["mockery/mockery"] = "^1.4.4"
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
        print_warning "DRY RUN - Would publish Laravel 9 and Voyager config files"
        return
    fi

    if [ -f "artisan" ]; then
        # Publish new config files if any
        php artisan vendor:publish --tag=laravel-assets --force 2>/dev/null || print_info "No Laravel assets to publish"

        # Check if Voyager is installed and republish assets
        if grep -q '"tcg/voyager"' composer.json; then
            print_info "Publishing Voyager 1.7 assets..."
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

        if [[ "$INSTALLED_VERSION" =~ Laravel\ Framework\ 9\. ]]; then
            print_success "Laravel 9 successfully installed!"
        else
            print_warning "Could not verify Laravel 9 installation"
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
    echo "1. ${YELLOW}Route files need updating${NC}"
    echo "   Update routes to use full controller class names:"
    echo "   ${BLUE}Before:${NC} Route::get('/schema', 'SchemaController@index');"
    echo "   ${BLUE}After:${NC}  Route::get('/schema', [App\\Http\\Controllers\\SchemaController::class, 'index']);"
    echo ""
    echo "2. ${YELLOW}Review custom middleware${NC}"
    echo "   Check app/Http/Middleware for any custom middleware that might need updates"
    echo ""
    echo "3. ${YELLOW}Test the application${NC}"
    echo "   - Test file storage (Flysystem 3.x)"
    echo "   - Test email sending (Symfony Mailer)"
    echo "   - Test Voyager admin panel"
    echo "   - Run your test suite"
    echo ""
    echo "4. ${YELLOW}Check database seeders${NC}"
    echo "   Update DatabaseSeeder.php if needed (now in database/seeders/)"
    echo ""
}

# Function to show summary
show_summary() {
    print_step "Upgrade Summary"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Laravel 8 → 9 Upgrade Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${GREEN}✓${NC} Updated Kernel.php maintenance middleware"
    echo -e "${GREEN}✓${NC} Updated TrustProxies to built-in Laravel version"
    echo -e "${GREEN}✓${NC} Updated mail configuration (MAIL_MAILER)"
    echo -e "${GREEN}✓${NC} Updated filesystem configuration (FILESYSTEM_DISK)"
    echo -e "${GREEN}✓${NC} Updated RouteServiceProvider"
    echo -e "${GREEN}✓${NC} Moved database seeders"
    echo -e "${GREEN}✓${NC} Updated composer dependencies (Laravel 9, Voyager 1.7)"
    echo -e "${GREEN}✓${NC} Published Voyager 1.7 assets"
    echo ""
    print_info "Next steps:"
    echo "  1. Review changes: git status && git diff"
    echo "  2. Update route files (see manual steps above)"
    echo "  3. Test the application locally"
    echo "  4. Commit: git add . && git commit -m 'Upgrade to Laravel 9'"
    echo "  5. Deploy to production"
    echo ""
    print_info "Documentation:"
    echo "  https://laravel.com/docs/9.x/upgrade"
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

Upgrades a Laravel 8 site to Laravel 9 with full code migration

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
  ✓ Updates Kernel.php (CheckForMaintenanceMode → PreventRequestsDuringMaintenance)
  ✓ Updates TrustProxies middleware (removes fideloper/proxy dependency)
  ✓ Updates mail.php config (driver → mailer, MAIL_DRIVER → MAIL_MAILER)
  ✓ Updates filesystems.php config (FILESYSTEM_DRIVER → FILESYSTEM_DISK)
  ✓ Updates RouteServiceProvider (removes namespace routing)
  ✓ Moves database/seeds → database/seeders
  ✓ Updates composer.json (Laravel 9, Voyager 1.7, removes deprecated packages)
  ✓ Runs composer update
  ✓ Publishes new configs and Voyager assets
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
    echo "║   Laravel 8 → 9 Upgrade Script        ║"
    echo "║   Full Code Migration                  ║"
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

    # Code updates
    update_kernel
    update_trust_proxies
    update_mail_config
    update_filesystem_config
    update_route_service_provider
    move_database_seeders

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
