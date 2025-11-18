# Migration Scripts for Moln8 Sites

Collection of migration scripts for upgrading Laravel and related packages across all sites.

## Available Scripts

### `laravel-8-to-9-upgrade.sh`

Upgrades Laravel 8 sites to Laravel 9, including:
- Laravel Framework 8.x → 9.x
- Voyager 1.6 → 1.7
- All breaking changes and config updates
- Database seeder migration

**Usage:**
```bash
# From any site directory
/Users/janne/Sites/kunder/migration-scripts/laravel-8-to-9-upgrade.sh

# Or from another location
/Users/janne/Sites/kunder/migration-scripts/laravel-8-to-9-upgrade.sh /path/to/site

# Dry run first (recommended)
/Users/janne/Sites/kunder/migration-scripts/laravel-8-to-9-upgrade.sh --dry-run
```

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
