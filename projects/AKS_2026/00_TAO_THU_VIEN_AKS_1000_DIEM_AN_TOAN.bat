@echo off
chcp 65001 >nul
setlocal
set "PROJECT=%~dp0"
set "GEE_PY=%~dp0..\..\.venv\Scripts\python.exe"

if not exist "%GEE_PY%" (
  echo [LOI] Khong tim thay Python da cai Google Earth Engine:
  echo       %GEE_PY%
  echo Hay chay CAI_DAT_UNG_DUNG.bat o thu muc goc truoc.
  echo Khong co du lieu nao duoc gui.
  pause
  exit /b 1
)

echo [1/2] Kiem tra va trich xuat toi da 1.000 diem AKS trong cung mot tien trinh...
"%GEE_PY%" "%PROJECT%_NOI_BO\pipeline\extract_positive_feature_knowledge_atomic.py" --project-dir "%PROJECT%."
if errorlevel 1 goto :failed

echo [2/2] Loai toa do, doi ma dong va tao knowledge-private...
"%GEE_PY%" "%PROJECT%_NOI_BO\pipeline\ingest_positive_feature_knowledge.py" --project-dir "%PROJECT%."
if errorlevel 1 goto :failed

echo [OK] Thu vien positive_reference_only da san sang va khong chua toa do.
pause
exit /b 0

:failed
echo [DA CHAN] Quy trinh dung an toan; khong phat hanh goi knowledge moi.
echo Xem thong bao loi phia tren.
pause
exit /b 1
