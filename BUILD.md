## Prerequisites
### Debian / Ubuntu / Linux Mint
You may need to run as root or add the prefix `sudo`.
```
apt-get install -y curl git unzip gcc make pkg-config libgtk-3-dev libasound2-dev
```
## Build from Source
### WSL
See [Linux](#linux) section below.
### Linux
#### Install Rust with Rustup
##### Manual install
```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```
##### Auto-install (Specifically for Docker)
```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
```
##### Other
For other installation (e.g. standalone installers), please check [Other Rust Installation Methods](https://forge.rust-lang.org/infra/other-installation-methods.html#standalone).
#### Clone the Repository
```
git clone https://github.com/TeamFlos/phira.git
```
#### Download Prebuilt avcodec Binaries
Locate to `phira/prpr-avc` and Run:
```
curl -LO https://github.com/TeamFlos/phira/files/14319201/static-lib.zip
unzip static-lib.zip -d static-lib
rm static-lib.zip
```
#### Build
Locate to `phira` and Run:
```
cargo clean
cargo build --release --package phira-main
```
You can find the built binary at `phira/target/[target-platform]/release/phira-main`.
For example, `[target-platform]` can be `x86_64-unknown-linux-gnu`
## Run
### Linux
Some assets have to get from release. For convenience, we put the binary in a path `phira-dev`. 
#### Download Latest Release
```
cd phira-dev
curl -s https://api.github.com/repos/TeamFlos/phira/releases/latest \
  | grep -o '"browser_download_url": *"[^"]*"' \
  | grep "linux" \
  | grep ".zip\"" \
  | sed 's/"browser_download_url": "//' \
  | sed 's/"$//' \
  | xargs -n 1 curl -o latest.zip -L
```
#### Final Step
```
unzip latest.zip
cp phira/target/[target-platform]/release/phira-main .
```
