#include <sqlite3.h>

static inline int chai_sqlite_archive_defensive(sqlite3 *db) {
    int rc = sqlite3_db_config(db, SQLITE_DBCONFIG_DEFENSIVE, 1, (int *)0);
    if (rc != SQLITE_OK) return rc;
    return sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, 0, (int *)0);
}
