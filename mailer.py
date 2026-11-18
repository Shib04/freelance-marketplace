"""Development "mail" service.

A real e-mail server is NOT required for this assignment. In development mode
the reset link is (1) printed in the terminal and (2) shown in a fake mailbox
page at /dev/mailbox. Replace send_reset_email() with real SMTP code later.
"""
import os
from datetime import datetime

DEV_MAILBOX = []  # newest first; lives in memory only


def is_dev_mode():
    return os.getenv("DEV_MODE", "0") == "1"


def send_reset_email(to_email, link, minutes):
    if not is_dev_mode():
        # No e-mail provider configured -> nothing is sent (and nothing is leaked).
        print("WARNING: password reset requested but no e-mail service is configured.")
        return
    print(f"[DEV MAIL] to={to_email}  reset link: {link}")
    DEV_MAILBOX.insert(0, {
        "to": to_email,
        "subject": "بازیابی رمز عبور",
        "link": link,
        "minutes": minutes,
        "time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    })
    del DEV_MAILBOX[50:]  # keep it small
