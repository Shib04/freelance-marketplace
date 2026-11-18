"""Sign-up page."""
from flask import flash, redirect, render_template, request, session, url_for

import db
from security import (hash_password, validate_email, validate_name, validate_password)

from . import bp


@bp.route("/signup", methods=["GET", "POST"])
def signup():
    if session.get("user_id"):
        return redirect(url_for("auth.welcome"))

    values = {"first_name": "", "last_name": "", "email": ""}
    errors = {}
    status = 200

    if request.method == "POST":
        values["first_name"] = " ".join(request.form.get("first_name", "").split())
        values["last_name"] = " ".join(request.form.get("last_name", "").split())
        values["email"] = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")
        password2 = request.form.get("password2", "")

        errors["first_name"] = validate_name(values["first_name"], "نام")
        errors["last_name"] = validate_name(values["last_name"], "نام خانوادگی")
        errors["email"] = validate_email(values["email"])
        errors["password"] = validate_password(password)
        if not errors["password"] and password != password2:
            errors["password2"] = "رمز عبور و تکرار آن یکسان نیستند."
        elif not password2:
            errors["password2"] = "تکرار رمز عبور را وارد کنید."
        errors = {k: v for k, v in errors.items() if v}

        if not errors:
            try:
                db.create_user(values["first_name"], values["last_name"],
                               values["email"], hash_password(password))
            except db.EmailAlreadyExists:
                errors["email"] = "این ایمیل قبلاً ثبت شده است. وارد شوید یا رمز را بازیابی کنید."
                status = 409
            else:
                flash("حساب شما با موفقیت ساخته شد. اکنون می‌توانید وارد شوید.", "success")
                return redirect(url_for("auth.login"))
        else:
            status = 400

    return render_template("signup.html", values=values, errors=errors), status
