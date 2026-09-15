package t4d.sync;

import com.mchange.v2.c3p0.AbstractConnectionCustomizer;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;

/**
 * Clinic half of the replication-origin loop guard (PG16+). Every pooled JDBC-sink
 * connection claims a replication origin for its session, so the transactions the
 * sink commits carry that origin and a source decoding with pgoutput `origin=none`
 * skips them: a replicated row is never re-published by the node that applied it.
 *
 * PostgreSQL lets ONE session hold a given origin at a time, so each connection takes
 * the first free one of <SYNC_ORIGIN_NAME>_1 .. _<SYNC_ORIGIN_MAX> (default hub_1..hub_16),
 * creating it if it does not exist yet. Needs, for the sink role, EXECUTE on
 * pg_replication_origin_session_setup(text) and pg_replication_origin_create(text).
 */
public class SyncOriginCustomizer extends AbstractConnectionCustomizer {
    @Override
    public void onAcquire(Connection c, String parentDataSourceIdentityToken) throws Exception {
        String base = System.getenv("SYNC_ORIGIN_NAME");
        if (base == null || base.isEmpty()) base = "hub";
        if (!base.matches("[A-Za-z0-9_]+")) throw new IllegalArgumentException("bad origin name: " + base);
        int max = 16;
        try { String m = System.getenv("SYNC_ORIGIN_MAX"); if (m != null && !m.isEmpty()) max = Integer.parseInt(m); } catch (NumberFormatException ignored) {}
        SQLException last = null;
        for (int n = 1; n <= max; n++) {
            String name = base + "_" + n;
            try (Statement s = c.createStatement()) {
                try {
                    s.execute("SELECT pg_replication_origin_session_setup('" + name + "')");
                    return;
                } catch (SQLException e) {
                    last = e;
                    String msg = e.getMessage() == null ? "" : e.getMessage();
                    if (msg.contains("does not exist")) {
                        s.execute("SELECT pg_replication_origin_create('" + name + "')");
                        s.execute("SELECT pg_replication_origin_session_setup('" + name + "')");
                        return;
                    }
                    if (!msg.contains("already active")) throw e;
                }
            }
        }
        throw new SQLException("no free replication origin " + base + "_1.." + max, last);
    }
}
