#!/usr/bin/env python3
"""SMTP client checks, run inside a throw-away container that shares the
network namespace of the exim container under test (so it talks to
127.0.0.1:8025 and works the same on GitHub runners and in `act`).

Usage: python3 - SCENARIO < smtp_check.py
  trusted   - client IP is in RELAY_FROM_HOSTS: relay without login
  untrusted - client IP is not trusted: relay only after STARTTLS + login
  noauth    - TLS configured, no users file: AUTH must not be offered
  notls     - no certificate: neither STARTTLS nor AUTH must be offered

No message is ever sent (we stop after RCPT), so nothing leaves the container.
"""
import os
import smtplib
import ssl
import sys
import time

USER = os.environ.get("TEST_USER", "smtpuser")
PASS = os.environ.get("TEST_PASS", "S3cret")


def connect():
    for _ in range(30):
        try:
            return smtplib.SMTP("127.0.0.1", 8025, timeout=10)
        except OSError:
            time.sleep(1)
    sys.exit("FAIL: exim did not start accepting connections")


def tls_ctx():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def check(cond, msg, detail=""):
    if not cond:
        sys.exit("FAIL: " + msg + (" (server said: " + detail + ")" if detail else ""))
    print("ok:", msg)


def rcpt(s):
    """MAIL + RCPT only; returns (code, text). No message is ever sent."""
    s.mail("sender@example.org")
    code, msg = s.rcpt("someone@example.com")
    return code, "%d %s" % (code, msg.decode(errors="replace"))


def features(s, starttls=False):
    s.ehlo("test.local")
    if starttls:
        s.starttls(context=tls_ctx())
        s.ehlo("test.local")
    return s.esmtp_features


scenario = sys.argv[1]

if scenario == "trusted":
    s = connect()
    features(s)
    code, text = rcpt(s)
    check(code == 250, "trusted host can relay without login", text)

elif scenario == "untrusted":
    s = connect()
    f = features(s)
    check("starttls" in f, "STARTTLS is offered")
    check("auth" not in f, "AUTH is not offered before STARTTLS")
    code, text = rcpt(s)
    check(code >= 500, "untrusted host without login is refused", text)
    s.close()

    s = connect()
    f = features(s, starttls=True)
    check("auth" in f, "AUTH is offered after STARTTLS")
    try:
        s.login(USER, "wrong-password")
        sys.exit("FAIL: wrong password was accepted")
    except smtplib.SMTPAuthenticationError as e:
        check(e.smtp_code == 535, "wrong password is rejected (535)")
    s.close()

    s = connect()
    features(s, starttls=True)
    s.login(USER, PASS)
    check(True, "login with correct password works")
    code, text = rcpt(s)
    check(code == 250, "authenticated client can relay", text)
    s.close()

    s = connect()
    features(s, starttls=True)
    try:
        s.login("nosuchuser", PASS)
        sys.exit("FAIL: unknown user was accepted")
    except smtplib.SMTPAuthenticationError:
        check(True, "unknown user is rejected")

elif scenario == "noauth":
    s = connect()
    f = features(s, starttls=True)
    check("auth" not in f, "AUTH is not offered without a users file")

elif scenario == "notls":
    s = connect()
    f = features(s)
    check("starttls" not in f, "STARTTLS is not offered without a certificate")
    check("auth" not in f, "AUTH is not offered without TLS")

else:
    sys.exit("unknown scenario: " + scenario)
