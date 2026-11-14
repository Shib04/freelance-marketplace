SET client_encoding = 'UTF8';
-- =====================================================================
-- Marketplace Freelance - useful queries  (run AFTER schema.sql + seed.sql)
-- Tip (pgAdmin): select ONE query at a time and press F5, because pgAdmin
-- only shows the result of the last statement in a script.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Q1. Open projects with their categories and employer
-- ---------------------------------------------------------------------
SELECT p.id,
       p.title,
       p.pricing_type,
       p.budget,
       u.first_name || ' ' || u.last_name              AS employer,
       string_agg(c.title, '، ' ORDER BY c.title)       AS categories,
       p.created_at
FROM projects p
JOIN users u                  ON u.id = p.employer_id
LEFT JOIN project_categories pc ON pc.project_id = p.id
LEFT JOIN categories c          ON c.id = pc.category_id
WHERE p.status = 'open'
GROUP BY p.id, u.id
ORDER BY p.created_at DESC, p.id;

-- ---------------------------------------------------------------------
-- Q2. Proposals of ONE project together with the freelancer name
--     (change the LIKE pattern to pick another project)
-- ---------------------------------------------------------------------
SELECT pr.id                                          AS proposal_id,
       f.first_name || ' ' || f.last_name             AS freelancer,
       pr.amount,
       pr.estimated_days,
       pr.estimated_hours,
       pr.status,
       pr.created_at
FROM proposals pr
JOIN projects p ON p.id = pr.project_id
JOIN users f    ON f.id = pr.freelancer_id
WHERE p.title LIKE '%فروشگاه%'
ORDER BY pr.amount;

-- ---------------------------------------------------------------------
-- Q3. Projects of every employer + number of proposals received
-- ---------------------------------------------------------------------
SELECT e.first_name || ' ' || e.last_name AS employer,
       p.title,
       p.status,
       count(pr.id)                       AS proposal_count
FROM users e
JOIN projects p       ON p.employer_id = e.id
LEFT JOIN proposals pr ON pr.project_id = p.id
GROUP BY e.id, p.id
ORDER BY employer, p.id;

-- ---------------------------------------------------------------------
-- Q4. Required skills of every project
-- ---------------------------------------------------------------------
SELECT p.title,
       string_agg(s.name, ', ' ORDER BY s.name) AS required_skills
FROM projects p
LEFT JOIN project_skills ps ON ps.project_id = p.id
LEFT JOIN skills s          ON s.id = ps.skill_id
GROUP BY p.id
ORDER BY p.id;

-- ---------------------------------------------------------------------
-- Q5. (extra) Everything a given user sent as FREELANCER, with project owner
-- ---------------------------------------------------------------------
SELECT f.email,
       p.title                              AS project,
       o.first_name || ' ' || o.last_name    AS employer,
       pr.amount,
       pr.status
FROM proposals pr
JOIN users f    ON f.id = pr.freelancer_id
JOIN projects p ON p.id = pr.project_id
JOIN users o    ON o.id = p.employer_id
WHERE f.email = 'ali.ahmadi@example.com';

-- ---------------------------------------------------------------------
-- Q6. (extra) Users who act in BOTH roles (employer and freelancer)
-- ---------------------------------------------------------------------
SELECT u.id, u.first_name || ' ' || u.last_name AS full_name
FROM users u
WHERE EXISTS (SELECT 1 FROM projects  p  WHERE p.employer_id  = u.id)
  AND EXISTS (SELECT 1 FROM proposals pr WHERE pr.freelancer_id = u.id);

-- ---------------------------------------------------------------------
-- Q7. (extra) Admin accounts with grant time
-- ---------------------------------------------------------------------
SELECT u.email, a.granted_at, g.email AS granted_by
FROM admins a
JOIN users u      ON u.id = a.user_id
LEFT JOIN users g ON g.id = a.granted_by;

-- ---------------------------------------------------------------------
-- Q8. (extra) Freelancers matching the skills a project needs
--     (profile skills ∩ project skills), best match first
-- ---------------------------------------------------------------------
SELECT p.title,
       u.first_name || ' ' || u.last_name AS freelancer,
       count(*)                           AS matching_skills
FROM projects p
JOIN project_skills ps  ON ps.project_id = p.id
JOIN profile_skills pks ON pks.skill_id  = ps.skill_id
JOIN profiles_user prf  ON prf.id = pks.profile_id
JOIN users u            ON u.id = prf.user_id
WHERE p.status = 'open' AND u.id <> p.employer_id
GROUP BY p.id, u.id
ORDER BY p.id, matching_skills DESC;
