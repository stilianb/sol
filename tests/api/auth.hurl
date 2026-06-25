# 1. Register new user
POST {{base_url}}/auth/register
Content-Type: application/json
{"email": "ci-auth@example.com", "password": "cipassword99"}

HTTP 200
[Captures]
access_token: jsonpath "$.access_token"
refresh_token: jsonpath "$.refresh_token"
[Asserts]
jsonpath "$.access_token" isString
jsonpath "$.refresh_token" isString

---

# 2. Register same email again
POST {{base_url}}/auth/register
Content-Type: application/json
{"email": "ci-auth@example.com", "password": "cipassword99"}

HTTP 400
[Asserts]
jsonpath "$.error" isString

---

# 3. Login with correct password
POST {{base_url}}/auth/login
Content-Type: application/json
{"email": "ci-auth@example.com", "password": "cipassword99"}

HTTP 200
[Captures]
access_token: jsonpath "$.access_token"
refresh_token: jsonpath "$.refresh_token"
[Asserts]
jsonpath "$.access_token" isString
jsonpath "$.refresh_token" isString

---

# 4. Login with wrong password
POST {{base_url}}/auth/login
Content-Type: application/json
{"email": "ci-auth@example.com", "password": "wrongpassword"}

HTTP 401

---

# 5. GET /user/me with valid token
GET {{base_url}}/user/me
Authorization: Bearer {{access_token}}

HTTP 200
[Asserts]
jsonpath "$.email" == "ci-auth@example.com"
jsonpath "$.id" isString

---

# 6. GET /user/me no token
GET {{base_url}}/user/me

HTTP 401

---

# 7. GET /user/me invalid token
GET {{base_url}}/user/me
Authorization: Bearer invalidtoken

HTTP 401

---

# 8. POST /auth/refresh with valid refresh_token
POST {{base_url}}/auth/refresh
Content-Type: application/json
{"refresh_token": "{{refresh_token}}"}

HTTP 200
[Captures]
access_token: jsonpath "$.access_token"
[Asserts]
jsonpath "$.access_token" isString

---

# 9. POST /auth/logout
POST {{base_url}}/auth/logout
Content-Type: application/json
{"refresh_token": "{{refresh_token}}"}

HTTP 200
[Asserts]
body == "{}"

---

# 10. POST /auth/refresh after logout (token revoked)
POST {{base_url}}/auth/refresh
Content-Type: application/json
{"refresh_token": "{{refresh_token}}"}

HTTP 401
