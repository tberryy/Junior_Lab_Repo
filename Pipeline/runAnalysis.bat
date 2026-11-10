@echo off
rem Runs the whole Junior Lab pipeline (runAnalysis.m) with MATLAB in batch mode.
rem Double-click it, or run it from a command prompt. Output goes to
rem ProcessedData\run_log.txt next to the figures and workbooks.
setlocal
set "PIPE=%~dp0"
set "LOG=%~dp0..\ProcessedData\run_log.txt"
if not exist "%~dp0..\ProcessedData" mkdir "%~dp0..\ProcessedData"
echo Started %date% %time% > "%LOG%"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -batch "cd('%PIPE%'); runAnalysis" >> "%LOG%" 2>&1
echo MATLAB exit code %ERRORLEVEL% >> "%LOG%"
echo Finished %date% %time% >> "%LOG%"
endlocal
