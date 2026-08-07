from app.config import BATCH_SIZE, MAX_RETRY_COUNT
from app.database import fetch_and_lock_one, mark_published, mark_failed
from app.kinesis_publisher import publish_one
from app.metrics import outbox_publish_total, outbox_publish_errors_total


def process_batch(conn):
    """한 폴링 주기에 최대 BATCH_SIZE건까지, 1건씩 잠그고 처리한다.
    다른 파드가 이미 다 가져가서 더 이상 잠글 게 없으면 자연스럽게 멈춘다."""
    processed = 0
    for _ in range(BATCH_SIZE):
        row = fetch_and_lock_one(conn)
        if row is None:
            # 더 이상 PENDING(잠글 수 있는) 이벤트가 없음 -> 이번 배치 종료
            conn.commit()  # 트랜잭션 정리 (조회만 했어도 커밋으로 마무리)
            break

        event_id, order_id, product_id, quantity, created_at, retry_count = row
        try:
            publish_one(event_id, order_id, product_id, quantity, created_at)
            mark_published(conn, event_id)
            outbox_publish_total.inc()
        except Exception as e:
            outbox_publish_errors_total.inc()
            gave_up = mark_failed(conn, event_id, e, retry_count, MAX_RETRY_COUNT)
            if gave_up:
                print(f"[outbox-publisher] event_id={event_id} FAILED (max retry {MAX_RETRY_COUNT} exceeded): {e}", flush=True)
            else:
                print(f"[outbox-publisher] publish failed event_id={event_id} retry={retry_count + 1}/{MAX_RETRY_COUNT}: {e}", flush=True)

        processed += 1
    return processed