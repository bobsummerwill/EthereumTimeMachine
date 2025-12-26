@echo off
setlocal ENABLEEXTENSIONS

REM ============================================================================
REM Geth v1.1.0 (Win64) launcher
REM - Downloads official v1.1.0 Win64 zip from ethereum/go-ethereum GitHub
REM - Extracts into: C:\Ethereum\Geth-1.1.0\
REM - Writes a single-peer static-nodes.json pointing at the v1.3.6 node on the VM
REM - Runs with discovery disabled and no bootnodes (manual peering only)
REM
REM Remote VM IP is taken from chain-of-geths/deploy.sh in this repo:
REM   VM_IP="54.81.90.194"
REM ============================================================================

REM === Install/run location on this Windows machine ===
set "BASE=C:\Ethereum\Geth-1.1.0"
set "DATADIR=%BASE%\data"

REM === Download details ===
set "URL=https://github.com/ethereum/go-ethereum/releases/download/v1.1.0/Geth-Win64-20150825140940-1.1.0-fd512fa.zip"
set "ZIP=%BASE%\Geth-Win64-20150825140940-1.1.0-fd512fa.zip"

REM === Remote v1.3.6 peer (pubkey taken from this repo: generated-files/data/v1.0.3/static-nodes.json) ===
set "VM_HOST=54.81.90.194"
REM Per chain-of-geths/docker-compose.yml, the v1.3.6 node exposes P2P on 30307 TCP+UDP.
set "VM_PORT=30307"
set "V136_PUBKEY=23b9ce0d434ddf399ee2200e5749f3b992afa322333069a859d8b09f36e9159095507b1ac36aa010272479f2b4390e55fac4d80468993c1e55081e48649968f1"
set "ENODE=enode://%V136_PUBKEY%@%VM_HOST%:%VM_PORT%?discport=0"

REM === Prep dirs ===
if not exist "%BASE%" mkdir "%BASE%"
if not exist "%DATADIR%" mkdir "%DATADIR%"

REM === Download zip (requires PowerShell) ===
if not exist "%ZIP%" (
  echo Downloading:
  echo   %URL%
  powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%URL%' -OutFile '%ZIP%'"
  if errorlevel 1 (
    echo Download failed.
    exit /b 1
  )
)

REM === Extract zip into BASE ===
echo Extracting %ZIP% to %BASE% ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force -Path '%ZIP%' -DestinationPath '%BASE%'"
if errorlevel 1 (
  echo Extraction failed.
  exit /b 1
)

REM === Write static-nodes.json (manual peering only) ===
echo Writing %DATADIR%\static-nodes.json with:
echo   %ENODE%
echo ["%ENODE%"]> "%DATADIR%\static-nodes.json"

REM === Find geth.exe ===
set "GETH=%BASE%\geth.exe"
if not exist "%GETH%" (
  for /r "%BASE%" %%F in (geth.exe) do (
    set "GETH=%%F"
    goto :found_geth
  )
)

:found_geth
if not exist "%GETH%" (
  echo Could not find geth.exe after extraction.
  exit /b 1
)

echo Using geth: %GETH%
echo.
echo Starting geth with manual peering only (discovery disabled)...
echo.

REM Flags:
REM  --datadir "%DATADIR%"  keep chain data under C:\Ethereum\Geth-1.1.0\data
REM  --networkid 1          mainnet (explicit)
REM  --nodiscover           disable discovery
REM  --bootnodes ""         do not use any bootnodes
REM  --maxpeers 1           only the one static peer
REM  --port 30303           local listen port (change if it conflicts)
"%GETH%" --datadir "%DATADIR%" --networkid 1 --port 30303 --nodiscover --bootnodes "" --maxpeers 1

endlocal
