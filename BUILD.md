## Install Dependencies
### Debian / Ubuntu / Linux Mint
Ensure root or sudo privileges for package installation.
```bash
# For building Linux binary
sudo apt-get install -y curl git unzip gcc make pkg-config libgtk-3-dev libasound2-dev

# For building Windows executable
sudo apt-get install -y curl git unzip gcc make mingw-w64
```
### Install Rust
```bash
# Manual install
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Auto-install (Specifically for Docker)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Add Rust to PATH if needed
source $HOME/.cargo/env
```
> [!NOTE]
> For other installation methods (e.g. standalone installers), please check [Other Rust Installation Methods](https://forge.rust-lang.org/infra/other-installation-methods.html#standalone).
## Build from Source
### Linux / WSL x86_64
```bash
# Clone the repository
git clone https://github.com/TeamFlos/phira.git

# Get prebuilt avcodec binaries
cd phira/prpr-avc
curl -LO https://github.com/TeamFlos/phira/files/14319201/static-lib.zip
unzip static-lib.zip -d static-lib
rm static-lib.zip

# Prepare to build
cd ..
cargo clean

# Build for Linux x86_64
rustup target add x86_64-unknown-linux-gnu
cargo build --target=x86_64-unknown-linux-gnu --release --package phira-main

# Build for Windows x86_64
rustup target add x86_64-pc-windows-gnu
cargo build --target=x86_64-pc-windows-gnu --release --package phira-main
```
You can find the built binary at `phira/target/[platform]/release/phira-main`.

> [!NOTE]
> The binaries provided by Mivik only support the build of `x86_64-unknown-linux-gnu` and `x86_64-pc-windows-gnu`.  
> If you have a guide or download method for compiling the ffmpeg static library binaries, please feel free to submit a pull request.
## Before running
Some assets have to be obtained from the release. 
For convenience, we put the binary in a example path `phira-dev`. 
### x86_64-unknown-linux-gnu
```bash
mkdir phira-dev
cd phira-dev

# Get latest release
curl -s https://api.github.com/repos/TeamFlos/phira/releases/latest \
  | grep -o '"browser_download_url": *"[^"]*"' \
  | grep "linux" \
  | grep ".zip\"" \
  | sed 's/"browser_download_url": "//' \
  | sed 's/"$//' \
  | xargs -n 1 curl -o latest.zip -L
unzip latest.zip

# Replace binary
cp phira/target/x86_64-unknown-linux-gnu/release/phira-main .
```
### x86_64-pc-windows-gnu
```bash
mkdir phira-dev
cd phira-dev

# Get latest release
curl -s https://api.github.com/repos/TeamFlos/phira/releases/latest \
  | grep -o '"browser_download_url": *"[^"]*"' \
  | grep "windows" \
  | grep ".zip\"" \
  | sed 's/"browser_download_url": "//' \
  | sed 's/"$//' \
  | xargs -n 1 curl -o latest.zip -L
unzip latest.zip

# Replace binary
cp phira/target/x86_64-pc-windows-gnu/release/phira-main.exe .
```
