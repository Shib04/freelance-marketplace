# Freelance Marketplace

A freelance marketplace platform (similar to Upwork, Ponisha, and Karlancer) where clients post projects, freelancers submit proposals, and clients can accept at most one proposal per project.

This repository covers **Phase 1**, including requirements analysis, database design, and implementation.

## Project Information

| Item | Description |
|---|---|
| DBMS | PostgreSQL 17 (pgAdmin 4) |
| Team | Shib04 |
| Jira | [[Board Link]](https://highshib.atlassian.net/jira/software/projects/FM/boards/3?filter=&groupBy=none) |
| User Roles | Regular User (acting as both Client and Freelancer) and Admin |

## Repository Structure

```text
├── README.md
├── .gitignore
├── database/
│   ├── schema.sql     # Tables, constraints, indexes, and triggers
│   ├── seed.sql       # Sample data
│   ├── queries.sql    # Application queries
│   └── tests.sql      # Automated constraint and business rule tests
└── docs/
    ├── erd.png        # ERD diagram
    ├── requirements.md
    ├── jira-backlog.md
    └── setup-guide.md
```

## Setup and Installation

### Requirements

- PostgreSQL 17
- pgAdmin 4 (optional, for graphical database management)

### Database Setup

Create the database:

```bash
psql -U postgres -c "CREATE DATABASE freelance_lab ENCODING 'UTF8';"
```

Run the SQL files in the following order:

```bash
psql -U postgres -d freelance_lab -v ON_ERROR_STOP=1 -f database/schema.sql
psql -U postgres -d freelance_lab -v ON_ERROR_STOP=1 -f database/seed.sql
psql -U postgres -d freelance_lab -f database/queries.sql
psql -U postgres -d freelance_lab -f database/tests.sql
```

**Note:** `schema.sql` is designed to be re-runnable. It drops existing tables before recreating them, so it should only be used in a development environment.

For instructions on running the SQL files through pgAdmin 4, see [docs/setup-guide.md](docs/setup-guide.md).

## Database Design

### Entity Relationship Diagram

![Entity Relationship Diagram](docs/erd.png)

### Database Tables

The database consists of 12 tables:

| Table | Description |
|---|---|
| `users` | Stores all user accounts, including regular users and administrators. |
| `admins` | Stores administrator accounts and the timestamp of their promotion. |
| `profiles_user` | Stores user profile information. Each user can have at most one profile. |
| `skills` | Stores available skills. |
| `categories` | Stores project categories. |
| `profile_skills` | Junction table representing the many-to-many relationship between profiles and skills. |
| `portfolio_items` | Stores portfolio items associated with user profiles. |
| `certificates` | Stores certificates associated with user profiles. |
| `projects` | Stores projects posted by clients. |
| `project_categories` | Junction table connecting projects and categories. |
| `project_skills` | Junction table connecting projects and required skills. |
| `proposals` | Stores freelancer proposals submitted for projects. |

### Key Design Decisions

#### 1. Administrator Management

Administrators are stored in a separate `admins` table rather than being identified by a `role` column in the `users` table.

- The table stores `granted_at` and `granted_by` information.
- Multiple administrators are supported.
- The `is_admin(user_id)` function determines whether a user is an administrator.
- Triggers prevent administrators from creating projects, submitting proposals, or creating profiles.
- Users who already have projects, proposals, or profiles cannot be promoted to administrators.

#### 2. Client and Freelancer Roles

Clients and freelancers are not stored in separate tables.

A regular user can act as both:

- A client when posting a project (`projects.employer_id`).
- A freelancer when submitting a proposal (`proposals.freelancer_id`).

#### 3. Many-to-Many Relationships

Junction tables with composite primary keys are used for many-to-many relationships:

- `profile_skills`
- `project_categories`
- `project_skills`

Skills are stored in a separate table rather than being saved as plain text in user profiles.

#### 4. Case-Insensitive Uniqueness

Case-insensitive unique indexes are used for:

- User email addresses (`lower(email)`).
- Skill names (`lower(name)`).
- Category titles (`lower(title)`).

Mobile numbers are optional but must be unique when provided.

#### 5. Password Security

Only `password_hash` is stored in the database.

A CHECK constraint requires the hash to contain at least 60 characters, matching the standard bcrypt hash length. Actual password hashing is handled by the application.

#### 6. Project and Proposal Pricing

Fixed-price and hourly projects use a single `budget` column in `projects`, while proposals use a single `amount` column in `proposals`.

The `pricing_type` determines how these values are interpreted.

- `estimated_hours` is only applicable to hourly projects and is enforced through a trigger.
- Changing a project's pricing type after proposals have been submitted is not allowed.

#### 7. Accepted Proposals

The accepted proposal is derived from `proposals.status = 'accepted'`.

A separate `accepted_proposal_id` column is not stored in the `projects` table to avoid redundant data.

A partial unique index on accepted proposals ensures that at most one proposal can be accepted for each project. A trigger also enforces this business rule.

#### 8. Deletion Rules

Foreign keys referencing users, projects, skills, and categories generally use `RESTRICT` to prevent deleting records that have dependent data.

Users and projects are deactivated rather than permanently deleted.

`CASCADE` is used only for dependent profile details and project junction records.

The `admins.granted_by` foreign key uses `SET NULL`.

#### 9. Status Management

Statuses are stored as text values with CHECK constraints rather than using PostgreSQL ENUM types.

#### 10. Currency and Numeric Precision

The platform uses Toman as its currency.

Monetary values use `NUMERIC(14,2)` instead of floating-point types to avoid precision problems.

#### 11. Timestamps

`TIMESTAMPTZ` is used for timestamp columns.

The `updated_at` field is automatically maintained using the `set_updated_at` trigger function.

#### 12. Indexing

Indexes are created on frequently queried foreign keys and commonly filtered or sorted columns.

For example:

- Foreign key columns.
- `projects(status, created_at DESC)`.

## Business Rules and State Transitions

### Project Lifecycle

```text
draft ──► open ──► in_progress ──► completed
  │         │            │
  └─────────┴────────────┴──► cancelled
```

- A project can move from `open` to `in_progress` only when a proposal is accepted. This transition happens automatically upon acceptance.
- `completed` and `cancelled` are final states.
- A new project can be created in either `draft` or `open` status.
- Cancelling a project automatically rejects all its pending proposals.

### Proposal Lifecycle

```text
pending ──► accepted
    │
    ├──────► rejected
    │
    └──────► withdrawn
```

All three resulting states are final.

**Proposal submission rules:**

- Proposals can only be submitted for projects with `open` status.
- A proposal must initially have `pending` status.
- Users cannot submit proposals for their own projects.
- Administrators cannot submit proposals.
- Only active users can submit proposals.

**Proposal acceptance rules:**

- A proposal can only be accepted while its project is `open`.
- Once a proposal is accepted, the project automatically moves to `in_progress`.
- All other pending proposals for that project are automatically rejected.

This behavior follows the design decision based on Question 2 in `requirements.md`.

**Proposal editing and withdrawal:**

- Only pending proposals can be edited.
- A freelancer can withdraw a pending proposal.
- `withdrawn` means the freelancer withdrew the proposal before acceptance.
- `rejected` means the client rejected it, or it was rejected because the project was cancelled or another proposal was accepted.

## Database Testing

The `database/tests.sql` file contains **36 automated tests** covering database constraints and business rules.

Each test runs inside a separate subtransaction and is rolled back afterward, ensuring that the sample data remains unchanged.

### Expected SQLSTATE Codes

| SQLSTATE | Meaning |
|---|---|
| `23505` | Unique constraint violation |
| `23503` | Foreign key violation |
| `23514` | CHECK constraint or business rule violation |
| `00000` | Successful execution |

### Test Coverage

| Test Numbers | Description | Expected Result |
|---|---|---|
| 1–2 | Duplicate email addresses, including case variations | `23505` |
| 3–4 | Invalid foreign key references | `23503` |
| 5 | Duplicate proposal by the same freelancer for the same project | `23505` |
| 6–8 | Zero or negative project budgets and hourly rates | `23514` |
| 9–10 | Zero proposal amount or estimated time | `23514` |
| 11 | Multiple accepted proposals for one project | `23514` |
| 12 | Multiple accepted proposals with the trigger disabled | `23505` |
| 13 | Submitting a proposal for one's own project | `23514` |
| 14 | Submitting a proposal for a non-open project | `23514` |
| 15–18 | Administrator restrictions, including promoting users with existing data | `23514` |
| 19–21 | Plaintext passwords, invalid email addresses, and invalid statuses | `23514` |
| 22–27 | Invalid status transitions, changing pricing type, and editing accepted proposals | `23514` |
| 28–29 | Deleting users or projects with existing history | `23503` |
| 30–32 | Duplicate profiles, skills, or categories | `23505` |
| 33–36 | Valid proposal submission, acceptance, withdrawal, and project cancellation | `00000` |

## Limitations and Future Improvements

Some features are intentionally left for future application-layer implementation.

### Current Limitations

- Requiring at least one category and one skill for an open project is enforced at the application layer.
- Password hashing, email and OTP validation, session management, and authorization are handled by the backend application.

### Future Improvements

Potential future features include:

- Direct messaging between clients and freelancers.
- Reviews and ratings.
- Payment processing and milestone management.
- Notifications.
- Support for multiple currencies through a dedicated currency column.
- Status history tracking.
- Full-text search using PostgreSQL GIN indexes and `tsvector`.

---

**Project Status:** Phase 1 – Requirements Analysis and Database Design and Implementation.
