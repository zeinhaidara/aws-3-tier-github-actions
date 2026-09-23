import os

os.environ["DATABASE_URL"] = "sqlite:///./test.db"
os.environ["SEED_DATA"] = "true"

from fastapi.testclient import TestClient

from main import app


def test_health_and_ready():
    with TestClient(app) as client:
        assert client.get("/healthz").status_code == 200
        assert client.get("/readyz").status_code == 200
        assert client.get("/").status_code == 200


def test_seeded_products():
    with TestClient(app) as client:
        response = client.get("/api/products")
        assert response.status_code == 200
        assert len(response.json()) >= 2

