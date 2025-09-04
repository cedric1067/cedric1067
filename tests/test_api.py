import pytest
from httpx import AsyncClient, ASGITransport

from app.main import app


@pytest.mark.asyncio
async def test_health_ok():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/v1/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_items_crud_flow():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        # list empty
        r = await ac.get("/api/v1/items")
        assert r.status_code == 200
        assert r.json() == []

        # create
        payload = {"name": "Stylo", "description": "Stylo bleu", "price": 2.5}
        r = await ac.post("/api/v1/items", json=payload)
        assert r.status_code == 201
        created = r.json()
        assert created["id"] == 1
        assert created["name"] == payload["name"]

        # get
        r = await ac.get("/api/v1/items/1")
        assert r.status_code == 200
        assert r.json()["id"] == 1

        # update
        r = await ac.put("/api/v1/items/1", json={"price": 3.0})
        assert r.status_code == 200
        assert r.json()["price"] == 3.0

        # delete
        r = await ac.delete("/api/v1/items/1")
        assert r.status_code == 204

        # get 404
        r = await ac.get("/api/v1/items/1")
        assert r.status_code == 404

