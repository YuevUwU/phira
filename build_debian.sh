#!/bin/bash

set -e

# Formatting variable
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'


# Default arguments
PHIRA_HOME="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
OUTPUT_DIR="$PHIRA_HOME/out"    # TODO: Not recommend to modify it or you need to modify `.gitignore`
PRPR_AVC_LIBS="$PHIRA_HOME/prpr-avc/static-lib"
LATEST_PATH="latest.zip"    # Release published by official
SKIP_DEP_CHECK=false
NO_CARGO_CLEAN=false
RELEASE=false
BIN_PATH="$PHIRA_HOME/target/x86_64-unknown-linux-gnu/debug/phira-main"
OPEN=false
build_args=""
# TODO: check if variable is legal

HELPER_STRING="Usage: $(basename "$0") [options]

Options:
  -h, --help                 Show this help text and exit 
  --phira-home=<path>        Set the Phira repo parent directory (\$PHIRA_HOME)           (default: $PHIRA_HOME)
  --static-lib-path=<path>   Set the path for FFmpeg static libraries (\$PRPR_AVC_LIBS)   (default: \$PHIRA_HOME/prpr-avc/static-lib)
  --latest-path=<path>       Set the path for the latest release zip file                 (default: \$PHIRA_HOME/out/latest.zip)
  --skip-dep-check           Skip dependency check                                        (default: disabled)
  --no-cargo-clean           Skip cleaning cargo cache                                    (default: disabled)
  -r, --release              Build in release mode and generate zip file                  (default: disabled)
  --open                     Open Phira after building                                    (default: disabled)
"

# Parse primary commands
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        -h|--help)
            echo "$HELPER_STRING"
            exit 0
            ;;
        --phira-home=*)
            PHIRA_HOME="${1#*=}"
            shift
            ;;
        --static-lib-path=*)
            PRPR_AVC_LIBS="${1#*=}"
            shift
            ;;
        --latest-path=*)
            LATEST_PATH="${1#*=}"
            shift
            ;;
        --skip-dep-check)
            SKIP_DEP_CHECK=true
            shift
            ;;
        --no-cargo-clean)
            NO_CARGO_CLEAN=true
            shift
            ;;
        -r|--release)
            RELEASE=true
            BIN_PATH="$PHIRA_HOME/target/x86_64-unknown-linux-gnu/release/phira-main"
            shift
            ;;
        --open)
            OPEN=true
            shift
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [ "$RELEASE" = true ]; then
    build_args="$build_args --release"
fi

if ! $SKIP_DEP_CHECK; then
    echo -e "${GREEN}Check dependencies...${NC}"

    # Update Package Info
    # sudo apt-get update

    # Install Dependencies
    sudo apt-get install -y curl git zip unzip gcc make pkg-config libgtk-3-dev libasound2-dev || echo -e "${YELLOW}Try to run \`sudo apt-get update\` to update package list or \`sudo apt -f install\` to fix bad package.${NC}"

    # Check if Rust is installed
    if ! command -v rustc > /dev/null; then
        # read -rp "${GREEN}Rust is not installed. Do you want to install Rust now? (Y/n)" install_rust
        echo -ne "${GREEN}Rust is not installed. Do you want to install Rust now? (Y/n) ${NC}"
        read -r install_rust
        case $install_rust in
            [Yy]* )
                echo -e "${GREEN}Installing Rust...${NC}"
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

                # TODO: if user install rust in custom path
                
                source "$HOME/.cargo/env"

                echo -e "${GREEN}Installing Rust nightly...${NC}"
                rustup toolchain install nightly

                echo -e "${GREEN}Rust has been installed${NC}"
                echo -e "${YELLOW}If you get error, please restart terminal and re-run this script.${NC}"
                ;;
            [Nn]* | * )
                echo -e "${GREEN}Rust installation aborted${NC}"
                exit 0
                ;;
        esac
    fi
fi

if [ ! -d "$PRPR_AVC_LIBS/x86_64-unknown-linux-gnu" ]; then
    echo -e "${GREEN}FFmpeg static libraries not found.${NC}"

    # Get prebuilt avcodec binaries
    mkdir -p "$PRPR_AVC_LIBS"
    cd "$PRPR_AVC_LIBS" || exit

    echo -e "${GREEN}Downloading prebuilt static-lib...${NC}"

    curl -LO https://github.com/TeamFlos/phira/files/14319201/static-lib.zip

    echo -e "${GREEN}Unzipping...${NC}"
    unzip -q static-lib.zip
    
    rm static-lib.zip
fi

# Prepare to build
cd "$PHIRA_HOME" || exit

if ! $NO_CARGO_CLEAN; then
    echo -e "${GREEN}Cleaning cargo cache...${NC}"

    cargo clean
fi

# Build for Linux x86_64
echo -e "${GREEN}Confirming toolchain has been downloaded...${NC}"
rustup +nightly target add x86_64-unknown-linux-gnu

echo -e "${GREEN}Building...${NC}"
cargo +nightly build --target=x86_64-unknown-linux-gnu --package phira-main $build_args

echo -e "${GREEN}Packaging...${NC}"

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR"/{assets,cache,LICENSE,phira-main}

# Packaging
if [ ! -f "$LATEST_PATH" ]; then
    echo -e "${GREEN}Latest release not found.${NC}"
    echo -e "${GREEN}Downloading latest release...${NC}"

    # Get latest release
    curl -s https://api.github.com/repos/TeamFlos/phira/releases/latest \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | grep "linux" \
    | grep ".zip\"" \
    | sed 's/"browser_download_url": "//' \
    | sed 's/"$//' \
    | xargs -n 1 curl -o "$LATEST_PATH" -L
fi

echo -e "${GREEN}Unzipping latest release...${NC}"
unzip -q "$LATEST_PATH" -d "$OUTPUT_DIR"

echo -e "${GREEN}Copying and Replacing assets...${NC}"
# cp -rf "$PHIRA_HOME/assets/" "$OUTPUT_DIR/assets"
rsync -ahIr --info=progress2 "$PHIRA_HOME/assets/" "$OUTPUT_DIR/assets"

echo -e "${GREEN}Copying and Replacing binary file...${NC}"
# cp -f "$PHIRA_HOME/target/x86_64-unknown-linux-gnu/debug/phira-main" "$OUTPUT_DIR/phira-main"
rsync -ahI --info=progress2 "$BIN_PATH" "$OUTPUT_DIR/phira-main"

echo "Packaging successful!"

echo -e "${GREEN}Build successful!${NC}"
echo -e "${GREEN}Binary is saved in \`$OUTPUT_DIR/phira-main\`.${NC}"

if $RELEASE; then
    cd "$OUTPUT_DIR"
    
    echo -e "${GREEN}Compressing...${NC}"
    zip_name="Phira-$(date +%s%N).zip"
    zip -rq "$PHIRA_HOME/$zip_name" .

    echo -e "${GREEN}Compression successful!${NC}"
    echo -e "${GREEN}The zip file is saved in \`$PHIRA_HOME/$zip_name\`.${NC}"
fi

if $OPEN; then
    echo -e "${GREEN}Opening phira...${NC}"
    "$OUTPUT_DIR/phira-main"
fi