# Changelog

## 1.0.0 — 2026-10-10

First release. Speedtest Tracker in Container Manager. Its default
admin@example.com / password login is replaced by your account at the first
start, with the password shown once.

The DSM window adds:
- **Speed:** the latest results, averages over 24 hours, 7 days and 30 days,
  and a test on demand.
- **History:** a monthly CSV of every result in the shared folder.
- **Schedule:** how often (at this install's own minute), which server, how
  long results are kept, and the public dashboard.
- **Alerts:** thresholds, with DSM notifications for results below them and
  for failed tests.
- **Account:** a new password, and API tokens (read-only, or able to start
  tests), each shown once.
- **Site address:** HTTPS with DSM's certificate.

Also included: consistent backups, updates and removal.
