# 1. Register fresh user for project tests
POST {{base_url}}/auth/register
Content-Type: application/json
{"email": "ci-projects@example.com", "password": "cipassword99"}

HTTP 200
[Captures]
access_token: jsonpath "$.access_token"
[Asserts]
jsonpath "$.access_token" isString


# 2. POST /projects — create project
POST {{base_url}}/projects
Authorization: Bearer {{access_token}}
Content-Type: application/json
{"name": "CI Test Project", "primary_url": "https://example.com"}

HTTP *
[Captures]
project_id: jsonpath "$.id"
[Asserts]
status >= 200
status <= 201
jsonpath "$.id" isString
jsonpath "$.name" == "CI Test Project"
jsonpath "$.primary_url" == "https://example.com"


# 3. GET /projects — list contains the project
GET {{base_url}}/projects
Authorization: Bearer {{access_token}}

HTTP 200
[Asserts]
jsonpath "$" isCollection
jsonpath "$[0].id" isString


# 4. GET /projects/:id
GET {{base_url}}/projects/{{project_id}}
Authorization: Bearer {{access_token}}

HTTP 200
[Asserts]
jsonpath "$.id" == "{{project_id}}"
jsonpath "$.name" == "CI Test Project"
jsonpath "$.primary_url" == "https://example.com"


# 5. GET /projects without auth
GET {{base_url}}/projects

HTTP 401


# 6. DELETE /projects/:id
DELETE {{base_url}}/projects/{{project_id}}
Authorization: Bearer {{access_token}}

HTTP *
[Asserts]
status >= 200
status <= 204


# 7. GET /projects/:id after delete — archived project returns 404
GET {{base_url}}/projects/{{project_id}}
Authorization: Bearer {{access_token}}

HTTP 404
