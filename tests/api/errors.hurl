# 1. POST /auth/register with missing password field
POST {{base_url}}/auth/register
Content-Type: application/json
{"email": "ci-errors@example.com"}

HTTP 400
[Asserts]
jsonpath "$.error" isString

---

# 2. POST /auth/register with empty body
POST {{base_url}}/auth/register
Content-Type: application/json
{}

HTTP 400
[Asserts]
jsonpath "$.error" isString

---

# 3. POST /auth/login missing fields
POST {{base_url}}/auth/login
Content-Type: application/json
{"email": "ci-errors@example.com"}

HTTP 400
[Asserts]
jsonpath "$.error" isString

---

# 4. GET /projects with expired/malformed JWT
GET {{base_url}}/projects
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJub3RhcmVhbHVzZXJAZXhhbXBsZS5jb20iLCJleHAiOjE2MDAwMDAwMDB9.invalidsignature

HTTP 401
