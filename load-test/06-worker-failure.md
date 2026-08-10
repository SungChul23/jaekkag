# [6] Worker 강제 장애 - Pod 재생성, 과거 이벤트 재처리

k6 스파이크(`02-spike-test.js`)가 도는 도중, 또는 `01-order-test.js`를 몇 건 더 쏘면서 실행.

## 1. Worker 파드 목록 확인

```powershell
kubectl get pods -n ecommerce -l app=inventory-worker
```

## 2. 하나 강제 삭제

```powershell
kubectl delete pod <파드이름> -n ecommerce
```

## 3. 자동 재생성 관찰

```powershell
kubectl get pods -n ecommerce -l app=inventory-worker -w
```

## 4. 새 파드가 이전 체크포인트부터 이어받는지 로그 확인

```powershell
kubectl logs -n ecommerce <새파드이름> --tail=50
```