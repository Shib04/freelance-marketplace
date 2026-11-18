SET client_encoding = 'UTF8';
-- =====================================================================
-- Marketplace Freelance - database schema
-- DBMS : PostgreSQL 17
-- Usage: psql -U postgres -d lab_freelance -v ON_ERROR_STOP=1 -f database/schema.sql
--
-- WARNING: the DROP section below makes the script re-runnable in a
-- development database. It DESTROYS existing data. Never run it in production.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Reset (development only)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS password_reset_tokens CASCADE;
DROP TABLE IF EXISTS proposals          CASCADE;
DROP TABLE IF EXISTS project_skills     CASCADE;
DROP TABLE IF EXISTS project_categories CASCADE;
DROP TABLE IF EXISTS projects           CASCADE;
DROP TABLE IF EXISTS certificates       CASCADE;
DROP TABLE IF EXISTS portfolio_items    CASCADE;
DROP TABLE IF EXISTS profile_skills     CASCADE;
DROP TABLE IF EXISTS profiles_user      CASCADE;
DROP TABLE IF EXISTS skills             CASCADE;
DROP TABLE IF EXISTS categories         CASCADE;
DROP TABLE IF EXISTS admins             CASCADE;
DROP TABLE IF EXISTS users              CASCADE;

-- ---------------------------------------------------------------------
-- 1. Generic helper: keep updated_at fresh
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. users  (every account: regular users AND admins)
-- ---------------------------------------------------------------------
CREATE TABLE users (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name    VARCHAR(100) NOT NULL,
    last_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(254) NOT NULL,
    phone         VARCHAR(20),                                  -- optional
    password_hash VARCHAR(255) NOT NULL,                        -- bcrypt/argon2 hash, NEVER plain text
    status        VARCHAR(10)  NOT NULL DEFAULT 'active',
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT users_first_name_not_blank_chk CHECK (btrim(first_name) <> ''),
    CONSTRAINT users_last_name_not_blank_chk  CHECK (btrim(last_name)  <> ''),
    CONSTRAINT users_email_format_chk
        CHECK (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
    CONSTRAINT users_phone_format_chk
        CHECK (phone IS NULL OR phone ~ '^\+?[0-9]{10,15}$'),
    -- A real bcrypt hash is 60 chars, argon2 is longer. A short value is almost surely plain text.
    CONSTRAINT users_password_hash_len_chk CHECK (char_length(password_hash) >= 60),
    CONSTRAINT users_status_chk CHECK (status IN ('active', 'inactive', 'blocked')),
    CONSTRAINT users_phone_key UNIQUE (phone)                   -- NULLs are allowed many times
);

-- Email uniqueness is case-insensitive: Ali@x.com and ali@x.com are the same address.
CREATE UNIQUE INDEX users_email_lower_uq ON users (lower(email));

COMMENT ON TABLE  users IS 'All platform accounts. Admin accounts are additionally listed in table admins.';
COMMENT ON COLUMN users.status IS 'active | inactive | blocked. Users are never hard-deleted; use inactive/blocked.';

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------
-- 3. admins  (1:1 extension of users; presence of a row == admin access)
-- ---------------------------------------------------------------------
CREATE TABLE admins (
    user_id    BIGINT PRIMARY KEY REFERENCES users (id) ON DELETE RESTRICT,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    granted_by BIGINT REFERENCES users (id) ON DELETE SET NULL, -- NULL = bootstrap/first admin
    CONSTRAINT admins_no_self_grant_chk CHECK (granted_by IS NULL OR granted_by <> user_id)
);

COMMENT ON TABLE admins IS 'Accounts with administrative access, with the time (and giver) of the grant.';

-- is_admin(): single place that answers "does this account have admin access?"
CREATE OR REPLACE FUNCTION is_admin(p_user_id BIGINT) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM admins WHERE user_id = p_user_id);
$$;

-- ---------------------------------------------------------------------
-- 3b. password_reset_tokens (phase 3: "forgot password" links)
--     The raw token is only sent to the user; the database stores just its
--     SHA-256 fingerprint. A token is single-use (used_at) and time-limited (expires_at).
-- ---------------------------------------------------------------------
CREATE TABLE password_reset_tokens (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    token_hash CHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at    TIMESTAMPTZ,
    CONSTRAINT password_reset_tokens_hash_key UNIQUE (token_hash),
    CONSTRAINT password_reset_tokens_expiry_chk CHECK (expires_at > created_at)
);
CREATE INDEX password_reset_tokens_user_idx ON password_reset_tokens (user_id);

-- ---------------------------------------------------------------------
-- 4. profiles_user  (at most one profile per regular user)
-- ---------------------------------------------------------------------
CREATE TABLE profiles_user (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    headline   VARCHAR(150),                 -- professional title (optional)
    bio        TEXT,                         -- short introduction (optional)
    country    VARCHAR(100),                 -- location (optional)
    city       VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT profiles_user_user_id_key UNIQUE (user_id)   -- "at most one profile per user"
);

CREATE TRIGGER trg_profiles_user_updated_at BEFORE UPDATE ON profiles_user
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------
-- 5. skills + categories (lookup tables, managed by admins)
-- ---------------------------------------------------------------------
CREATE TABLE skills (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT skills_name_not_blank_chk CHECK (btrim(name) <> '')
);
CREATE UNIQUE INDEX skills_name_lower_uq ON skills (lower(name));

CREATE TABLE categories (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title       VARCHAR(100) NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT categories_title_not_blank_chk CHECK (btrim(title) <> '')
);
CREATE UNIQUE INDEX categories_title_lower_uq ON categories (lower(title));

-- ---------------------------------------------------------------------
-- 6. Profile details
-- ---------------------------------------------------------------------
-- M:N  profile <-> skill
CREATE TABLE profile_skills (
    profile_id BIGINT NOT NULL REFERENCES profiles_user (id) ON DELETE CASCADE,
    skill_id   BIGINT NOT NULL REFERENCES skills (id)        ON DELETE RESTRICT,
    added_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (profile_id, skill_id)
);
CREATE INDEX profile_skills_skill_idx ON profile_skills (skill_id);

-- 1:N  profile -> portfolio items
CREATE TABLE portfolio_items (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    profile_id   BIGINT NOT NULL REFERENCES profiles_user (id) ON DELETE CASCADE,
    title        VARCHAR(200) NOT NULL,
    description  TEXT,
    project_url  VARCHAR(500),
    completed_on DATE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT portfolio_title_not_blank_chk CHECK (btrim(title) <> ''),
    CONSTRAINT portfolio_url_chk CHECK (project_url IS NULL OR project_url ~* '^https?://')
);
CREATE INDEX portfolio_items_profile_idx ON portfolio_items (profile_id);

-- 1:N  profile -> certificates
CREATE TABLE certificates (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    profile_id     BIGINT NOT NULL REFERENCES profiles_user (id) ON DELETE CASCADE,
    title          VARCHAR(200) NOT NULL,
    issuer         VARCHAR(200),
    issued_on      DATE,
    expires_on     DATE,
    credential_url VARCHAR(500),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT certificates_title_not_blank_chk CHECK (btrim(title) <> ''),
    CONSTRAINT certificates_dates_chk
        CHECK (issued_on IS NULL OR expires_on IS NULL OR expires_on >= issued_on),
    CONSTRAINT certificates_url_chk
        CHECK (credential_url IS NULL OR credential_url ~* '^https?://')
);
CREATE INDEX certificates_profile_idx ON certificates (profile_id);

-- ---------------------------------------------------------------------
-- 7. projects
-- ---------------------------------------------------------------------
CREATE TABLE projects (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employer_id  BIGINT NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    title        VARCHAR(200) NOT NULL,
    description  TEXT NOT NULL,
    pricing_type VARCHAR(10) NOT NULL,
    budget       NUMERIC(14,2) NOT NULL,   -- fixed: total budget | hourly: hourly rate (single currency)
    status       VARCHAR(15) NOT NULL DEFAULT 'draft',
    deadline     TIMESTAMPTZ,              -- optional
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT projects_title_not_blank_chk CHECK (btrim(title) <> ''),
    CONSTRAINT projects_pricing_type_chk CHECK (pricing_type IN ('fixed', 'hourly')),
    CONSTRAINT projects_budget_positive_chk CHECK (budget > 0),
    CONSTRAINT projects_status_chk
        CHECK (status IN ('draft', 'open', 'in_progress', 'completed', 'cancelled')),
    CONSTRAINT projects_deadline_chk CHECK (deadline IS NULL OR deadline > created_at)
);
CREATE INDEX projects_employer_idx ON projects (employer_id);
CREATE INDEX projects_status_created_idx ON projects (status, created_at DESC);

COMMENT ON COLUMN projects.budget IS 'pricing_type=fixed: total budget; pricing_type=hourly: hourly rate.';

CREATE TRIGGER trg_projects_updated_at BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- M:N  project <-> category
CREATE TABLE project_categories (
    project_id  BIGINT NOT NULL REFERENCES projects (id)   ON DELETE CASCADE,
    category_id BIGINT NOT NULL REFERENCES categories (id) ON DELETE RESTRICT,
    PRIMARY KEY (project_id, category_id)
);
CREATE INDEX project_categories_category_idx ON project_categories (category_id);

-- M:N  project <-> required skill
CREATE TABLE project_skills (
    project_id BIGINT NOT NULL REFERENCES projects (id) ON DELETE CASCADE,
    skill_id   BIGINT NOT NULL REFERENCES skills (id)   ON DELETE RESTRICT,
    PRIMARY KEY (project_id, skill_id)
);
CREATE INDEX project_skills_skill_idx ON project_skills (skill_id);

-- ---------------------------------------------------------------------
-- 8. proposals
-- ---------------------------------------------------------------------
CREATE TABLE proposals (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id      BIGINT NOT NULL REFERENCES projects (id) ON DELETE RESTRICT,
    freelancer_id   BIGINT NOT NULL REFERENCES users (id)    ON DELETE RESTRICT,
    amount          NUMERIC(14,2) NOT NULL,  -- fixed project: total price | hourly project: hourly rate
    cover_letter    TEXT NOT NULL,
    estimated_days  INTEGER,                 -- optional: estimated duration in days
    estimated_hours INTEGER,                 -- optional: only for hourly projects
    status          VARCHAR(10) NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT proposals_amount_positive_chk CHECK (amount > 0),
    CONSTRAINT proposals_days_positive_chk   CHECK (estimated_days  IS NULL OR estimated_days  > 0),
    CONSTRAINT proposals_hours_positive_chk  CHECK (estimated_hours IS NULL OR estimated_hours > 0),
    CONSTRAINT proposals_cover_letter_not_blank_chk CHECK (btrim(cover_letter) <> ''),
    CONSTRAINT proposals_status_chk
        CHECK (status IN ('pending', 'accepted', 'rejected', 'withdrawn')),
    -- a freelancer may send at most ONE proposal per project
    CONSTRAINT proposals_one_per_freelancer_uq UNIQUE (project_id, freelancer_id)
);

-- At most ONE accepted proposal per project (partial unique index = last line of defence).
CREATE UNIQUE INDEX proposals_one_accepted_per_project_uq
    ON proposals (project_id) WHERE status = 'accepted';

CREATE INDEX proposals_freelancer_idx ON proposals (freelancer_id);

COMMENT ON COLUMN proposals.amount IS 'Project pricing_type=fixed: total price; hourly: hourly rate.';

CREATE TRIGGER trg_proposals_updated_at BEFORE UPDATE ON proposals
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =====================================================================
-- 9. Business-rule triggers (rules that need data from OTHER tables,
--    which CHECK constraints cannot express)
--    All violations raise SQLSTATE 23514 (check_violation).
-- =====================================================================

-- 9.1 admins: an account that already acts as a regular user cannot become admin
CREATE OR REPLACE FUNCTION fn_admins_before_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM profiles_user WHERE user_id = NEW.user_id)
       OR EXISTS (SELECT 1 FROM projects  WHERE employer_id = NEW.user_id)
       OR EXISTS (SELECT 1 FROM proposals WHERE freelancer_id = NEW.user_id) THEN
        RAISE EXCEPTION 'User % already has a profile/projects/proposals and cannot become an admin', NEW.user_id
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.granted_by IS NOT NULL AND NOT is_admin(NEW.granted_by) THEN
        RAISE EXCEPTION 'granted_by (user %) is not an admin', NEW.granted_by
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_admins_before_insert BEFORE INSERT ON admins
    FOR EACH ROW EXECUTE FUNCTION fn_admins_before_insert();

-- 9.2 profiles: admins have no profile
CREATE OR REPLACE FUNCTION fn_profiles_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF is_admin(NEW.user_id) THEN
        RAISE EXCEPTION 'Admin accounts cannot have a user profile (user %)', NEW.user_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_profiles_guard BEFORE INSERT OR UPDATE OF user_id ON profiles_user
    FOR EACH ROW EXECUTE FUNCTION fn_profiles_guard();

-- 9.3 projects: INSERT rules
CREATE OR REPLACE FUNCTION fn_projects_before_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_user_status TEXT;
BEGIN
    IF is_admin(NEW.employer_id) THEN
        RAISE EXCEPTION 'Admin accounts cannot create projects (user %)', NEW.employer_id
            USING ERRCODE = 'check_violation';
    END IF;
    SELECT u.status INTO v_user_status FROM users u WHERE u.id = NEW.employer_id;
    IF v_user_status IS NOT NULL AND v_user_status <> 'active' THEN
        RAISE EXCEPTION 'Only active users can create projects (user % is %)', NEW.employer_id, v_user_status
            USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status NOT IN ('draft', 'open') THEN
        RAISE EXCEPTION 'A new project must start as draft or open, not %', NEW.status
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_projects_before_insert BEFORE INSERT ON projects
    FOR EACH ROW EXECUTE FUNCTION fn_projects_before_insert();

-- 9.4 projects: UPDATE rules (immutable owner, allowed status transitions)
--     draft -> open | cancelled
--     open  -> in_progress (only via an accepted proposal) | cancelled
--     in_progress -> completed | cancelled
--     completed / cancelled are final
CREATE OR REPLACE FUNCTION fn_projects_before_update() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.employer_id IS DISTINCT FROM OLD.employer_id THEN
        RAISE EXCEPTION 'The employer of a project cannot be changed'
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.pricing_type IS DISTINCT FROM OLD.pricing_type
       AND EXISTS (SELECT 1 FROM proposals WHERE project_id = OLD.id) THEN
        RAISE EXCEPTION 'pricing_type cannot change after proposals were received'
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT (   (OLD.status = 'draft'       AND NEW.status IN ('open', 'cancelled'))
                OR (OLD.status = 'open'        AND NEW.status IN ('in_progress', 'cancelled'))
                OR (OLD.status = 'in_progress' AND NEW.status IN ('completed', 'cancelled')) ) THEN
            RAISE EXCEPTION 'Invalid project status transition: % -> %', OLD.status, NEW.status
                USING ERRCODE = 'check_violation';
        END IF;

        IF NEW.status = 'in_progress'
           AND NOT EXISTS (SELECT 1 FROM proposals
                           WHERE project_id = OLD.id AND status = 'accepted') THEN
            RAISE EXCEPTION 'A project can become in_progress only when one proposal is accepted'
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_projects_before_update BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION fn_projects_before_update();

-- 9.5 projects: when cancelled, still-pending proposals are rejected automatically
CREATE OR REPLACE FUNCTION fn_projects_after_cancel() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE proposals SET status = 'rejected'
     WHERE project_id = NEW.id AND status = 'pending';
    RETURN NULL;
END;
$$;
CREATE TRIGGER trg_projects_after_cancel AFTER UPDATE OF status ON projects
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'cancelled')
    EXECUTE FUNCTION fn_projects_after_cancel();

-- 9.6 proposals: INSERT rules
CREATE OR REPLACE FUNCTION fn_proposals_before_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_employer_id  BIGINT;
    v_proj_status  TEXT;
    v_pricing_type TEXT;
    v_user_status  TEXT;
BEGIN
    SELECT p.employer_id, p.status, p.pricing_type
      INTO v_employer_id, v_proj_status, v_pricing_type
      FROM projects p WHERE p.id = NEW.project_id;

    IF NOT FOUND THEN
        RETURN NEW;   -- the foreign key will reject the row with a proper error (23503)
    END IF;

    IF NEW.status <> 'pending' THEN
        RAISE EXCEPTION 'A new proposal must start as pending' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.freelancer_id = v_employer_id THEN
        RAISE EXCEPTION 'A user cannot send a proposal to his/her own project'
            USING ERRCODE = 'check_violation';
    END IF;
    IF v_proj_status <> 'open' THEN
        RAISE EXCEPTION 'Proposals can only be sent to open projects (project status: %)', v_proj_status
            USING ERRCODE = 'check_violation';
    END IF;
    IF is_admin(NEW.freelancer_id) THEN
        RAISE EXCEPTION 'Admin accounts cannot send proposals (user %)', NEW.freelancer_id
            USING ERRCODE = 'check_violation';
    END IF;
    SELECT u.status INTO v_user_status FROM users u WHERE u.id = NEW.freelancer_id;
    IF v_user_status IS NOT NULL AND v_user_status <> 'active' THEN
        RAISE EXCEPTION 'Only active users can send proposals (user % is %)', NEW.freelancer_id, v_user_status
            USING ERRCODE = 'check_violation';
    END IF;
    IF v_pricing_type = 'fixed' AND NEW.estimated_hours IS NOT NULL THEN
        RAISE EXCEPTION 'estimated_hours is only meaningful for hourly projects'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_proposals_before_insert BEFORE INSERT ON proposals
    FOR EACH ROW EXECUTE FUNCTION fn_proposals_before_insert();

-- 9.7 proposals: UPDATE rules
--     pending -> accepted | rejected | withdrawn ; the three final states never change again.
--     Accepting requires the project to be open (row is locked => no race between two accepts).
CREATE OR REPLACE FUNCTION fn_proposals_before_update() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_proj_status TEXT;
BEGIN
    IF NEW.project_id <> OLD.project_id OR NEW.freelancer_id <> OLD.freelancer_id THEN
        RAISE EXCEPTION 'project_id and freelancer_id of a proposal cannot be changed'
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.status = OLD.status THEN
        IF OLD.status <> 'pending'
           AND (   NEW.amount <> OLD.amount
                OR NEW.cover_letter <> OLD.cover_letter
                OR NEW.estimated_days  IS DISTINCT FROM OLD.estimated_days
                OR NEW.estimated_hours IS DISTINCT FROM OLD.estimated_hours) THEN
            RAISE EXCEPTION 'Only pending proposals can be edited (current status: %)', OLD.status
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.status <> 'pending' THEN
        RAISE EXCEPTION 'Proposal status "%" is final and cannot change to "%"', OLD.status, NEW.status
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.status = 'accepted' THEN
        SELECT p.status INTO v_proj_status FROM projects p WHERE p.id = NEW.project_id FOR UPDATE;
        IF v_proj_status IS DISTINCT FROM 'open' THEN
            RAISE EXCEPTION 'A proposal can only be accepted while its project is open (project status: %)', v_proj_status
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_proposals_before_update BEFORE UPDATE ON proposals
    FOR EACH ROW EXECUTE FUNCTION fn_proposals_before_update();

-- 9.8 proposals: after acceptance -> project becomes in_progress, other pending proposals are rejected
CREATE OR REPLACE FUNCTION fn_proposals_after_accept() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE projects SET status = 'in_progress' WHERE id = NEW.project_id;
    UPDATE proposals SET status = 'rejected'
     WHERE project_id = NEW.project_id AND id <> NEW.id AND status = 'pending';
    RETURN NULL;
END;
$$;
CREATE TRIGGER trg_proposals_after_accept AFTER UPDATE OF status ON proposals
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM 'accepted' AND NEW.status = 'accepted')
    EXECUTE FUNCTION fn_proposals_after_accept();

COMMIT;
