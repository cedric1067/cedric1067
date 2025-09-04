from typing import List

from fastapi import APIRouter, Depends, HTTPException, status

from ...db.memory import InMemoryItemStore
from ...models.item import Item, ItemCreate, ItemUpdate


router = APIRouter()


def get_store() -> InMemoryItemStore:
    if not hasattr(get_store, "_store"):
        get_store._store = InMemoryItemStore()  # type: ignore[attr-defined]
    return get_store._store  # type: ignore[attr-defined]


@router.get("/health", tags=["health"])
def health() -> dict:
    return {"status": "ok"}


@router.get("/items", response_model=List[Item], tags=["items"])
def list_items(store: InMemoryItemStore = Depends(get_store)) -> List[Item]:
    return store.list_items()


@router.post("/items", response_model=Item, status_code=status.HTTP_201_CREATED, tags=["items"])
def create_item(payload: ItemCreate, store: InMemoryItemStore = Depends(get_store)) -> Item:
    return store.create_item(payload)


@router.get("/items/{item_id}", response_model=Item, tags=["items"])
def get_item(item_id: int, store: InMemoryItemStore = Depends(get_store)) -> Item:
    item = store.get_item(item_id)
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    return item


@router.put("/items/{item_id}", response_model=Item, tags=["items"])
def update_item(item_id: int, payload: ItemUpdate, store: InMemoryItemStore = Depends(get_store)) -> Item:
    item = store.update_item(item_id, payload)
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    return item


@router.delete("/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["items"])
def delete_item(item_id: int, store: InMemoryItemStore = Depends(get_store)) -> None:
    deleted = store.delete_item(item_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
    return None

