"""Forgot-password request, reset form and the development mailbox."""
import os
import secrets

from flask import abort, flash, redirect, render_template, request, session, url_for

import db
import mailer
from security import (hash_password, hash_token, validate_email, validate_password)

from . import bp

# Same answer whether the e-mail exists or not -> nobody can probe for accounts.
FORGOT_NEUTRAL_MESSAGE = ("اگر این ایمیل در سامانه ثبت شده باشد، لینک بازیابی رمز عبور برای آن ارسال می‌شود.")


def _minutes():
    try:
        return max(1, int(os.getenv("RESET_LINK_MINUTES", "30")))
    except ValueError:
        return 30


@bp.route("/forgot-password", methods=["GET", "POST"])
def forgot():
    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        error = validate_email(email)
        if error:
            return render_template("forgot.html", email=email, error=error), 400

        user = db.find_user_by_email(email)
        if user is not None and user["status"] == "active":
            token = secrets.token_urlsafe(32)  # 256 bits of randomness
            db.create_reset_token(user["id"], hash_token(token), _minutes())
            link = url_for("auth.reset", token=token, _external=True)
            mailer.send_reset_email(user["email"], link, _minutes())

        flash(FORGOT_NEUTRAL_MESSAGE, "info")
        return redirect(url_for("auth.forgot"))

    return render_template("forgot.html", email="", error=None)


@bp.route("/reset-password/<token>", methods=["GET", "POST"])
def reset(token):
    token_hash = hash_token(token)
    if db.find_valid_reset_token(token_hash) is None:
        return render_template("reset_invalid.html"), 400

    errors = {}
    if request.method == "POST":
        password = request.form.get("password", "")
        password2 = request.form.get("password2", "")
        errors["password"] = validate_password(password)
        if not errors["password"] and password != password2:
            errors["password2"] = "رمز عبور و تکرار آن یکسان نیستند."
        elif not password2:
            errors["password2"] = "تکرار رمز عبور را وارد کنید."
        errors = {k: v for k, v in errors.items() if v}

        if errors:
            return render_template("reset.html", errors=errors), 400

        if not db.reset_password(token_hash, hash_password(password)):
            return render_template("reset_invalid.html"), 400

        session.clear()
        flash("رمز عبور جدید ذخیره شد. اکنون با رمز جدید وارد شوید.", "success")
        return redirect(url_for("auth.login"))

    return render_template("reset.html", errors=errors)


@bp.route("/dev/mailbox")
def dev_mailbox():
    """Fake inbox for development only (404 when DEV_MODE is not 1)."""
    if not mailer.is_dev_mode():
        abort(404)
    return render_template("dev_mailbox.html", mails=mailer.DEV_MAILBOX)
