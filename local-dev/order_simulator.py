"""
1번(Order API)이 아직 준비되지 않았을 때, 그 역할을 흉내내서
orders + outbox_events를 한 트랜잭션으로 넣어주는 검증용 스크립트.

1번 코드가 완성되면 이 스크립트는 더 이상 필요 없음 (진짜 Order API가 이 역할을 대신함).
"""
import time
import uuid
import random
import pymysql

DB_HOST = "localhost"
DB_PORT = 3307
DB_NAME = "ecommerce"
DB_USER = "appuser"
DB_PASSWORD = "devpass"

PRODUCT_IDS = [10, 20, 30]


def get_conn():
    return pymysql.connect(
        host=DB_HOST, port=DB_PORT, db=DB_NAME,
        user=DB_USER, password=DB_PASSWORD, autocommit=False,
    )


def create_fake_order(conn):
    product_id = random.choice(PRODUCT_IDS)
    quantity = random.randint(1, 5)
    event_id = str(uuid.uuid4())

    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO orders (product_id, quantity) VALUES (%s, %s)",
            (product_id, quantity),
        )
        order_id = cur.lastrowid
        cur.execute(
            """
            INSERT INTO outbox_events (event_id, order_id, product_id, quantity, status)
            VALUES (%s, %s, %s, %s, 'PENDING')
            """,
            (event_id, order_id, product_id, quantity),
        )
    conn.commit()
    print(f"[order_simulator] order_id={order_id} product_id={product_id} qty={quantity} event_id={event_id}")


def main():
    conn = get_conn()
    print("[order_simulator] 시작. Ctrl+C로 종료")
    try:
        while True:
            create_fake_order(conn)
            time.sleep(2)
    except KeyboardInterrupt:
        pass
    finally:
        conn.close()


if __name__ == "__main__":
    main()
