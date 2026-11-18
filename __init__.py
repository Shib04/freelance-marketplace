"""Authentication blueprint: login/logout/welcome, sign-up, password reset."""
from flask import Blueprint

bp = Blueprint("auth", __name__)

# The route modules register their pages on `bp` when imported.
from . import login, signup, reset  # noqa: E402,F401
