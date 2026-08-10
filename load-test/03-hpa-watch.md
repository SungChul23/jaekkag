# [3] Order API 부하 증가 - HPA 작동, Pod 증가 (관찰)

k6 스파이크(`02-spike-test.js`)가 도는 동안 별도 터미널에서 실행.

```powershell
kubectl get hpa -n ecommerce -w
```

```powershell
kubectl get pods -n ecommerce -w
```

CPU 사용률이 임계치를 넘으면서 Order API Pod 개수가 늘어나는지 확인.