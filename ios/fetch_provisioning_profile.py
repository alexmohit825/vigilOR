import sys, os, time, json, base64
import jwt
import requests

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

KEY_ID = os.environ.get("APP_STORE_CONNECT_KEY_ID", "38F6WA87DU")
ISSUER_ID = os.environ.get("APP_STORE_CONNECT_ISSUER_ID", "73c7355a-beef-4d79-919d-c3d7dec7747a")

def find_key_path():
    candidates = [
        os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"),
        r"C:\Users\mohal\Downloads\AuthKey_38F6WA87DU.p8",
        f"AuthKey_{KEY_ID}.p8"
    ]
    for p in candidates:
        if os.path.exists(p):
            return p
    raise FileNotFoundError(f"AuthKey p8 file not found in candidates: {candidates}")

def get_token():
    key_path = find_key_path()
    with open(key_path, "r") as f:
        key = f.read()
    now = int(time.time())
    payload = {
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1"
    }
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})

def main():
    token = get_token()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    b_res = requests.get("https://api.appstoreconnect.apple.com/v1/bundleIds?filter[identifier]=com.AlexMohit.VigilOR", headers=headers)
    b_data = b_res.json().get("data", [])
    if not b_data:
        print("Bundle ID com.AlexMohit.VigilOR not found.")
        sys.exit(1)
    bundle_res_id = b_data[0]["id"]
    print("Found Bundle Resource ID:", bundle_res_id)

    p_res = requests.get(f"https://api.appstoreconnect.apple.com/v1/profiles?filter[bundleId]={bundle_res_id}", headers=headers)
    p_data = p_res.json().get("data", [])
    
    profile_content = None
    if p_data:
        print(f"Found existing profile: {p_data[0]['attributes']['name']}")
        profile_content = p_data[0]["attributes"]["profileContent"]

    out_path = sys.argv[1] if len(sys.argv) > 1 else "embedded.mobileprovision"
    if profile_content:
        with open(out_path, "wb") as f:
            f.write(base64.b64decode(profile_content))
        print(f"Successfully written embedded.mobileprovision to {out_path} ({os.path.getsize(out_path)} bytes)")
    else:
        print("Warning: Could not fetch profileContent.")

if __name__ == "__main__":
    main()
