# CI / GitHub Actions

This repository uses a reusable GitHub Actions workflow at `.github/workflows/reusable-ci.yml`.

Required repository secrets (add in Settings → Secrets):

- `AWS_ACCESS_KEY_ID` — AWS credentials for ECR push
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` — e.g. `us-east-1`
- `ECR_REGISTRY` — account-id.dkr.ecr.<region>.amazonaws.com
- `ECR_REPOSITORY_PREFIX` — prefix for repositories inside ECR (e.g. `tech-challenge`)

How it works:
- Per-service workflows in `.github/workflows/ci-<service>.yml` trigger on path changes and call the reusable workflow.
- The reusable workflow performs dependency caching, dependency scanning (`gosec` / `pip-audit`), builds a Docker image tagged `sha-<shortsha>`, runs a Trivy container scan, and optionally pushes to ECR when `push` is enabled (configured to run on `main`).

To add a new service:
1. Create `.github/workflows/ci-<service>.yml` that calls the reusable workflow with appropriate inputs (`service`, `context`, `language`, etc.).
2. Ensure the service has a `Dockerfile` at the configured context, or pass the `dockerfile` input.
3. Set `push` in the caller to `${{ github.ref == 'refs/heads/main' }}` to only push from `main`.
