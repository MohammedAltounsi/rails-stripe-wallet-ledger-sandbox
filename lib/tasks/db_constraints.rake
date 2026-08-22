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

    # A stored-value wallet must never go negative. The app locks the wallet row
    # during checkout so concurrent spends can't overdraw, but this makes the
    # rule a property of the DATABASE too: any committed change that would leave a
    # wallet:* account with a negative balance raises. Defense-in-depth against
    # any future code path that forgets the lock.
    conn.execute(<<~SQL)
      CREATE OR REPLACE FUNCTION wallet_no_overdraft() RETURNS trigger AS $$
      DECLARE
        acct bigint := COALESCE(NEW.account_id, OLD.account_id);
        nm   text;
        bal  bigint;
      BEGIN
        SELECT name INTO nm FROM accounts WHERE id = acct;
        IF nm LIKE 'wallet:%' THEN
          SELECT COALESCE(SUM(amount_cents), 0) INTO bal FROM postings WHERE account_id = acct;
          IF bal < 0 THEN
            RAISE EXCEPTION 'ledger integrity: wallet % balance % is negative (overdraft blocked)', nm, bal;
          END IF;
        END IF;
        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS wallet_no_overdraft ON postings;
      CREATE CONSTRAINT TRIGGER wallet_no_overdraft
        AFTER INSERT OR UPDATE OR DELETE ON postings
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW EXECUTE FUNCTION wallet_no_overdraft();
    SQL

    puts "db:ensure_constraints — installed: postings must balance per entry + wallets cannot overdraw (deferred triggers)."
  end
end
