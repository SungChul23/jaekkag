FROM python:3.12-slim

WORKDIR /app_root

# 의존성 레이어를 코드 레이어보다 먼저 분리
# → requirements.txt가 안 바뀌면 이 pip install 레이어는 캐시 재사용됨
# → 코드만 수정했을 때 재빌드 속도가 빨라짐
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# app/ 패키지 전체 복사 (main.py도 이 안에 포함됨)
COPY app/ ./app/

# Prometheus 메트릭 노출 포트
EXPOSE 8001

# main.py가 app/ 패키지 내부에 있으므로 -m으로 모듈 실행
# (python app/main.py로 직접 실행하면 내부 상대 import가 깨짐)
CMD ["python", "-u", "-m", "app.main"]

