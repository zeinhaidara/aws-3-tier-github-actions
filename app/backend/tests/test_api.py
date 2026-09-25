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


def test_create_and_delete_product():
    with TestClient(app) as client:
        created = client.post(
            "/api/products",
            json={"name": "Delete me", "description": "temporary", "price": 1.0},
        )
        assert created.status_code == 201
        product_id = created.json()["id"]

        deleted = client.delete(f"/api/products/{product_id}")
        assert deleted.status_code == 204
        assert client.delete(f"/api/products/{product_id}").status_code == 404


def test_product_validation():
    with TestClient(app) as client:
        assert client.post("/api/products", json={"name": "", "price": 1}).status_code == 422
        assert client.post("/api/products", json={"name": "Invalid", "price": -1}).status_code == 422

