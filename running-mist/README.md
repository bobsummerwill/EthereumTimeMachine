# Running Mist with Historical Geth Versions

This guide documents compatibility between Mist/Ethereum Wallet and historical Geth versions for the Ethereum Time Machine project.

## Overview

Mist (and Ethereum Wallet) connects to Geth via IPC. The IPC protocol evolved over time, so **version matching is critical**. Using a Mist version that's too new for your Geth will result in IPC response format mismatches and crashes.

## Confirmed Working Combinations

| Geth Version | Mist/Wallet Version | Status |
|--------------|---------------------|--------|
| **1.1.0** (Aug 2015) | **0.2.6** (Sep 2015) | Confirmed working |
| 1.3.x (Early 2016) | 0.3.7 - 0.3.8 | Expected to work |
| 1.4.x (Mid 2016) | 0.7.x - 0.8.0 | Expected to work |

## Version Timeline

### Geth Releases (2015-2016)

| Version | Date | Era |
|---------|------|-----|
| v1.0.0 | Jul 30, 2015 | Frontier launch |
| v1.1.0 | Aug 25, 2015 | Frontier |
| v1.1.3 | Sep 10, 2015 | Frontier |
| 1.2.1 | Oct 1, 2015 | Frontier |
| 1.3.3 | Jan 2016 | Frontier/Homestead |
| 1.3.6 | Apr 1, 2016 | Homestead |

### Mist/Wallet Releases

| Version | Date | Bundled Geth | Fork Requirements |
|---------|------|--------------|-------------------|
| **0.2.6** | Sep 16, 2015 | ~1.1.x | Frontier only |
| 0.3.1-0.3.6 | Oct-Nov 2015 | ~1.2.x | Frontier only |
| **0.3.7** | Dec 3, 2015 | ~1.2.x-1.3.x | Frontier only |
| 0.3.8 | Jan 11, 2016 | 1.3.3 | Frontier only |
| 0.4.0-0.7.6 | Feb-Jun 2016 | 1.3.x-1.4.x | **Homestead only** |
| 0.8.0 | Jul 8, 2016 | ~1.4.x | Homestead (pre-DAO) |
| 0.8.1+ | Jul 17, 2016+ | 1.4.10+ | DAO fork |

## Win64 Binary Downloads

### Frontier Era (Geth 1.1.0)

| Version | Filename | Size | Link |
|---------|----------|------|------|
| **0.2.6** | `Ethereum-Wallet-win32-x64-0-2-6.zip` | 67 MB | [Download](https://github.com/ethereum/mist/releases/download/0.2.6/Ethereum-Wallet-win32-x64-0-2-6.zip) |
| 0.3.6 | `Mist-win64-0-3-6.zip` | 86 MB | [Download](https://github.com/ethereum/mist/releases/download/0.3.6/Mist-win64-0-3-6.zip) |
| 0.3.7 | `Ethereum-Wallet-win64-0-3-7.zip` | 91 MB | [Download](https://github.com/ethereum/mist/releases/download/0.3.7/Ethereum-Wallet-win64-0-3-7.zip) |

### Homestead Era (Geth 1.3.6)

| Version | Filename | Size | Link |
|---------|----------|------|------|
| **0.7.4** | `Ethereum-Wallet-win64-0-7-4.zip` | 70 MB | [Download](https://github.com/ethereum/mist/releases/download/0.7.4/Ethereum-Wallet-win64-0-7-4.zip) |
| 0.7.5 | `Ethereum-Wallet-win64-0-7-5.zip` | 102 MB | [Download](https://github.com/ethereum/mist/releases/download/0.7.5/Ethereum-Wallet-win64-0-7-5.zip) |
| 0.7.6 | `Ethereum-Wallet-win64-0-7-6.zip` | 106 MB | [Download](https://github.com/ethereum/mist/releases/download/0.7.6/Ethereum-Wallet-win64-0-7-6.zip) |
| 0.8.0 | `Ethereum-Wallet-win64-0-8-0.zip` | 103 MB | [Download](https://github.com/ethereum/mist/releases/download/0.8.0/Ethereum-Wallet-win64-0-8-0.zip) |

### Geth Win64 Binaries

| Version | Filename | Link |
|---------|----------|------|
| v1.1.0 | `Geth-Win64-20150825140940-1.1.0-fd512fa.zip` | [Download](https://github.com/ethereum/go-ethereum/releases/download/v1.1.0/Geth-Win64-20150825140940-1.1.0-fd512fa.zip) |
| v1.3.3 | `Geth-Win64-20160105141035-1.3.3-c541b38.zip` | [Download](https://github.com/ethereum/go-ethereum/releases/download/v1.3.3/Geth-Win64-20160105141035-1.3.3-c541b38.zip) |
| v1.3.5 | `Geth-Win64-20160303142914-1.3.5-34b622a.zip` | [Download](https://github.com/ethereum/go-ethereum/releases/download/v1.3.5/Geth-Win64-20160303142914-1.3.5-34b622a.zip) |
| v1.3.6 | `Geth-Win64-20160401105807-1.3.6-9e323d6.zip` | [Download](https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/Geth-Win64-20160401105807-1.3.6-9e323d6.zip) |

## IPC Connection Behavior

When Mist starts:

1. Looks for `geth.ipc` at the default location
2. **If found** → connects to running Geth
3. **If not found** → starts bundled Geth

### Windows IPC Path

```
\\.\pipe\geth.ipc
```

Default data directory:
```
%APPDATA%\Ethereum\
```

### Force Mist to Use External Geth

```cmd
Ethereum-Wallet.exe --rpc \\.\pipe\geth.ipc
```

## Common Errors

### "Cannot read property 'hash' of undefined"

**Cause**: Mist version too new for your Geth. The IPC response format changed.

**Solution**: Use an older Mist version closer to your Geth release date.

### "Cannot read property 'error' of undefined"

**Cause**: Same as above - IPC protocol mismatch.

**Solution**: Try an even older Mist version.

### Mist starts syncing from block 0

**Cause**: Mist couldn't find your running Geth and started its own bundled version.

**Solution**:
1. Ensure Geth is running before starting Mist
2. Use `--rpc` flag to specify IPC path
3. Check that IPC is enabled in your Geth

## Memory Considerations (4GB RAM Systems)

| Component | RAM Usage |
|-----------|-----------|
| Geth 1.1.0 (synced, idle) | ~500-800 MB |
| Mist 0.2.6 | ~400-600 MB |
| **Total** | ~1-1.5 GB |

Tips:
- Close other applications when running Mist
- Earlier Mist versions use less RAM
- Run Geth externally (don't let Mist spawn its own)

## Fallback: Geth Console

If no Mist version works, use Geth's JavaScript console:

```cmd
geth attach
```

### Common Console Commands

```javascript
// List accounts
eth.accounts

// Create new account
personal.newAccount()

// Check balance (in ether)
web3.fromWei(eth.getBalance(eth.accounts[0]), "ether")

// Unlock account (required before sending)
personal.unlockAccount(eth.accounts[0], "password", 300)

// Send transaction
eth.sendTransaction({
  from: eth.accounts[0],
  to: "0xRecipientAddress",
  value: web3.toWei(1, "ether")
})

// Check transaction
eth.getTransaction("0xTxHash")

// Current block number
eth.blockNumber

// Sync status
eth.syncing
```

## Tested Hardware

- **2010 ThinkPads** with Win64, 4GB RAM
- Geth 1.1.0 + Mist 0.2.6: **Working**

## References

- [Mist Releases](https://github.com/ethereum/mist/releases)
- [Go-Ethereum Releases](https://github.com/ethereum/go-ethereum/releases)
- [Homestead Release Blog](https://blog.ethereum.org/2016/02/29/homestead-release)
