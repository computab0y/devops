#!/usr/bin/env python3
import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def run_script():
    keycloak_url = "https://keycloak-keycloak.apps.okd.local"
    
    # 1. Get Access Token
    token_url = f"{keycloak_url}/realms/master/protocol/openid-connect/token"
    data = "client_id=admin-cli&username=temp-admin&password=c2da53c9e6b648d7bf1cf33830d0d2e5&grant_type=password".encode()
    req = urllib.request.Request(token_url, data=data)
    with urllib.request.urlopen(req, context=ctx) as f:
        token = json.loads(f.read().decode())["access_token"]
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    # 2. Get User Profile Configuration
    profile_url = f"{keycloak_url}/admin/realms/rgb-realm/users/profile"
    req = urllib.request.Request(profile_url, headers=headers)
    with urllib.request.urlopen(req, context=ctx) as f:
        profile = json.loads(f.read().decode())

    # Add custom attributes if not already present
    attr_names = [a["name"] for a in profile["attributes"]]
    if "OU" not in attr_names:
        profile["attributes"].append({
            "name": "OU",
            "displayName": "OU",
            "permissions": {"view": ["admin", "user"], "edit": ["admin", "user"]},
            "multivalued": False
        })
    if "password" not in attr_names:
        profile["attributes"].append({
            "name": "password",
            "displayName": "Password",
            "permissions": {"view": ["admin"], "edit": ["admin"]},
            "multivalued": False
        })

    # 3. Update User Profile Configuration
    req = urllib.request.Request(profile_url, data=json.dumps(profile).encode(), headers=headers, method="PUT")
    with urllib.request.urlopen(req, context=ctx) as f:
        print("Updated Keycloak User Profile configuration.")

    # 4. Update Users
    users_data = [
        {
            "id": "83f0ca18-1e2b-4054-a252-8dcf95ced69c",
            "username": "admin",
            "email": "admin@okd.local",
            "firstName": "Admin",
            "lastName": "User",
            "attributes": {"OU": ["FTP-Users"], "password": ["admin123"]}
        },
        {
            "id": "f04e2a14-bf4c-4b1b-a9fa-0183b1c9e2a8",
            "username": "developer",
            "email": "developer@okd.local",
            "firstName": "Dev",
            "lastName": "User",
            "attributes": {"OU": ["FTP-Users"], "password": ["developer123"]}
        },
        {
            "id": "2e8ed083-a319-47c3-aaf6-f495dac540a2",
            "username": "computab0y",
            "email": "computab0y@okd.local",
            "firstName": "Cluster",
            "lastName": "Admin",
            "attributes": {"OU": ["FTP-Users"], "password": ["qwerty"]}
        }
    ]

    for user in users_data:
        user_url = f"{keycloak_url}/admin/realms/rgb-realm/users/{user['id']}"
        req = urllib.request.Request(user_url, data=json.dumps(user).encode(), headers=headers, method="PUT")
        with urllib.request.urlopen(req, context=ctx) as f:
            print(f"Successfully updated user {user['username']} in Keycloak with OU and password attributes.")

if __name__ == "__main__":
    run_script()
