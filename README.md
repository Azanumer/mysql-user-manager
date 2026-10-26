# MySQL User Manager

A single Bash script for the MySQL/MariaDB user chores every VPS admin repeats: list users, create least-privilege app users, reset passwords, and drop users safely.

## Why not just run the SQL by hand?

- **Injection-safe identifiers:** usernames and hosts are validated against `[A-Za-z0-9_.-]` before they ever reach SQL.
- **Allow-listed privileges:** only real MySQL privileges are accepted — a typo like `SELCT` fails loudly instead of silently granting nothing.
- **No password on the command line unless you choose to:** omit `--password` and a 24-character random password is generated with `openssl`.
- **Drop is two-step:** it prints the user's current grants first and refuses to run without `--yes`, so you never drop a user blind.

## Usage

```bash
# Credentials come from ~/.my.cnf (a [client] section with user/password).
./manage-mysql-users.sh list
./manage-mysql-users.sh list --host localhost

# Least-privilege app user for one database (password auto-generated):
./manage-mysql-users.sh create shop_app --privileges 'shop.*:SELECT,INSERT,UPDATE,DELETE' --yes

# Full privileges (use sparingly):
./manage-mysql-users.sh create admin2 --privileges ALL --host localhost --yes

# Reset a password (auto-generated unless --password is given):
./manage-mysql-users.sh reset-password shop_app

# Drop (shows grants first, requires --yes):
./manage-mysql-users.sh drop old_app --yes
```

`create` is idempotent for the same name: it replaces the password and re-applies the grants, so re-running it after a privilege change is safe.

## Requirements

- `mysql` client, `openssl` (password generation only)
- A `~/.my.cnf` `[client]` section with a privileged user, e.g. root

## License

MIT
