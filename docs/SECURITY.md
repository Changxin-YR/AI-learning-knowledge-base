# Security

Passwords use Argon2id. JWTs expire and all protected resources verify user ownership. Uploads reject path traversal, unsupported extensions and files over 10 MiB. Repository imports allow only HTTP(S) and reject loopback hosts. API keys are read only from server environment variables. Markdown is rendered as plain text in the mobile client, avoiding executable HTML.
