FROM python:3.12-slim

WORKDIR /app

# 로그 버퍼링 방지 - kubectl logs에서 print() 출력이 즉시 보이도록
ENV PYTHONUNBUFFERED=1

# 의존성 먼저 설치 (레이어 캐싱으로 재빌드 속도 향상)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 애플리케이션 코드 복사
COPY outbox_publisher.py .

# Prometheus 메트릭 포트 (METRICS_PORT 환경변수와 일치)
EXPOSE 8001

CMD ["python", "outbox_publisher.py"]