"""Password hashing, input validation, CSRF protection and the login guard."""
import hashlib
import re
import secrets
from functools import wraps

from flask import abort, flash, g, redirect, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

import db

# --------------------------------------------------------------------------
# Password hashing: PBKDF2-HMAC-SHA256 with a random salt and 600 000 rounds
# (OWASP recommendation). It is a slow, dedicated password-hashing algorithm.
# Plain text, MD5 and a bare SHA-256 are NEVER used for passwords.
# The hashing happens here in the backend only.
# --------------------------------------------------------------------------
HASH_METHOD = "pbkdf2:sha256:600000"

# A throw-away hash: when the e-mail does not exist we still verify against it,
# so a wrong e-mail and a wrong password take the same time (no user enumeration).
DUMMY_HASH = generate_password_hash("not-a-real-password-1", method=HASH_METHOD)


def hash_password(password):
    return generate_password_hash(password, method=HASH_METHOD)


def verify_password(stored_hash, password):
    try:
        return check_password_hash(stored_hash, password)
    except ValueError:  # hash in an unknown/unsupported format -> treat as wrong
        return False


def hash_token(token):
    """Fingerprint of a reset token. The token is 256 bits of randomness (not a
    human password), so a plain SHA-256 fingerprint is the correct tool here."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


# ------------------------------------------------------------------ validation
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def validate_email(email):
    if not email:
        return "ایمیل را وارد کنید."
    if len(email) > 254 or not EMAIL_RE.match(email):
        return "ایمیل واردشده معتبر نیست."
    return None


def validate_password(password):
    if not password:
        return "رمز عبور را وارد کنید."
    if len(password) < 8:
        return "رمز عبور باید حداقل ۸ کاراکتر باشد."
    if len(password) > 128:
        return "رمز عبور نباید بیشتر از ۱۲۸ کاراکتر باشد."
    if not re.search(r"[A-Za-z\u0600-\u06FF]", password) or not re.search(r"\d", password):
        return "رمز عبور باید هم حرف و هم عدد داشته باشد."
    return None


def validate_name(value, label):
    if not value:
        return f"{label} را وارد کنید."
    if len(value) > 100:
        return f"{label} نباید بیشتر از ۱۰۰ کاراکتر باشد."
    return None


# ------------------------------------------------------------------------ CSRF
def csrf_token():
    if "csrf" not in session:
        session["csrf"] = secrets.token_hex(16)
    return session["csrf"]


def verify_csrf():
    """Every POST must carry the secret token that was placed in the form."""
    sent = request.form.get("csrf_token", "")
    real = session.get("csrf", "")
    if not real or not secrets.compare_digest(sent.encode("utf-8"), real.encode("utf-8")):
        abort(400)


# ------------------------------------------------------------------ login guard
def login_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        user_id = session.get("user_id")
        if not user_id:
            flash("برای دیدن این صفحه باید وارد شوید.", "error")
            return redirect(url_for("auth.login"))
        user = db.get_user_by_id(user_id)
        if user is None or user["status"] != "active":
            session.clear()
            flash("حساب شما در دسترس نیست. دوباره وارد شوید.", "error")
            return redirect(url_for("auth.login"))
        g.user = user
        return view(*args, **kwargs)

    return wrapper
