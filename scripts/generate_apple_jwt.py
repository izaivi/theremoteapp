#!/usr/bin/env python3
"""
Generate the JWT client_secret that Supabase needs for Sign in with Apple.

Usage:
  pip3 install pyjwt cryptography
  python3 generate_apple_jwt.py /path/to/AuthKey_JDP6NB6N3Z.p8

Apple allows secrets up to 6 months. Re-run before expiry.
"""
import sys, time, jwt

TEAM_ID    = "T48AT39AXA"
CLIENT_ID  = "com.punkytigerlabs.theremote.signin"  # Services ID
KEY_ID     = "JDP6NB6N3Z"

if len(sys.argv) != 2:
    print("usage: python3 generate_apple_jwt.py /path/to/AuthKey_XXXX.p8")
    sys.exit(1)

with open(sys.argv[1], "r") as f:
    private_key = f.read()

now = int(time.time())
payload = {
    "iss": TEAM_ID,
    "iat": now,
    "exp": now + 60 * 60 * 24 * 180,  # 180 days
    "aud": "https://appleid.apple.com",
    "sub": CLIENT_ID,
}
headers = {"kid": KEY_ID, "alg": "ES256"}

token = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
print(token)
