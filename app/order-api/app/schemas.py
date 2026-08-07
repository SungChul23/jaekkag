from enum import Enum

from pydantic import BaseModel, Field


class ProductId(str, Enum):
    # Fold
    FOLD_BLACK = "101"
    FOLD_WHITE = "102"
    FOLD_LAVENDER = "103"
    FOLD_GRAY = "104"

    # Flip
    FLIP_BLACK = "201"
    FLIP_WHITE = "202"
    FLIP_LAVENDER = "203"
    FLIP_GRAY = "204"

    # Ultra
    ULTRA_BLACK = "301"
    ULTRA_WHITE = "302"
    ULTRA_LAVENDER = "303"
    ULTRA_GRAY = "304"


class OrderCreateRequest(BaseModel):
    product_id: ProductId = Field(
        ...,
        examples=["101"],
        description="상품 ID",
    )

    quantity: int = Field(
        ...,
        gt=0,
        le=1,
        examples=[1],
        description="주문 수량",
    )


class OrderCreateResponse(BaseModel):
    order_id: int
    status: str