# Running Mist with Historical Geth Versions

This guide documents compatibility between Mist/Ethereum Wallet and historical Geth versions for the Ethereum Time Machine project.

## Overview

Mist (and Ethereum Wallet) connects to Geth via IPC. The IPC protocol evolved over time, so **version matching is critical**. Using a Mist version that's too new for your Geth will result in IPC response format mismatches and crashes.

## Confirmed Working Combinations

| Geth Version | Mist/Wallet Version | Status |
|--------------|---------------------|--------|
| **1.1.0** (Aug 2015) | **0.2.6** (Sep 2015) | Confirmed working |
| **1.3.6** (Apr 2016) | **0.7.4** (May 2016) | Confirmed working |
| 1.3.x (Early 2016) | 0.3.7 - 0.3.8 | Expected to work |
| 1.4.x (Mid 2016) | 0.7.x - 0.8.0 | Expected to work |

## Database Migration

Geth supports upgrading chaindata between versions:

- **1.1.0 → 1.3.6**: Works. Shows "found old database" and performs lengthy upgrade.
- Copy the data directory to a new folder before running newer Geth to preserve original.

## Complete Mist/Ethereum Wallet Release Table

All releases include both macOS and Windows 64-bit binaries.

| Version | Date | macOS Binary | Windows Binary | Bundled Node | Notes |
|---------|------|--------------|----------------|--------------|-------|
| 0.2.6 | Sep 16, 2015 | Yes | Yes | ~1.1.x (estimated) | First public release, Ethereum Wallet only |
| 0.3.1 | Oct 13, 2015 | Yes | Yes | Unknown | |
| 0.3.2 | Oct 17, 2015 | Yes | Yes | Unknown | |
| 0.3.4 | Oct 30, 2015 | Yes | Yes | Unknown | |
| 0.3.5 | Nov 2, 2015 | Yes | Yes | geth 1.3.1 | First confirmed geth version |
| 0.3.6 | Nov 13, 2015 | Yes | Yes | geth 1.2.2 | |
| 0.3.7 | Dec 3, 2015 | Yes | Yes | Unknown | |
| 0.3.8 | Jan 11, 2016 | Yes | Yes | geth 1.3.3 | Last pre-Homestead release |
| 0.4.0 | Feb 9, 2016 | Yes | Yes | Unknown | |
| 0.5.0 | Mar 1, 2016 | Yes | Yes | geth 1.3.5 | **First Homestead-ready release** |
| 0.5.1 | Mar 14, 2016 | Yes | Yes | geth 1.3.5 | Homestead mainnet launch version |
| 0.5.2 | Mar 21, 2016 | Yes | Yes | geth 1.3.6 | |
| 0.6.0 | Apr 7, 2016 | Yes | Yes | Unknown | |
| 0.6.1 | Apr 12, 2016 | Yes | Yes | Unknown | |
| 0.6.2 | Apr 14, 2016 | Yes | Yes | geth 1.3.6 | |
| 0.7.0 | Apr 26, 2016 | Yes | Yes | Unknown | |
| 0.7.1 | Apr 28, 2016 | Yes | Yes | Unknown | |
| 0.7.2 | May 4, 2016 | Yes | Yes | geth 1.4.3 | |
| 0.7.3 | May 13, 2016 | Yes | Yes | Unknown | |
| 0.7.4 | May 26, 2016 | Yes | Yes | geth 1.4.5 | **First geth 1.4.x release** |
| 0.7.5 | Jun 3, 2016 | Yes | Yes | geth 1.4.5 | |
| 0.7.6 | Jun 17, 2016 | Yes | Yes | geth 1.4.6 | Last pre-DAO release |
| 0.8.0 | Jul 8, 2016 | Yes | Yes | geth 1.4.8 | First Mist Browser (pre-DAO fork) |
| 0.8.1 | Jul 17, 2016 | Yes | Yes | geth 1.4.10 | DAO fork support |
| 0.8.2 | Aug 5, 2016 | Yes | Yes | geth 1.4.11 | |
| 0.8.3 | Sep 28, 2016 | Yes | Yes | geth 1.4.12 | |
| 0.8.4 | Oct 14, 2016 | Yes | Yes | geth 1.4.18 | |
| 0.8.5 | Oct 21, 2016 | Yes | Yes | Unknown | |
| 0.8.6 | Oct 25, 2016 | Yes | Yes | geth 1.4.18 | |
| 0.8.7 | Nov 14, 2016 | Yes | Yes | geth 1.5.2 | First geth 1.5.x |
| 0.8.8 | Dec 2, 2016 | Yes | Yes | geth 1.5.4 | |
| 0.8.9 | Jan 13, 2017 | Yes | Yes | geth 1.5.6 | |
| 0.8.10 | Apr 25, 2017 | Yes | Yes | geth 1.6.1 | First geth 1.6.x |
| 0.9.0 | Aug 22, 2017 | Yes | Yes | geth 1.6.7 | Byzantium-ready |
| 0.9.1 | Oct 2, 2017 | Yes | Yes | geth 1.7.1 | First geth 1.7.x |
| 0.9.2 | Oct 17, 2017 | Yes | Yes | geth 1.7.2 | |
| 0.9.3 | Jan 25, 2018 | Yes | Yes | geth 1.7.3 | |
| 0.10.0 | May 2, 2018 | Yes | Yes | geth 1.8.6 | First geth 1.8.x |
| 0.11.0 | Sep 26, 2018 | Yes | Yes | geth 1.8.16 | |
| 0.11.1 | Mar 27, 2019 | Yes | Yes | geth 1.8.23 | **Final release** |

## Ethereum Hard Forks and Minimum Geth Versions

| Fork | Block | Date | Minimum Geth |
|------|-------|------|--------------|
| Frontier | 0 | Jul 30, 2015 | v1.0.0 |
| Frontier Thawing | 200,000 | Sep 7, 2015 | v1.0.0 |
| Homestead | 1,150,000 | Mar 14, 2016 | v1.3.5 |
| DAO Fork | 1,920,000 | Jul 20, 2016 | v1.4.10 |
| Tangerine Whistle | 2,463,000 | Oct 18, 2016 | v1.4.18 |
| Spurious Dragon | 2,675,000 | Nov 22, 2016 | v1.5.0 |
| Byzantium | 4,370,000 | Oct 16, 2017 | v1.7.0 |

**Important**: An old geth version cannot sync past a hard fork it doesn't support. It will stop at the fork block.

## macOS Compatibility

### Go Runtime Issues

Old geth binaries (v1.3.x, v1.4.x) were compiled with Go 1.5/1.6 which has memory allocator issues on macOS 10.13+ (High Sierra and later). This causes crashes with errors like:

```
runtime: MSpanList_Insert
```

### Recommended macOS Versions for Old Geth

| macOS Version | Codename | Release Date | Old Geth Compatibility | Mist Compatibility |
|---------------|----------|--------------|------------------------|-------------------|
| 10.6 | Snow Leopard | Aug 2009 | Unknown - very old | None |
| 10.7 | Lion | Jul 2011 | Best bet for geth 1.3.x | **None** - Mist requires 10.8+ |
| 10.8 | Mountain Lion | Jul 2012 | Good candidate | 0.2.6, 0.3.6, 0.3.7 |
| 10.9 | Mavericks | Oct 2013 | Good candidate | All versions |
| 10.10 | Yosemite | Oct 2014 | Good candidate | All versions |
| 10.11 | El Capitan | Sep 2015 | Good candidate | All versions |
| 10.12 | Sierra | Sep 2016 | **Sweet spot** - usable browsers, likely works | All versions |
| 10.13 | High Sierra | Sep 2017 | Go runtime issues begin | All versions |

**Note**: Mist/Ethereum Wallet requires at least macOS 10.8 (Mountain Lion). Users on Lion (10.7) must use geth console instead.

### macOS Internet Recovery

- **Cmd+Option+R**: Installs latest compatible macOS (usually too new)
- **Cmd+Shift+Option+R**: Installs original macOS the Mac shipped with

To downgrade from a newer version, you must erase the disk first.

### macOS Installer Downloads

For installing macOS 10.12 Sierra (recommended for old geth), download the installer from Apple:

- **macOS Sierra**: https://support.apple.com/en-us/102662

The DMG is ~5GB. For FAT32 USB drives (4GB limit), split with:
```bash
split -b 3G InstallOS.dmg InstallOS.dmg.part.
```

Reassemble on the Mac with:
```bash
cat InstallOS.dmg.part.* > InstallOS.dmg
```

### Browser/TLS Issues on Old macOS

Safari and other browsers on macOS 10.7-10.9 cannot access most modern HTTPS websites due to TLS 1.2/certificate issues. However:

- Ethereum's devp2p protocol (port 30303) uses RLPx encryption, not TLS
- Geth networking should work even if browsers don't
- Use USB drives or SSH/SCP for file transfers

## File Transfer to Old Macs

Since old macOS versions can't browse modern websites:

| Method | Protocol | Notes |
|--------|----------|-------|
| USB Drive | FAT32 | Universal, format with: `mkfs.vfat -F32 /dev/sdX1` |
| SSH/SCP | SSH | Works if SSH enabled on old Mac |
| SMB Share | SMB | May work with SMB1 on old macOS |
| AFP Share | AFP | Native Apple protocol, best compatibility |

## Version Timeline

### Geth Releases (2015-2016)

| Version | Date | Era |
|---------|------|-----|
| v1.0.0 | Jul 30, 2015 | Frontier launch |
| v1.1.0 | Aug 25, 2015 | Frontier |
| v1.1.3 | Sep 10, 2015 | Frontier |
| 1.2.1 | Oct 1, 2015 | Frontier |
| 1.3.3 | Jan 2016 | Frontier/Homestead |
| 1.3.5 | Mar 2016 | Homestead |
| 1.3.6 | Apr 1, 2016 | Homestead |

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

## macOS Binary Downloads

### Frontier Era (Geth 1.1.0)

| Version | Filename | Size | Min macOS | Link |
|---------|----------|------|-----------|------|
| **0.2.6** | `Ethereum-Wallet-darwin-x64-0-2-6.zip` | 53 MB | 10.8 (Mountain Lion) | [Download](https://github.com/ethereum/mist/releases/download/0.2.6/Ethereum-Wallet-darwin-x64-0-2-6.zip) |
| 0.3.6 | `Mist-macosx-0-3-6.zip` | 87 MB | 10.8 (Mountain Lion) | [Download](https://github.com/ethereum/mist/releases/download/0.3.6/Mist-macosx-0-3-6.zip) |
| 0.3.7 | `Ethereum-Wallet-macosx-0-3-7.zip` | 92 MB | 10.8 (Mountain Lion) | [Download](https://github.com/ethereum/mist/releases/download/0.3.7/Ethereum-Wallet-macosx-0-3-7.zip) |

### Homestead Era (Geth 1.3.6)

| Version | Filename | Size | Min macOS | Link |
|---------|----------|------|-----------|------|
| **0.7.4** | `Ethereum-Wallet-macosx-0-7-4.zip` | 79 MB | 10.9 (Mavericks) | [Download](https://github.com/ethereum/mist/releases/download/0.7.4/Ethereum-Wallet-macosx-0-7-4.zip) |
| 0.7.5 | `Ethereum-Wallet-macosx-0-7-5.zip` | 69 MB | 10.9 (Mavericks) | [Download](https://github.com/ethereum/mist/releases/download/0.7.5/Ethereum-Wallet-macosx-0-7-5.zip) |
| 0.7.6 | `Ethereum-Wallet-macosx-0-7-6.zip` | 73 MB | 10.9 (Mavericks) | [Download](https://github.com/ethereum/mist/releases/download/0.7.6/Ethereum-Wallet-macosx-0-7-6.zip) |
| 0.8.0 | `Ethereum-Wallet-macosx-0-8-0.zip` | 69 MB | 10.9 (Mavericks) | [Download](https://github.com/ethereum/mist/releases/download/0.8.0/Ethereum-Wallet-macosx-0-8-0.zip) |

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
- Geth 1.1.0 + Mist 0.2.6: **Working** (Frontier)
- Geth 1.3.6 + Mist 0.7.4: **Working** (Homestead)

## Recommendations for Historical Research

### To Run Frontier-Era Ethereum (Aug-Oct 2015)
- Use Mist 0.2.6 or 0.3.5 with geth 1.1.x
- macOS 10.7-10.12 recommended

### To Run Homestead-Era Ethereum (Mar-Jul 2016)
- Use Mist 0.5.0-0.7.6 with geth 1.3.5-1.4.6
- macOS 10.11-10.12 recommended

### To Run Post-DAO Fork Ethereum (Jul 2016+)
- Use Mist 0.8.1+ with geth 1.4.10+
- macOS 10.12 may still work

## References

- [Mist Releases](https://github.com/ethereum/mist/releases)
- [Go-Ethereum Releases](https://github.com/ethereum/go-ethereum/releases)
- [Homestead Release Blog](https://blog.ethereum.org/2016/02/29/homestead-release)
