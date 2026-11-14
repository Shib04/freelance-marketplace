SET client_encoding = 'UTF8';
-- =====================================================================
-- Marketplace Freelance - constraint / business-rule tests
-- Run AFTER schema.sql + seed.sql:
--   psql -U postgres -d lab_freelance -f database/tests.sql
-- Every test runs inside its own sub-transaction that is ALWAYS rolled back,
-- so your sample data is untouched. The LAST statement of this file is the
-- result table (pgAdmin only displays the result of the last statement).
-- Result: one table with expected vs actual SQLSTATE and PASS/FAIL.
--   00000 = statement succeeded   23505 = unique   23503 = foreign key   23514 = check/rule
-- =====================================================================

DROP TABLE IF EXISTS pg_temp.test_results;

CREATE TEMP TABLE test_results (
    no       INTEGER,
    title    TEXT,
    expected TEXT,
    actual   TEXT,
    result   TEXT,
    message  TEXT
);

-- helpers (live only in this session) -----------------------------------
CREATE OR REPLACE FUNCTION pg_temp.uid(p_email TEXT) RETURNS BIGINT LANGUAGE sql AS
$$ SELECT id FROM users WHERE email = p_email $$;

CREATE OR REPLACE FUNCTION pg_temp.pjid(p_pattern TEXT) RETURNS BIGINT LANGUAGE sql AS
$$ SELECT id FROM projects WHERE title LIKE p_pattern $$;

CREATE OR REPLACE FUNCTION pg_temp.prid(p_email TEXT, p_pattern TEXT) RETURNS BIGINT LANGUAGE sql AS
$$ SELECT pr.id FROM proposals pr
     JOIN projects p ON p.id = pr.project_id
     JOIN users u    ON u.id = pr.freelancer_id
    WHERE u.email = p_email AND p.title LIKE p_pattern $$;

CREATE OR REPLACE FUNCTION pg_temp.run_test(p_no INT, p_title TEXT, p_sql TEXT, p_expected TEXT)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_state TEXT;
    v_msg   TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        -- statement succeeded: force a rollback of its effects
        RAISE EXCEPTION 'rollback' USING ERRCODE = 'ZZ001';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    END;
    IF v_state = 'ZZ001' THEN
        v_state := '00000';
        v_msg   := 'statement succeeded (changes rolled back)';
    END IF;
    INSERT INTO test_results
    VALUES (p_no, p_title, p_expected, v_state,
            CASE WHEN v_state = p_expected THEN 'PASS' ELSE 'FAIL' END, v_msg);
END;
$$;

-- ---------------------------------------------------------------------
-- A. Required scenarios
-- ---------------------------------------------------------------------
DO $do$ BEGIN
PERFORM pg_temp.run_test(1, 'Duplicate email (exact)',
$q$ INSERT INTO users (first_name,last_name,email,password_hash)
    VALUES ('x','y','ali.ahmadi@example.com', repeat('h',60)) $q$, '23505');

PERFORM pg_temp.run_test(2, 'Duplicate email (different letter case)',
$q$ INSERT INTO users (first_name,last_name,email,password_hash)
    VALUES ('x','y','ALI.AHMADI@Example.com', repeat('h',60)) $q$, '23505');

PERFORM pg_temp.run_test(3, 'Invalid foreign key: proposal for a non-existent project',
$q$ INSERT INTO proposals (project_id, freelancer_id, amount, cover_letter)
    VALUES (999999, pg_temp.uid('reza.mohammadi@example.com'), 1000, 'hi') $q$, '23503');

PERFORM pg_temp.run_test(4, 'Invalid foreign key: project_skills with non-existent skill',
$q$ INSERT INTO project_skills (project_id, skill_id)
    VALUES (pg_temp.pjid('%فروشگاه%'), 999999) $q$, '23503');

PERFORM pg_temp.run_test(5, 'Duplicate proposal (same freelancer, same project)',
$q$ INSERT INTO proposals (project_id, freelancer_id, amount, cover_letter)
    VALUES (pg_temp.pjid('%فروشگاه%'), pg_temp.uid('ali.ahmadi@example.com'), 39000000, 'again') $q$, '23505');

PERFORM pg_temp.run_test(6, 'Project budget = 0',
$q$ INSERT INTO projects (employer_id,title,description,pricing_type,budget)
    VALUES (pg_temp.uid('ali.ahmadi@example.com'),'t','d','fixed',0) $q$, '23514');

PERFORM pg_temp.run_test(7, 'Project budget negative',
$q$ INSERT INTO projects (employer_id,title,description,pricing_type,budget)
    VALUES (pg_temp.uid('ali.ahmadi@example.com'),'t','d','fixed',-5000) $q$, '23514');

PERFORM pg_temp.run_test(8, 'Hourly project with hourly rate = 0',
$q$ INSERT INTO projects (employer_id,title,description,pricing_type,budget)
    VALUES (pg_temp.uid('ali.ahmadi@example.com'),'t','d','hourly',0) $q$, '23514');

PERFORM pg_temp.run_test(9, 'Proposal amount / hourly rate = 0',
$q$ INSERT INTO proposals (project_id, freelancer_id, amount, cover_letter)
    VALUES (pg_temp.pjid('%رزرو نوبت%'), pg_temp.uid('reza.mohammadi@example.com'), 0, 'hi') $q$, '23514');

PERFORM pg_temp.run_test(10, 'Proposal estimated_days = 0',
$q$ INSERT INTO proposals (project_id, freelancer_id, amount, cover_letter, estimated_days)
    VALUES (pg_temp.pjid('%رزرو نوبت%'), pg_temp.uid('reza.mohammadi@example.com'), 1000, 'hi', 0) $q$, '23514');

PERFORM pg_temp.run_test(11, 'Accepting more than one proposal in one project (trigger rule)',
$q$ DO $b$ BEGIN
      UPDATE proposals SET status='accepted'
       WHERE id = pg_temp.prid('ali.ahmadi@example.com','%فروشگاه%');      -- 1st accept: OK
      UPDATE proposals SET status='accepted'
       WHERE id = pg_temp.prid('reza.mohammadi@example.com','%فروشگاه%');  -- 2nd accept: must fail
    END $b$ $q$, '23514');

PERFORM pg_temp.run_test(12, 'Two accepted proposals even with triggers disabled (partial unique index)',
$q$ DO $b$ BEGIN
      ALTER TABLE proposals DISABLE TRIGGER USER;
      UPDATE proposals SET status='accepted'
       WHERE id = pg_temp.prid('ali.ahmadi@example.com','%فروشگاه%');
      UPDATE proposals SET status='accepted'
       WHERE id = pg_temp.prid('reza.mohammadi@example.com','%فروشگاه%');
    END $b$ $q$, '23505');

-- ---------------------------------------------------------------------
-- B. Business rules
-- ---------------------------------------------------------------------
PERFORM pg_temp.run_test(13, 'User sends a proposal to his/her own project',
$q$ INSERT INTO proposals (project_id, freelancer_id, amount, cover_letter)
    VALUES (pg_temp.pjid('%فروشگاه%'), pg_temp.uid('sara.karimi@example.com'), 1000, 'me') $q$, '23514');

PERFORM pg_temp.run_test(14, 'Proposal for a project that is not open (in_progress)',
$q$ INSERT INTO proposals (project_id, freelancer_id, amount, cover_letter)
    VALUES (pg_temp.pjid('%داشبورد%'), pg_temp.uid('ali.ahmadi@example.com'), 1000, 'late') $q$, '23514');

PERFORM pg_temp.run_test(15, 'Admin creates a project',
$q$ INSERT INTO projects (employer_id,title,description,pricing_type,budget)
    VALUES (pg_temp.uid('admin@marketplace.test'),'t','d','fixed',1000) $q$, '23514');

PERFORM pg_temp.run_test(16, 'Admin sends a proposal',
$q$ INSERT INTO proposals (project_id, freelancer_id, amount, cover_letter)
    VALUES (pg_temp.pjid('%رزرو نوبت%'), pg_temp.uid('admin@marketplace.test'), 1000, 'hi') $q$, '23514');

PERFORM pg_temp.run_test(17, 'Admin gets a profile',
$q$ INSERT INTO profiles_user (user_id, headline)
    VALUES (pg_temp.uid('admin@marketplace.test'), 'x') $q$, '23514');

PERFORM pg_temp.run_test(18, 'Grant admin to a user who already has projects',
$q$ INSERT INTO admins (user_id, granted_by)
    VALUES (pg_temp.uid('ali.ahmadi@example.com'), pg_temp.uid('admin@marketplace.test')) $q$, '23514');

PERFORM pg_temp.run_test(19, 'Plain-text (too short) password stored',
$q$ INSERT INTO users (first_name,last_name,email,password_hash)
    VALUES ('x','y','new@example.com','123456') $q$, '23514');

PERFORM pg_temp.run_test(20, 'Invalid email format',
$q$ INSERT INTO users (first_name,last_name,email,password_hash)
    VALUES ('x','y','not-an-email', repeat('h',60)) $q$, '23514');

PERFORM pg_temp.run_test(21, 'Invalid project status value',
$q$ INSERT INTO projects (employer_id,title,description,pricing_type,budget,status)
    VALUES (pg_temp.uid('ali.ahmadi@example.com'),'t','d','fixed',1000,'archived') $q$, '23514');

PERFORM pg_temp.run_test(22, 'Illegal project transition in_progress -> draft',
$q$ UPDATE projects SET status='draft' WHERE id = pg_temp.pjid('%داشبورد%') $q$, '23514');

PERFORM pg_temp.run_test(23, 'Open -> in_progress without an accepted proposal',
$q$ UPDATE projects SET status='in_progress' WHERE id = pg_temp.pjid('%رزرو نوبت%') $q$, '23514');

PERFORM pg_temp.run_test(24, 'Change pricing_type after proposals exist',
$q$ UPDATE projects SET pricing_type='hourly' WHERE id = pg_temp.pjid('%فروشگاه%') $q$, '23514');

PERFORM pg_temp.run_test(25, 'estimated_hours on a fixed-price project',
$q$ INSERT INTO proposals (project_id, freelancer_id, amount, cover_letter, estimated_hours)
    VALUES (pg_temp.pjid('%فروشگاه%'), pg_temp.uid('maryam.hosseini@example.com'), 1000, 'hi', 10) $q$, '23514');

PERFORM pg_temp.run_test(26, 'Edit amount of an already accepted proposal',
$q$ UPDATE proposals SET amount = 1
     WHERE id = pg_temp.prid('reza.mohammadi@example.com','%داشبورد%') $q$, '23514');

PERFORM pg_temp.run_test(27, 'Change status of a rejected proposal back to pending',
$q$ UPDATE proposals SET status='pending'
     WHERE id = pg_temp.prid('maryam.hosseini@example.com','%داشبورد%') $q$, '23514');

PERFORM pg_temp.run_test(28, 'Delete a user who owns projects (no silent cascade)',
$q$ DELETE FROM users WHERE email = 'sara.karimi@example.com' $q$, '23503');

PERFORM pg_temp.run_test(29, 'Delete a project that has proposals',
$q$ DELETE FROM projects WHERE id = pg_temp.pjid('%فروشگاه%') $q$, '23503');

PERFORM pg_temp.run_test(30, 'Second profile for the same user',
$q$ INSERT INTO profiles_user (user_id, headline)
    VALUES (pg_temp.uid('ali.ahmadi@example.com'), 'dup') $q$, '23505');

PERFORM pg_temp.run_test(31, 'Duplicate skill name (different case)',
$q$ INSERT INTO skills (name) VALUES ('python') $q$, '23505');

PERFORM pg_temp.run_test(32, 'Duplicate category title',
$q$ INSERT INTO categories (title) VALUES ('تحلیل داده') $q$, '23505');

-- ---------------------------------------------------------------------
-- C. Positive tests (must SUCCEED = 00000)
-- ---------------------------------------------------------------------
PERFORM pg_temp.run_test(33, 'Valid new proposal on an open project',
$q$ INSERT INTO proposals (project_id, freelancer_id, amount, cover_letter, estimated_days)
    VALUES (pg_temp.pjid('%فروشگاه%'), pg_temp.uid('maryam.hosseini@example.com'), 41000000, 'ok', 20) $q$, '00000');

PERFORM pg_temp.run_test(34, 'Accept a proposal => project in_progress, other pending => rejected',
$q$ DO $b$ BEGIN
      UPDATE proposals SET status='accepted'
       WHERE id = pg_temp.prid('ali.ahmadi@example.com','%فروشگاه%');
      IF (SELECT status FROM projects WHERE id = pg_temp.pjid('%فروشگاه%')) <> 'in_progress' THEN
          RAISE EXCEPTION 'project was not moved to in_progress';
      END IF;
      IF (SELECT status FROM proposals
           WHERE id = pg_temp.prid('reza.mohammadi@example.com','%فروشگاه%')) <> 'rejected' THEN
          RAISE EXCEPTION 'other pending proposal was not rejected';
      END IF;
    END $b$ $q$, '00000');

PERFORM pg_temp.run_test(35, 'Freelancer withdraws a pending proposal',
$q$ UPDATE proposals SET status='withdrawn'
     WHERE id = pg_temp.prid('ali.ahmadi@example.com','%فروشگاه%') $q$, '00000');

PERFORM pg_temp.run_test(36, 'Cancelling an open project rejects its pending proposals',
$q$ DO $b$ BEGIN
      UPDATE projects SET status='cancelled' WHERE id = pg_temp.pjid('%فروشگاه%');
      IF EXISTS (SELECT 1 FROM proposals WHERE project_id = pg_temp.pjid('%فروشگاه%') AND status='pending') THEN
          RAISE EXCEPTION 'pending proposals were not rejected';
      END IF;
    END $b$ $q$, '00000');

END $do$;

-- ---------------------------------------------------------------------
SELECT no, title, expected, actual, result, left(message, 90) AS message
FROM test_results ORDER BY no;
