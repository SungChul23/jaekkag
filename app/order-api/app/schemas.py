from enum import IntEnum

from pydantic import BaseModel, Field


class ProductId(IntEnum):
    # Fold
    FOLD_BLACK = 101
    FOLD_WHITE = 102
    FOLD_LAVENDER = 103
    FOLD_GRAY = 104

    # Flip
    FLIP_BLACK = 201
    FLIP_WHITE = 202
    FLIP_LAVENDER = 203
    FLIP_GRAY = 204

    # Ultra
    ULTRA_BLACK = 301
    ULTRA_WHITE = 302
    ULTRA_LAVENDER = 303
    ULTRA_GRAY = 304


class OrderCreateRequest(BaseModel):
    product_id: ProductId = Field(
        ...,
        examples=[101],
        description=(
            "상품 ID "
            "(101~104: Fold, 201~204: Flip, 301~304: Ultra)"
        ),
    )

    quantity: int = Field(
        ...,
        gt=0,
        le=100,
        examples=[1],
        description="주문 수량 (1~100)",
    )


class OrderCreateResponse(BaseModel):
    order_id: int
    status: str