mysqldump \
  -h <REMOTE_HOST> -P <REMOTE_PORT> --protocol tcp \
  -u <REMOTE_USER> -p \
  --set-gtid-purged=OFF \
  --single-transaction \
  --routines --triggers \
  --add-drop-database \
  --databases openmrs \
  > openmrs-$(date +%Y%m%d-%H%M)-seed_local.sql
