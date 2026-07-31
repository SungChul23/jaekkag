from itertools import count

from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field


app = FastAPI(
    title="Jaekkag Order API",
    version="0.1.0",
)

# 临时订单编号生成器
# 程序每次重新启动后，会从 1 重新开始
order_id_generator = count(start=1)


class OrderCreateRequest(BaseModel):
    """创建订单时，客户端需要发送的数据。"""

    product_id: int = Field(
        ...,
        gt=0,
        description="商品 ID，必须大于 0",
        examples=[101],
    )
    quantity: int = Field(
        ...,
        gt=0,
        le=100,
        description="订单数量，必须为 1～100",
        examples=[2],
    )


class OrderCreateResponse(BaseModel):
    """创建订单成功后返回的数据。"""

    order_id: int
    product_id: int
    quantity: int
    status: str


@app.get("/")
def root():
    return {"message": "Order API Running"}


@app.get("/health")
def health_check():
    return {"status": "healthy"}


@app.get("/ready")
def readiness_check():
    return {"status": "ready"}


@app.post(
    "/orders",
    response_model=OrderCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_order(order: OrderCreateRequest):
    # 这里先模拟业务验证
    if order.product_id == 999:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Product not found",
        )

    new_order_id = next(order_id_generator)

    return OrderCreateResponse(
        order_id=new_order_id,
        product_id=order.product_id,
        quantity=order.quantity,
        status="created",
    )