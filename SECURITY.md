# Security

SCCP-Mobile is a public repository in **development / testing**.

Do not publish through issues, commits or documentation:

- Supabase credentials or service-role keys.
- Firebase service-account credentials.
- Android keystores or signing passwords.
- Real personal data.
- Real locations or operational records.
- Voice profiles, biometric embeddings or other sensitive data.

## Configuration

Supabase credentials are supplied at build time with:

```bash
--dart-define=SUPABASE_URL=...
--dart-define=SUPABASE_ANON_KEY=...
```

Local Android/Firebase configuration is intentionally excluded from version control.

## Reporting

If you discover a security issue, avoid publishing exploit details in a public issue. Contact the repository owner privately with enough information to reproduce the problem.

## Deployment warning

The repository is not a production-certified monitoring system. Before operational deployment, review authentication, authorization, Supabase RLS/policies, RPC permissions, Android permissions, device binding, background execution and secure release signing.
