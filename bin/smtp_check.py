#!/usr/bin/env python3
"""SMTP client checks, run inside a throw-away container that shares the
network namespace of the exim container under test (so it talks to
127.0.0.1:8025 and works the same on GitHub runners and in `act`).

Usage: python3 - SCENARIO < smtp_check.py
  trusted   - client IP is in RELAY_FROM_HOSTS: relay without login
  untrusted - client IP is not trusted: relay only after STARTTLS + login
  noauth    - TLS configured, no users file: AUTH must not be offered
  notls     - no certificate: neither STARTTLS nor AUTH must be offered
  insecure  - explicit opt-in permits AUTH without TLS

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
    code, msg = s.mail("sender@example.org")
    check(code == 250, "MAIL FROM is accepted", msg.decode(errors="replace"))
    code, msg = s.rcpt("someone@example.com")
    return code, "%d %s" % (code, msg.decode(errors="replace"))


def features(s, starttls=False):
    code, msg = s.ehlo("test.local")
    check(code == 250, "EHLO is accepted", msg.decode(errors="replace"))
    if starttls:
        s.starttls(context=tls_ctx())
        code, msg = s.ehlo("test.local")
        check(code == 250, "EHLO after STARTTLS is accepted", msg.decode(errors="replace"))
    return s.esmtp_features


def check_auth_disabled(s):
    check("auth" not in s.esmtp_features, "AUTH is not advertised")
    # A client can issue AUTH without seeing it in EHLO. Check the command is
    # refused too, before Exim starts asking for plaintext credentials.
    for mechanism in ("PLAIN", "LOGIN"):
        code, msg = s.docmd("AUTH", mechanism)
        check(code == 503, mechanism + " command is refused", msg.decode(errors="replace"))


def check_authentication(starttls):
    # Exercise each mechanism explicitly: SMTP.login() prefers PLAIN and
    # would leave a broken LOGIN implementation undetected.
    for mechanism in ("PLAIN", "LOGIN"):
        for user, password, expected in (
            (USER, PASS, 235),
            (USER, "wrong-password", 535),
            ("nosuchuser", PASS, 535),
            ("nosuchuser", "", 535),
        ):
            with connect() as s:
                f = features(s, starttls=starttls)
                check(mechanism in f.get("auth", "").split(), mechanism + " is advertised")
                s.user, s.password = user, password
                try:
                    code, msg = s.auth(mechanism, getattr(s, "auth_" + mechanism.lower()))
                except smtplib.SMTPAuthenticationError as e:
                    code, msg = e.smtp_code, e.smtp_error
                # smtplib also returns 503 as success ("already authenticated").
                # Require 235 to prove these credentials actually authenticated.
                check(code == expected, mechanism + " authentication returns " + str(expected),
                      "%d %s" % (code, msg.decode(errors="replace")))
                code, text = rcpt(s)
                if expected == 235:
                    check(code == 250, "authenticated client can relay", text)
                else:
                    check(code == 550, "failed authentication cannot enable relaying", text)


scenario = sys.argv[1]

if scenario == "trusted":
    with connect() as s:
        features(s)
        code, text = rcpt(s)
        check(code == 250, "trusted host can relay without login", text)

elif scenario == "untrusted":
    for starttls in (False, True):
        with connect() as s:
            f = features(s, starttls=starttls)
            if not starttls:
                check("starttls" in f, "STARTTLS is offered")
                check_auth_disabled(s)
            code, text = rcpt(s)
            check(code == 550, "untrusted host without login is refused", text)
    check_authentication(starttls=True)

elif scenario == "noauth":
    with connect() as s:
        features(s, starttls=True)
        check_auth_disabled(s)

elif scenario == "notls":
    with connect() as s:
        f = features(s)
        check("starttls" not in f, "STARTTLS is not offered without both certificate and key")
        check_auth_disabled(s)

elif scenario == "insecure":
    with connect() as s:
        f = features(s)
        check("starttls" not in f, "STARTTLS is not offered without a certificate")
        check("auth" in f, "explicit opt-in enables AUTH without TLS")
    check_authentication(starttls=False)

else:
    sys.exit("unknown scenario: " + scenario)
