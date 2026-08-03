# main.py 
# 启动 FastAPI、注册路由、health、ready、metrics
# schemas.py 请求和响应格式
# metrics.py Prometheus 指标
# routers/orders.py POST /orders 业务逻辑
# models.py orders、outbox_events 数据库模型
# database.py MySQL 连接

from fastapi import FastAPI
from prometheus_client import make_asgi_app

from app.routers.orders import router as orders_router


app = FastAPI(
    title="Ecommerce Timesale Order API",
    version="0.1.0",
)

app.include_router(orders_router)


@app.get("/health")
def health_check():
    return {"status": "UP"}


@app.get("/ready")
def readiness_check():
    return {"status": "READY"}


metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)