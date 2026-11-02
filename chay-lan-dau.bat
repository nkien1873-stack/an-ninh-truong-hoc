@echo off
rem Tai thu vien cho app, backend va campus_core (chay mot lan sau khi giai nen hoac clone).
rem Can cai Flutter va them thu muc flutter\bin vao PATH.
cd /d "%~dp0"
where flutter >nul 2>nul
if errorlevel 1 (
  echo Khong tim thay lenh flutter. Hay cai Flutter va them flutter\bin vao PATH, roi chay lai.
  pause
  exit /b 1
)
echo [1/3] App Flutter...
call flutter pub get || goto loi
echo [2/3] packages\campus_core...
pushd packages\campus_core
call dart pub get || (popd & goto loi)
popd
echo [3/3] backend...
pushd backend
call dart pub get || (popd & goto loi)
popd
echo.
echo Xong. Mo thu muc nay trong Android Studio, chon may Android roi bam Run.
pause
exit /b 0
:loi
echo.
echo Tai thu vien that bai. Kiem tra mang Internet roi chay lai.
pause
exit /b 1
