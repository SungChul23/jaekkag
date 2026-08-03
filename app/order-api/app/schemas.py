from pydantic import BaseModel, Field


class OrderCreateRequest(BaseModel):
    product_id: int = Field(..., gt=0, examples=[10])
    quantity: int = Field(..., gt=0, le=100, examples=[2])


class OrderCreateResponse(BaseModel):
    order_id: int
    status: str