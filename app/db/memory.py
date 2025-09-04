from typing import Dict, List, Optional

from ..models.item import Item, ItemCreate, ItemUpdate


class InMemoryItemStore:
    def __init__(self) -> None:
        self._items: Dict[int, Item] = {}
        self._next_id: int = 1

    def list_items(self) -> List[Item]:
        return list(self._items.values())

    def get_item(self, item_id: int) -> Optional[Item]:
        return self._items.get(item_id)

    def create_item(self, data: ItemCreate) -> Item:
        item = Item(id=self._next_id, **data.model_dump())
        self._items[self._next_id] = item
        self._next_id += 1
        return item

    def update_item(self, item_id: int, data: ItemUpdate) -> Optional[Item]:
        existing_item = self._items.get(item_id)
        if existing_item is None:
            return None
        updated_payload = existing_item.model_dump()
        changes = data.model_dump(exclude_unset=True)
        updated_payload.update(changes)
        updated_item = Item(**updated_payload)
        self._items[item_id] = updated_item
        return updated_item

    def delete_item(self, item_id: int) -> bool:
        if item_id in self._items:
            del self._items[item_id]
            return True
        return False

