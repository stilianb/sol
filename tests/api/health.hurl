GET {{base_url}}/health

HTTP 200
[Asserts]
body == "ok"
