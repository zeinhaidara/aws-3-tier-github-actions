# FastAPI backend

Run locally:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export SEED_DATA=true
uvicorn main:app --reload
```

Endpoints:

- `GET /healthz` — process health check
- `GET /readyz` — database readiness check
- `GET /api/products` — list products
- `POST /api/products` — create a product

The dev seed data is enabled with `SEED_DATA=true`. Production should use a migration and controlled seed job instead of automatic seeding.

On AWS, set `DATABASE_SECRET_ARN` to the RDS-managed Secrets Manager secret. The application retrieves the username and password using the EC2 instance role; database credentials are never stored in GitHub or the image.
