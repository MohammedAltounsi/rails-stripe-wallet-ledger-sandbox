namespace :db do
  desc "Install DB-level integrity guarantees (PostgreSQL only). Idempotent — safe on every boot."
  task ensure_constraints: :environment do
    conn = ActiveRecord::Base.connection
    unless conn.adapter_name.match?(/postg/i)
      puts "db:ensure_constraints — skipped (#{conn.adapter_name}, not PostgreSQL)."
      next
    end

    # The ledger's core invariant is that every entry's postings sum to zero.
    # Ruby enforces it (Entry#must_balance), but app code can have bugs. This
    # makes it a property of the DATABASE: a deferred CONSTRAINT TRIGGER checks
    # the sum at COMMIT (so a valid two-sided entry built across two INSERTs
    # still passes), and raises otherwise. Money cannot be committed unbalanced,
    # no matter what the application does.
    conn.execute(<<~SQL)
      CREATE OR REPLACE FUNCTION entry_must_balance() RETURNS trigger AS $$
      DECLARE
        eid   bigint := COALESCE(NEW.entry_id, OLD.entry_id);
        total bigint;
      BEGIN
        SELECT COALESCE(SUM(amount_cents), 0) INTO total FROM postings WHERE entry_id = eid;
        -- total = 0 also covers the "all postings deleted" case (no rows -> 0).
        IF total <> 0 THEN
          RAISE EXCEPTION 'ledger integrity: entry % postings sum to % (must be 0)', eid, total;
        END IF;
        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS postings_must_balance ON postings;
      CREATE CONSTRAINT TRIGGER postings_must_balance
        AFTER INSERT OR UPDATE OR DELETE ON postings
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION entry_must_balance();
    SQL

    puts "db:ensure_constraints — installed: postings must balance per entry (deferred trigger)."
  end
end
