# Migration Scripts for Moln8 Sites

Collection of migration scripts for upgrading Laravel and related packages across all sites.

## Available Scripts

### `laravel-8-to-9-upgrade.sh`

Upgrades Laravel 8 sites to Laravel 9, including:
- Laravel Framework 8.x → 9.x
- Voyager 1.6 → 1.7
- PHP 8.0+ required
- All breaking changes and config updates
- Database seeder migration

**Key Changes:**
- Kernel middleware updates
- TrustProxies to Laravel built-in
- Mail/filesystem config updates
- RouteServiceProvider namespace removal

**Usage:**
```bash
# Dry run first (recommended)
/Users/janne/Sites/kunder/migration-scripts/laravel-8-to-9-upgrade.sh --dry-run

# Run the upgrade
/Users/janne/Sites/kunder/migration-scripts/laravel-8-to-9-upgrade.sh
```

---

### `laravel-9-to-10-upgrade.sh`

Upgrades Laravel 9 sites to Laravel 10, including:
- Laravel Framework 9.x → 10.x
- Voyager stays at 1.7
- PHP 8.1+ required
- Password reset table rename
- Type hint additions

**Key Changes:**
- `$dates` → `$casts` in models (BREAKING)
- `dispatchNow` → `dispatchSync`
- `$routeMiddleware` → `$middlewareAliases`
- Remove `DispatchesJobs` trait
- Password reset table rename

**Usage:**
```bash
# Dry run first (recommended)
/Users/janne/Sites/kunder/migration-scripts/laravel-9-to-10-upgrade.sh --dry-run

# Run the upgrade
/Users/janne/Sites/kunder/migration-scripts/laravel-9-to-10-upgrade.sh
```

---

### `laravel-10-to-11-upgrade.sh`

Upgrades Laravel 10 sites to Laravel 11, including:
- Laravel Framework 10.x → 11.x
- Voyager stays at 1.7
- PHP 8.2+ required
- Database migration breaking changes
- Rate limiting timing changes

**CRITICAL BREAKING CHANGES:**
- Migration `->change()` behavior (must specify ALL column attributes)
- Rate limiting: minutes → seconds
- Float/double column syntax changes
- Spatial column consolidation

**Usage:**
```bash
# Dry run first (HIGHLY recommended - scans for breaking changes)
/Users/janne/Sites/kunder/migration-scripts/laravel-10-to-11-upgrade.sh --dry-run

# Run the upgrade
/Users/janne/Sites/kunder/migration-scripts/laravel-10-to-11-upgrade.sh
```

**⚠️ WARNING:** Laravel 11 has critical breaking changes in database migrations. Always test on a database copy first!

## Workflow

1. **Test locally** on one site first
2. **Review changes** with `git diff`
3. **Test the application** thoroughly
4. **Commit** when satisfied
5. **Repeat** for other sites

## Version Control

This directory should be its own git repository so you can:
- Track changes to migration scripts
- Revert to previous versions if needed
- Share scripts across your team
- Document what migrations were run when

```bash
cd /Users/janne/Sites/kunder/migration-scripts
git init
git add .
git commit -m "Initial commit: Laravel 8 to 9 migration script"
```

## Adding New Scripts

When creating new migration scripts, follow this pattern:
- Name: `{from}-to-{to}-{what}.sh` (e.g., `laravel-9-to-11-upgrade.sh`)
- Include `--dry-run` mode
- Include `--help` documentation
- Check for git repository and uncommitted changes
- Provide rollback instructions
