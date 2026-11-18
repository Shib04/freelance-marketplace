"""Marketplace Freelance - authentication phase (login, sign-up, password reset).

Run:  py app.py     then open  http://127.0.0.1:5000
"""
import os
from datetime import timedelta

from dotenv import load_dotenv
from flask import Flask, redirect, render_template, request, session, url_for

load_dotenv()  # reads the secret values from the ".env" file (never committed to Git)

import db  # noqa: E402
import mailer  # noqa: E402
import security  # noqa: E402
from auth import bp as auth_bp  # noqa: E402


def create_app():
    app = Flask(__name__)

    secret = os.getenv("SECRET_KEY", "")
    if len(secret) < 16 or secret.startswith("change-me"):
        raise RuntimeError("SECRET_KEY is missing or still the example value. "
                           "Copy .env.example to .env and set a long random SECRET_KEY.")

    app.config.update(
        SECRET_KEY=secret,
        SESSION_COOKIE_HTTPONLY=True,       # JavaScript cannot read the cookie
        SESSION_COOKIE_SAMESITE="Lax",      # not sent on cross-site POSTs
        SESSION_COOKIE_SECURE=os.getenv("COOKIE_SECURE", "0") == "1",  # set 1 behind HTTPS
        PERMANENT_SESSION_LIFETIME=timedelta(hours=8),
        MAX_CONTENT_LENGTH=64 * 1024,       # forms are tiny; reject huge bodies
    )

    app.jinja_env.globals["csrf_token"] = security.csrf_token

    @app.before_request
    def protect_forms():
        if request.method == "POST":
            security.verify_csrf()

    @app.after_request
    def add_headers(resp):
        resp.headers["Cache-Control"] = "no-store"          # back button cannot reveal pages after logout
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["X-Frame-Options"] = "DENY"
        resp.headers["Referrer-Policy"] = "no-referrer"     # reset token never leaks in Referer
        return resp

    @app.route("/")
    def index():
        return redirect(url_for("auth.welcome" if session.get("user_id") else "auth.login"))

    @app.errorhandler(400)
    def bad_request(_e):
        return render_template("error.html", title="درخواست نامعتبر",
                               message="فرم منقضی شده یا نامعتبر است. صفحه را دوباره باز کنید و تلاش کنید."), 400

    @app.errorhandler(404)
    def not_found(_e):
        return render_template("error.html", title="صفحه پیدا نشد",
                               message="آدرس واردشده وجود ندارد."), 404

    @app.errorhandler(405)
    def not_allowed(_e):
        return redirect(url_for("index"))

    @app.errorhandler(500)
    def server_error(_e):
        return render_template("error.html", title="خطای سرور",
                               message="مشکلی پیش آمد. چند لحظه بعد دوباره تلاش کنید."), 500

    app.register_blueprint(auth_bp)
    return app


app = create_app()

if __name__ == "__main__":
    ok, message = db.check_connection()
    print(message)
    if not ok:
        raise SystemExit(1)
    app.run(host="127.0.0.1", port=5000, debug=mailer.is_dev_mode())
