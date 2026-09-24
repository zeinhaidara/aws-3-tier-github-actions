from contextlib import asynccontextmanager
import json
from pathlib import Path
from typing import Annotated
from urllib.parse import quote_plus

import boto3
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import Boolean, Float, String, create_engine, select, text
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "cloudbatch818-api"
    database_url: str = "sqlite:///./app.db"
    database_secret_arn: str | None = None
    database_host: str | None = None
    database_port: int = 3306
    seed_data: bool = False


settings = Settings()


def resolve_database_url() -> str:
    if settings.database_secret_arn:
        secret = boto3.client("secretsmanager").get_secret_value(
            SecretId=settings.database_secret_arn
        )
        credentials = json.loads(secret["SecretString"])
        host = settings.database_host or credentials["host"]
        port = credentials.get("port", settings.database_port)
        database = credentials.get("dbname", "app")
        return (
            f"mysql+pymysql://{quote_plus(credentials['username'])}:"
            f"{quote_plus(credentials['password'])}"
            f"@{host}:{port}/{database}"
        )
    return settings.database_url


database_url = resolve_database_url()
connect_args = {"check_same_thread": False} if database_url.startswith("sqlite") else {}
engine = create_engine(database_url, connect_args=connect_args, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    description: Mapped[str] = mapped_column(String(500), default="")
    price: Mapped[float] = mapped_column(Float)
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class ProductCreate(BaseModel):
    name: str
    description: str = ""
    price: float
    active: bool = True


class ProductResponse(ProductCreate):
    model_config = ConfigDict(from_attributes=True)

    id: int


def seed_products(session: Session) -> None:
    if session.scalar(select(Product.id).limit(1)) is not None:
        return

    session.add_all(
        [
            Product(name="Starter plan", description="Development starter plan", price=9.99),
            Product(name="Professional plan", description="Production-ready plan", price=29.99),
        ]
    )
    session.commit()


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(engine)
    if settings.seed_data:
        with SessionLocal() as session:
            seed_products(session)
    yield
    engine.dispose()


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)


def get_session():
    with SessionLocal() as session:
        yield session


SessionDependency = Annotated[Session, Depends(get_session)]


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz(session: SessionDependency):
    try:
        session.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="database unavailable",
        ) from exc
    return {"status": "ready"}


@app.get("/api/products", response_model=list[ProductResponse])
def list_products(session: SessionDependency):
    return list(session.scalars(select(Product).order_by(Product.id)))


@app.post("/api/products", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)
def create_product(product: ProductCreate, session: SessionDependency):
    existing = session.scalar(select(Product).where(Product.name == product.name))
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="product already exists")

    record = Product(**product.model_dump())
    session.add(record)
    session.commit()
    session.refresh(record)
    return record


@app.delete("/api/products/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_product(product_id: int, session: SessionDependency):
    record = session.get(Product, product_id)
    if record is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="product not found")

    session.delete(record)
    session.commit()


app.mount(
    "/",
    StaticFiles(directory=Path(__file__).parent / "static", html=True),
    name="frontend",
)

