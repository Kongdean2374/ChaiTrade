#include <sqlite3.h>

static inline int chai_sqlite_archive_defensive(sqlite3 *db) {
    int defensive = 0;
    int rc = sqlite3_db_config(db, SQLITE_DBCONFIG_DEFENSIVE, 1, &defensive);
    if (rc != SQLITE_OK) return rc;
    if (defensive != 1) return SQLITE_ERROR;
    /*
     * Apple's SQLite is built with OMIT_LOAD_EXTENSION: the loader does not
     * exist and its db_config selector returns SQLITE_MISUSE (21). Verify the
     * compile option instead of treating every unsupported selector as safe.
     */
    if (sqlite3_compileoption_used("OMIT_LOAD_EXTENSION")) return SQLITE_OK;
    int extensions = -1;
    rc = sqlite3_db_config(db, SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION, 0, &extensions);
    if (rc != SQLITE_OK) return rc;
    return extensions == 0 ? SQLITE_OK : SQLITE_ERROR;
}
