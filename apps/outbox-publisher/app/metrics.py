from prometheus_client import Counter, Gauge

from app.database import count_by_status

outbox_pending_events = Gauge("outbox_pending_events", "발행 대기 중인 이벤트 수")
outbox_failed_events = Gauge("outbox_failed_events", "최대 재시도 초과로 실패 처리된 이벤트 수")
outbox_publish_total = Counter("outbox_publish_total", "발행 성공 건수")
outbox_publish_errors_total = Counter("outbox_publish_errors_total", "발행 실패 건수")


def update_gauges(conn):
    """현재 PENDING / FAILED 상태 이벤트 수를 세어 Gauge에 반영.
    Grafana에서 '미발행 이벤트 적체'와 '영구 실패 이벤트 누적'을
    실시간으로 볼 수 있게 해준다."""
    outbox_pending_events.set(count_by_status(conn, "PENDING"))
    outbox_failed_events.set(count_by_status(conn, "FAILED"))