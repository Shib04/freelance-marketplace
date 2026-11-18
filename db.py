"""Database access layer (PostgreSQL via psycopg 3).

Every function opens its own short connection, runs parameterised SQL
(never string-formatted SQL -> no SQL injection) and commits on success.
"""
import os

import psycopg
import psycopg.errors
from psycopg.rows import dict_row


class EmailAlreadyExists(Exception):
    """Raised when the e-mail is already registered."""


def _connect():
    return psycopg.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "5432")),
        dbname=os.getenv("DB_NAME", "lab_freelance"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD", ""),
        row_factory=dict_row,
        connect_timeout=5,
    )


def check_connection():
    """Used at start-up. Returns (ok, message)."""
    try:
        with _connect() as conn:
            conn.execute("SELECT 1")
            row = conn.execute(
                "SELECT to_regclass('public.password_reset_tokens') AS t, "
                "       to_regclass('public.users') AS u"
            ).fetchone()
            if row["u"] is None or row["t"] is None:
                return False, ("Connected, but the tables are missing. Run database/schema.sql "
                               "(the NEW version that contains password_reset_tokens) first.")
        return True, "Database connection OK."
    except Exception as exc:  # noqa: BLE001 - we only print a hint
        return False, f"Cannot connect to PostgreSQL: {exc}"


# --------------------------------------------------------------------- users
_USER_COLUMNS = """
    u.id, u.first_name, u.last_name, u.email, u.password_hash, u.status,
    EXISTS (SELECT 1 FROM admins a WHERE a.user_id = u.id) AS is_admin
"""


def find_user_by_email(email):
    with _connect() as conn:
        return conn.execute(
            f"SELECT {_USER_COLUMNS} FROM users u WHERE lower(u.email) = lower(%s)",
            (email,),
        ).fetchone()


def get_user_by_id(user_id):
    with _connect() as conn:
        return conn.execute(
            f"SELECT {_USER_COLUMNS} FROM users u WHERE u.id = %s",
            (user_id,),
        ).fetchone()


def create_user(first_name, last_name, email, password_hash):
    """Insert a new active user and return its id.
    The UNIQUE index on lower(email) is the final guard against duplicates
    (it also protects against two people registering at the same moment)."""
    try:
        with _connect() as conn:
            row = conn.execute(
                "INSERT INTO users (first_name, last_name, email, password_hash) "
                "VALUES (%s, %s, %s, %s) RETURNING id",
                (first_name, last_name, email, password_hash),
            ).fetchone()
            return row["id"]
    except psycopg.errors.UniqueViolation:
        raise EmailAlreadyExists() from None


# ------------------------------------------------------- password reset tokens
def create_reset_token(user_id, token_hash, minutes):
    """Invalidate older unused links of this user, then store the new one."""
    with _connect() as conn:
        conn.execute(
            "UPDATE password_reset_tokens SET used_at = now() "
            "WHERE user_id = %s AND used_at IS NULL",
            (user_id,),
        )
        conn.execute(
            "INSERT INTO password_reset_tokens (user_id, token_hash, expires_at) "
            "VALUES (%s, %s, now() + make_interval(mins => %s::int))",
            (user_id, token_hash, minutes),
        )


def find_valid_reset_token(token_hash):
    """Return the token row if it exists, is unused, not expired, and its user is active."""
    with _connect() as conn:
        return conn.execute(
            "SELECT t.id, t.user_id "
            "FROM password_reset_tokens t JOIN users u ON u.id = t.user_id "
            "WHERE t.token_hash = %s AND t.used_at IS NULL "
            "  AND t.expires_at > now() AND u.status = 'active'",
            (token_hash,),
        ).fetchone()


def reset_password(token_hash, new_password_hash):
    """Atomically: consume the token (single use) + set the new password.
    Returns True on success, False if the token is invalid/used/expired."""
    with _connect() as conn:
        row = conn.execute(
            "UPDATE password_reset_tokens SET used_at = now() "
            "WHERE token_hash = %s AND used_at IS NULL AND expires_at > now() "
            "RETURNING user_id",
            (token_hash,),
        ).fetchone()
        if row is None:
            return False
        cur = conn.execute(
            "UPDATE users SET password_hash = %s WHERE id = %s AND status = 'active'",
            (new_password_hash, row["user_id"]),
        )
        if cur.rowcount != 1:
            conn.rollback()
            return False
        conn.execute(
            "UPDATE password_reset_tokens SET used_at = now() "
            "WHERE user_id = %s AND used_at IS NULL",
            (row["user_id"],),
        )
        return True
