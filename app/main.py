from fastapi import FastAPI

from .api.v1.endpoints import router as api_router


def create_app() -> FastAPI:
    application = FastAPI(title="Exemple d'application FastAPI", version="1.0.0")
    application.include_router(api_router, prefix="/api/v1")
    return application


app = create_app()

