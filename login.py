"""Login page, logout and the temporary welcome page."""
from flask import flash, g, redirect, render_template, request, session, url_for

import db
from security import (DUMMY_HASH, login_required, validate_email, verify_password)

from . import bp

GENERIC_LOGIN_ERROR = "ایمیل یا رمز عبور نادرست است."  # never says which one is wrong


@bp.route("/login", methods=["GET", "POST"])
def login():
    if session.get("user_id"):
        return redirect(url_for("auth.welcome"))

    email = ""
    error = None
    status = 200

    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")

        if not email or not password:
            error, status = "ایمیل و رمز عبور را وارد کنید.", 400
        elif validate_email(email):
            error, status = "ایمیل واردشده معتبر نیست.", 400
        else:
            user = db.find_user_by_email(email)
            # Always verify (against a dummy hash if the user is unknown) -> same timing.
            password_ok = verify_password(user["password_hash"] if user else DUMMY_HASH, password)
            if user is None or not password_ok:
                error, status = GENERIC_LOGIN_ERROR, 401
            elif user["status"] != "active":
                # Only reached with the CORRECT password, so nothing is leaked.
                error, status = "این حساب کاربری فعال نیست. با پشتیبانی تماس بگیرید.", 403
            else:
                session.clear()              # new session on every login (prevents fixation)
                session["user_id"] = user["id"]
                session.permanent = True
                return redirect(url_for("auth.welcome"))

    return render_template("login.html", email=email, error=error), status


@bp.route("/welcome")
@login_required
def welcome():
    return render_template("welcome.html", user=g.user)


@bp.route("/logout", methods=["POST"])
def logout():
    session.clear()
    flash("از حساب کاربری خارج شدید.", "success")
    return redirect(url_for("auth.login"))
