## Install Dependencies
### Debian / Ubuntu / Linux Mint
Ensure root or sudo privileges for package installation.
```bash
# For building Linux binary
sudo apt-get install -y curl git unzip gcc make pkg-config libgtk-3-dev libasound2-dev

# For building Windows executable
sudo apt-get install -y curl git unzip gcc make gcc-mingw-w64
```
### Arch Linux / Manjaro
Ensure root or sudo privileges for package installation.
```bash
# For building Linux binary
sudo pacman -Sy curl git wget unzip gcc make pkg-config gtk3 alsa-lib --noconfirm

# For building Windows executable
sudo pacman -Sy curl git wget unzip gcc make mingw-w64-gcc --noconfirm
```
### Fedora
Ensure root or sudo privileges for package installation.
```bash
# For building Linux binary
sudo dnf install -y curl git wget unzip gcc make pkgconf-pkg-config gtk3-devel alsa-lib-devel

# For building Windows executable
sudo dnf install -y curl git wget unzip gcc make mingw64-gcc perl
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
### Build Arguments
See also: [cargo build - The Cargo Book](https://doc.rust-lang.org/cargo/commands/cargo-build.html)  
`-r`, `--release`: Build an optimized version, but takes longer to compile. It's recommended to delete it during development.  
`--target`: Build for the given architecture. If not added, the default architecture will be used, which is determined by the selection during installation. Run `rustc --print target-list` for a list of supported targets. However, phira may not support compilation of certain architectures.
### Optional Features
As of v0.6.2, phira supports compilation with these optional or unfinished features.  
You can enable them via `-F <features>` or `--features <features>`. For example:
```
cargo build --package phira-main --features "phira/chat,phira/event_debug"
```
`phira/closed`: (Unavailable) This feature is closed source and cannot be compiled by most users.  
`phira/video`: (Useless) Video support. For v0.6.2, the feature is a default and neccessary feature of prpr. Turning it on or off doesn't affect the feature.  
`phira/aa`: Enable anti-addiction measures. Due to laws in China, Android users will be required to fill in the name-based authentication system.  
`phira/chat`: Message service in multiplayer rooms. Due to laws in China, the message censorship feature is still to be developed.  
`phira/event_debug`: UML debugging support for event development. The event content will be changed in real time according to the `test.uml` in the same folder as the executable file.

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
## Run
### From File Explorer
Double click to open `phira-main` or `phira-main.exe`
### From Command Line
```
# Linux
./phira-main

# Windows
.\phira-main.exe
```
