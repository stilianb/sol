# 1. GET /api/audit with valid url
GET {{base_url}}/api/audit?url=https%3A%2F%2Fexample.com

HTTP 200
[Asserts]
jsonpath "$.scores" exists
jsonpath "$.url" == "https://example.com"
jsonpath "$.scores.performance" isInteger
jsonpath "$.scores.accessibility" isInteger
jsonpath "$.scores.best_practices" isInteger
jsonpath "$.scores.seo" isInteger
jsonpath "$.scores.gdpr" isInteger

---

# 2. GET /api/audit — missing url param
GET {{base_url}}/api/audit

HTTP 400

---

# 3. GET /api/runs with url param — returns array (may be empty)
GET {{base_url}}/api/runs?url=https%3A%2F%2Fexample.com

HTTP 200
[Asserts]
jsonpath "$" isCollection
