@echo off
setlocal enabledelayedexpansion
openfiles>nul 2>&1
if %errorlevel% neq 0 (
  where sudo.exe>nul 2>&1
  if !errorlevel! equ 0 (
    sudo.exe "%~0"
  ) else (
    start /B /I /wait powershell start-process '%~0' -Verb runas
  )
  exit
)
powershell -ExecutionPolicy Bypass -File "%~dp0node_sea_build.ps1"