import pymysql

from app.config import DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD


def get_conn():
    return pymysql.connect(
        host=DB_HOST, port=DB_PORT, db=DB_NAME,
        user=DB_USER, password=DB_PASSWORD, autocommit=False,
    )


def fetch_and_lock_one(conn):
    """PENDING 이벤트 1건을 잠그고 가져온다.
    여러 파드가 동시에 폴링해도 SKIP LOCKED 덕분에 이미 잠긴 row는
    자동으로 건너뛰고 서로 다른 row를 가져가게 된다.
    (한 번에 여러 건을 잠그면 첫 건 커밋 시 나머지 잠금까지 풀려버려서
     반드시 1건 단위로 잠그고, 처리하고, 커밋한다.)
    retry_count도 같이 가져와서 재시도 한도 판단에 사용한다."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT event_id, order_id, product_id, quantity, created_at, retry_count
            FROM outbox_events
            WHERE publish_status = 'PENDING'
            ORDER BY created_at
            LIMIT 1
            FOR UPDATE SKIP LOCKED
            """
        )
        return cur.fetchone()


def mark_published(conn, event_id):
    """발행 성공 -> PUBLISHED 전환 + 발행 완료 시각 기록"""
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE outbox_events SET publish_status = 'PUBLISHED', published_at = NOW() WHERE event_id = %s",
            (event_id,),
        )
    conn.commit()  # 이 시점에 해당 row의 잠금이 해제됨


def mark_failed(conn, event_id, error_message, current_retry_count, max_retry_count):
    """발행 실패 처리.
    - max_retry_count 미만이면: PENDING 유지 (다음 폴링에서 자동 재시도)
    - max_retry_count 이상이면: FAILED로 전환해서 더 이상 폴링 대상에서 제외
      (무한 재시도로 인한 자원 낭비/정상 이벤트 처리 지연 방지)"""
    next_retry_count = current_retry_count + 1
    with conn.cursor() as cur:
        if next_retry_count >= max_retry_count:
            cur.execute(
                """
                UPDATE outbox_events
                SET publish_status = 'FAILED',
                    retry_count = %s,
                    last_error = %s
                WHERE event_id = %s
                """,
                (next_retry_count, str(error_message)[:1000], event_id),
            )
        else:
            cur.execute(
                """
                UPDATE outbox_events
                SET retry_count = %s,
                    last_error = %s
                WHERE event_id = %s
                """,
                (next_retry_count, str(error_message)[:1000], event_id),
            )
    conn.commit()
    return next_retry_count >= max_retry_count


def count_by_status(conn, status):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT COUNT(*) FROM outbox_events WHERE publish_status = %s",
            (status,),
        )
        (count,) = cur.fetchone()
    return count