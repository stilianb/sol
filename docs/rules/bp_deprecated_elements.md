# bp_deprecated_elements

**Category**: best_practices
**Severity**: warning
**Profiles**: all

## What we check

Counts occurrences of deprecated HTML elements: `<font>`, `<center>`, `<marquee>`.

## Why it matters

Deprecated elements are not guaranteed to be supported in future browsers and indicate outdated markup practices. They often signal larger maintenance problems in the codebase.

## How the score is affected

| Finding                       | Penalty   |
|-------------------------------|-----------|
| 0 deprecated elements         | 0         |
| 1–2 deprecated elements       | −5 points |
| 3+ deprecated elements        | −15 points|

## How to fix

Replace `<font>` and `<center>` with CSS (`font-family`, `text-align: center`). Remove `<marquee>` and implement any required animation in CSS or JavaScript.
