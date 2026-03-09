# Migration Scripts for Moln8/Eastwest Sites

This directory contains upgrade scripts for Laravel sites using moln8-components and eastwest packages.

## Quick Start

When asked to upgrade a site to Laravel 11:

1. **Run the moln8 upgrade script first:**
   ```bash
   ./moln8-v2-to-v3-upgrade.sh /path/to/site
   ```

2. **Then run the Laravel upgrade script:**
   ```bash
   ./laravel-10-to-11-upgrade.sh /path/to/site
   ```

3. **Run composer update:**
   ```bash
   cd /path/to/site && composer clear-cache && composer update
   ```

## Available Scripts

| Script | Purpose |
|--------|---------|
| `moln8-v2-to-v3-upgrade.sh` | Updates moln8-components/eastwest packages for Laravel 11 |
| `laravel-8-to-9-upgrade.sh` | Laravel 8 → 9 upgrade |
| `laravel-9-to-10-upgrade.sh` | Laravel 9 → 10 upgrade |
| `laravel-10-to-11-upgrade.sh` | Laravel 10 → 11 upgrade |

## Package Repositories

Packages are hosted on Bitbucket under `ewpublisher` and served via satis at `satis.eastwest.se`.

To clone packages for editing:
```bash
mkdir -p /Users/janne/Sites/kunder/packages
cd /Users/janne/Sites/kunder/packages
git clone git@bitbucket.org:ewpublisher/blog.git
git clone git@bitbucket.org:ewpublisher/events.git
git clone git@bitbucket.org:ewpublisher/treats.git
git clone git@bitbucket.org:ewpublisher/staff.git
git clone git@bitbucket.org:ewpublisher/moln8-publisher.git
```

## Satis

Satis config: `/home/forge/satis-config/satis.json`
Satis output: `/home/forge/satis.eastwest.se/public`

Rebuild satis:
```bash
php /home/forge/satis.eastwest.se/satis-123.on-forge.com/bin/satis build /home/forge/satis-config/satis.json /home/forge/satis.eastwest.se/public
```

## Common Issues

### Carbon 3 formatLocalized removed

Laravel 11 uses Carbon 3 which removed `formatLocalized()`. Replace with `translatedFormat()`:

```php
// Before
$date->formatLocalized('%e %b %Y')

// After
$date->translatedFormat('j M Y')
```

Format conversion: `%e`→`j`, `%b`→`M`, `%B`→`F`, `%Y`→`Y`, `%H:%M`→`H:i`

### Packages needing updates for Laravel 11

These packages have `formatLocalized` and need patch releases:
- moln8-components/blog (v2.4.12+)
- moln8-components/events (v4.0.10+)
- moln8-components/treats (v2.1.8+)
- moln8-components/staff (v2.1.14+)
- eastwest/publisher (v4.0.2+)

### stevebauman/purify constraint

Packages using `stevebauman/purify ~5.0` need updating to `^6.2` for Laravel 11.

Affected: `moln8-components/base`, `eastwest/publisher`, `moln8-components/html`

## Laravel 11 Compatible Versions

**Packages that MUST be updated to v3/v4:**

| Package | Version | Reason |
|---------|---------|--------|
| eastwest/publisher | ^4.0 | Carbon 3, purify |
| moln8-components/base | ^3.0 | purify ^6.2 |
| moln8-components/moln8-updater | ^4.0 | Laravel 11 |
| moln8-components/html | ^3.0 | purify ^6.2 |
| moln8-components/snippet | ^3.0 | purify ^6.2 |
| moln8-components/include-code | ^3.0 | purify ^6.2 |
| moln8-components/events | ^4.0 | Carbon 3 |
| moln8-components/navbar | ^3.0 | base ^3.0 |
| spatie/laravel-backup | ^8.0 | Laravel 11 |
| spatie/laravel-ignition | ^2.0 | Laravel 11 |

**Packages that stay at ^2.0 (work fine with base ^3.0):**
- moln8-components/blog, cards, gallery, image, slider, etc.
- moln8-templates/* (all templates)
- Most other moln8-components/*

The moln8-v2-to-v3-upgrade.sh script only updates the specific packages that need it.

## Config Updates

After upgrading, check `config/events.php` for `model_date_string` - needs PHP date format:
```php
// Before (strftime)
'model_date_string' => '%A %e %b'

// After (PHP date)
'model_date_string' => 'l j M'
```

## Reference Sites

- **Laravel 11 reference:** `/Users/janne/Sites/kunder/umeajazzfestival.se`
- **Another site to upgrade:** `/Users/janne/Sites/kunder/prfkonferens2026.se`

## Updating Packages (for fixing issues)

If a package needs code changes (e.g., formatLocalized fix):

1. Clone the repo:
   ```bash
   cd /Users/janne/Sites/kunder/packages
   git clone git@bitbucket.org:ewpublisher/PACKAGE.git
   ```

2. Make changes, commit, push:
   ```bash
   git add -A
   git commit -m "Description of fix"
   git push
   ```

3. Tag a new patch release:
   ```bash
   git tag --sort=-version:refname | head -3  # See current tags
   git tag v2.4.12  # Create new tag
   git push origin v2.4.12
   ```

4. Rebuild satis to pick up new tag

## Moln8 Updater Scripts

The `moln8-updater` package has internal scripts at:
```
vendor/moln8-components/moln8-updater/scripts/
```

**As of v4.0.2:** The scripts only run file operations (TrustProxies.php, routes/web.php, voyager cleanup).
They NO LONGER modify composer.json - use the bash scripts in this directory instead.

This avoids the catch-22 where composer update needs to work before the scripts can run.

## Debugging Composer Conflicts

When composer fails, find the specific blocker:
```bash
composer update --dry-run 2>&1 | grep -E "Problem|requires" | head -20
```

Check available versions of a package:
```bash
composer show package/name --available
```

## Deprecated Packages to Remove

| Package | Replacement | Notes |
|---------|-------------|-------|
| `facade/ignition` | `spatie/laravel-ignition` | Already in require |
| `spatie/laravel-cookie-consent` | - | Usually unused |
| `fideloper/proxy` | Built into Laravel 9+ | Remove entirely |

## Config Files with HTML in Format Strings

If `config/events.php` has HTML spans in `model_date_string`:
```php
// This WON'T work with Carbon 3:
'model_date_string' => '<span class="day">%A %e</span> <span class="month">%b</span>'

// Change to simple format:
'model_date_string' => 'l j M'
```

If HTML styling is needed, update the blade views to add spans around the date output.

## Sites May Have Different Package Sets

Not all sites use all packages. Check what's installed:
```bash
jq '.require | keys[]' composer.json | grep -E "moln8|eastwest"
```

## Fix npm/webpack for Node.js 17+

Older laravel-mix (v4/v5) fails with OpenSSL errors on Node.js 17+. Fix package.json:

```json
"scripts": {
    "dev": "npm run development",
    "development": "cross-env NODE_OPTIONS=--openssl-legacy-provider NODE_ENV=development node_modules/webpack/bin/webpack.js --progress --hide-modules --config=node_modules/laravel-mix/setup/webpack.config.js",
    "watch": "cross-env NODE_OPTIONS=--openssl-legacy-provider NODE_ENV=development node_modules/webpack/bin/webpack.js --watch --progress --hide-modules --config=node_modules/laravel-mix/setup/webpack.config.js",
    "watch-poll": "npm run watch -- --watch-poll",
    "hot": "cross-env NODE_OPTIONS=--openssl-legacy-provider NODE_ENV=development node_modules/webpack-dev-server/bin/webpack-dev-server.js --inline --hot --config=node_modules/laravel-mix/setup/webpack.config.js",
    "prod": "npm run production",
    "production": "cross-env NODE_OPTIONS=--openssl-legacy-provider NODE_ENV=production node_modules/webpack/bin/webpack.js --no-progress --hide-modules --config=node_modules/laravel-mix/setup/webpack.config.js",
    "build": "npm run production"
}
```

Key changes:
- Add `NODE_OPTIONS=--openssl-legacy-provider` to all webpack scripts
- Add `"build": "npm run production"` for Forge compatibility

## After Successful Upgrade

1. Clear all caches:
   ```bash
   php artisan config:clear && php artisan cache:clear && php artisan view:clear && php artisan route:clear
   ```

2. Verify Laravel version:
   ```bash
   php artisan --version
   ```

3. Test the site in browser

4. Check for runtime errors in `storage/logs/laravel.log`

## Git Workflow

After upgrade:
```bash
git status
git add .
git commit -m "Upgrade to Laravel 11"
```

Keep backup files out of git - they should already be in .gitignore:
- `auth.json`
- `composer.json.backup.*`

## Full Checklist

See `LARAVEL-11-UPGRADE-CHECKLIST.md` for complete step-by-step guide.
