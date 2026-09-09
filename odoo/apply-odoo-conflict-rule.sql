-- SUPERSEDED 2026-09-09 on clinic nodes by retire-write-origin-guard.sql: row filters and the
-- origin stamp are retired; the last-writer rule lives on in sync_lww() without an origin
-- tie-break (sync-core F-048). Columns and sequences this file creates stay.
-- ADDED 2026-09-04 (sync-core D3). Gives Odoo a conflict rule, which the system has
-- never had.
--
-- THE DEFECT THIS FIXES, measured on the live lab 2026-09-04. Two clinics editing the
-- same row concurrently do not converge -- they SWAP. Rawach wrote RAWACH-SAYS-A and
-- ended holding GHATED-SAYS-B; Ghated wrote GHATED-SAYS-B and ended holding
-- RAWACH-SAYS-A. Stable, permanent, every connector RUNNING, nothing reported. It is
-- not last-writer-wins failing; there is no winner at all.
--
-- WHY IT HAPPENS, and why the fix is where it is. The sink's echo filter drops any row
-- stamped with this node's own name. That is what prevents convergence: a node never
-- sees its own value come back, so it never gets the chance to re-evaluate. Each node
-- receives only the OTHER's value and applies it. Once applied the row carries the
-- other's stamp, so neither publishes again.
--
-- THE FIX: replace "is this my echo?" with "is this newer than what I have?".
--   * a genuine echo carries an EQUAL timestamp, so it is not newer, so it is not
--     applied, so no WAL is written and no new event is produced -- it terminates
--     itself. Loop prevention comes free.
--   * a genuine conflict resolves to the globally-latest write on every node, so all
--     nodes converge on the same value.
-- Conflict resolution and loop prevention become ONE mechanism instead of two.
--
-- WHY A DEDICATED COLUMN, NOT THE APPLICATION'S OWN TIMESTAMP. Odoo's write_date is
-- fully populated, but OpenMRS's person.date_changed is NULL on 120,657 of 121,782 rows
-- (it is set on update, never on create). A rule that works on one engine and silently
-- does nothing on another is worse than no rule. sync_updated_at is set by the same
-- trigger that sets sync_origin, so it is always present, on every table, on every node.
--
-- clock_timestamp(), NOT now(). now() returns the transaction start time, so every row
-- written in one transaction would carry an identical timestamp and ties would be
-- decided by the origin tie-break rather than by time.
--
-- THE TIE-BREAK IS NOT DECORATION. Two writes in the same microsecond with different
-- data would otherwise leave both nodes rejecting each other's row and staying diverged
-- -- the exact failure being fixed. Comparing sync_origin gives a total order that every
-- node computes identically.
--
-- CLOCK SKEW IS THE RESIDUAL RISK. Last-writer-wins on physical time is only as good as
-- the clocks. The nodes need NTP; the tie-break bounds the damage but does not remove
-- it. Recorded here rather than left implicit.
--
-- Usage: psql -U postgres -d odoo -v node=rawach -f odoo/apply-odoo-conflict-rule.sql
\set ON_ERROR_STOP on
BEGIN;

SELECT set_config('myvars.node', :'node', false);

DO $do$
DECLARE
  v_node   text := current_setting('myvars.node');
  v_tbl    text;
  v_tables text[] := ARRAY[
    'res_partner',
    'product_template','product_product','product_category','product_uom',
    'sale_order','sale_order_line','stock_move','stock_quant','stock_picking',
    'account_invoice','account_invoice_line'
  ];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'odoo_sink') THEN
    RAISE EXCEPTION 'odoo_sink role missing -- run odoo/create-odoo-sink-role.sh first';
  END IF;

  FOREACH v_tbl IN ARRAY v_tables LOOP
    EXECUTE format(
      'ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS sync_updated_at timestamptz', v_tbl);

    -- Seed existing rows so the guard has something to compare against. Rows already
    -- here predate the rule; giving them epoch means the first real write to any of them
    -- always wins, which is the safe direction -- a NULL would make every comparison
    -- NULL and every write be rejected.
    EXECUTE format(
      'UPDATE public.%I SET sync_updated_at = ''epoch''::timestamptz WHERE sync_updated_at IS NULL', v_tbl);

    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN sync_updated_at SET NOT NULL', v_tbl);
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN sync_updated_at SET DEFAULT ''epoch''::timestamptz', v_tbl);
  END LOOP;
END $do$;

CREATE OR REPLACE FUNCTION public.stamp_sync_origin() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  IF session_user = 'odoo_sink' THEN
    -- Replicated write. Apply it only if it is genuinely newer than what we hold.
    IF TG_OP = 'UPDATE' THEN
      IF NEW.sync_updated_at < OLD.sync_updated_at THEN
        RETURN NULL;                       -- stale: discard, write nothing, emit nothing
      END IF;
      IF NEW.sync_updated_at = OLD.sync_updated_at
         AND NEW.sync_origin IS NOT DISTINCT FROM OLD.sync_origin THEN
        RETURN NULL;                       -- our own echo, or a byte-identical replay
      END IF;
      IF NEW.sync_updated_at = OLD.sync_updated_at
         AND NEW.sync_origin < OLD.sync_origin THEN
        RETURN NULL;                       -- exact tie: lower origin loses, everywhere
      END IF;
    END IF;
    RETURN NEW;                            -- keep the originating node's stamp and time
  END IF;

  -- Local application write: claim the row and timestamp it.
  NEW.sync_origin     := TG_ARGV[0];
  NEW.sync_updated_at := clock_timestamp();
  RETURN NEW;
END $fn$;

COMMIT;
