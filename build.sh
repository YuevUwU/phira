#!/bin/bash
# shellcheck shell=bash

set -e

# Formatting variable
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Default arguments
PHIRA_HOME="$PWD"
PRPR_AVC_LIBS="$PHIRA_HOME/prpr-avc/static-lib"
LATEST_PATH="latest.zip" # Release published by official
TARGET=()
SKIP_DEP_CHECK=false
RELEASE=false
PROFILE=""
CLEAR_DATA=false
ARCHIVE=false
ARCHIVE_NAME=""
OPEN=false
NO_CONFIRMATION=false
BUILD_ARGS=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [cargo_build_flags]

Options:
  -h, --help                 Show this help text and exit 
  --phira-home=<path>        Set the Phira repo parent directory (\$PHIRA_HOME)            (default: \$PWD)
  --static-lib-path=<path>   Set the path for FFmpeg static libraries (\$PRPR_AVC_LIBS)    (default: \$PWD/prpr-avc/static-lib)
  --latest-path=<path>       Set the path for the latest release zip file                 (default: \$PWD/out/latest.zip)
  --target=<TRIPLE>          Build for the target triple(s) (Support multiple specifying) (default: x86_64-unknown-linux-gnu)
                                                                                          (    WSL: x86_64-pc-windows-gnu)
  --skip-dep-check           Skip dependency check                                        (default: false)
  -r, --release              Build in release mode, with optimizations                    (default: false)
  --profile=<PROFILE-NAME>   Build with the specified profile                             (default: debug|release)
  --clear-data               Delete login info, chart etc.                                (default: false)
  --archive                  Package into ZIP file                                        (default: false)
  --archive-name=<name|path> Specify name/path of ZIP file                                (default: Phira-\$(date +%s%N)-[profile].zip)
  --open                     Open Phira after building                                    (default: false)
  -y, --yes                  Disable confirmation prompt                                  (default: false)

cargo_build_flags:
  Any additional arguments are passed to 'cargo build'.
  For a full list of available options, see 'cargo build --help'
  or visit https://doc.rust-lang.org/cargo/commands/cargo-build.html
EOF
}

main() {
    # Parse primary commands
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
        -h | --help)
            usage
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
        --target=*)
            TARGET+=("${1#*=}")
            shift
            ;;
        --skip-dep-check)
            SKIP_DEP_CHECK=true
            shift
            ;;
        -r | --release)
            RELEASE=true
            shift
            ;;
        --profile=*)
            PROFILE="${1#*=}"
            shift
            ;;
        --clear-data)
            CLEAR_DATA=true
            shift
            ;;
        --archive)
            ARCHIVE=true
            shift
            ;;
        --archive-name=*)
            ARCHIVE_NAME="${1#*=}"
            shift
            ;;
        --open)
            OPEN=true
            shift
            ;;
        -y | --yes)
            NO_CONFIRMATION=true
            shift
            ;;
        *)
            BUILD_ARGS+=" $1"
            shift
            ;;
        esac
    done

    if [ -z "$PROFILE" ]; then
        if [ "$RELEASE" = true ]; then
            BUILD_ARGS+=" --release"
            PROFILE="release"
        else
            PROFILE="debug"
        fi
    else
        BUILD_ARGS+=" --profile=$PROFILE"
    fi

    # Default target
    if ! [ ${#TARGET[@]} -ne 0 ]; then
        if uname -r | grep -qe "[Mm]icrosoft"; then
            TARGET=("x86_64-pc-windows-gnu")
        else
            TARGET=("x86_64-unknown-linux-gnu")
        fi
        BUILD_ARGS+=" --target=${TARGET[0]}"
    else
        log Waiting for target list...
        AVAILABLE_TRIPLES="$(rustc --print target-list)"
        for triple in "${TARGET[@]}"; do
            echo "$AVAILABLE_TRIPLES" | grep -qE "^$triple\$" || error "Unknown target triple: $triple"
            BUILD_ARGS+=" --target=$triple"
        done
    fi

    TARGET_COMMA=$(join_arr , "${TARGET[@]}")
    log "Build target(s): $TARGET_COMMA"

    if ! $SKIP_DEP_CHECK; then
        log "Check dependencies..."

        check_dep

        # Check if Rust is installed
        if ! command -v rustc >/dev/null; then

            if ! NO_CONFIRMATION; then
                rust_install
            fi

            echo -ne "Rust is not installed. Do you want to install Rust now? (Y/n)"
            read -r install_rust
            case $install_rust in
            [Yy]*)
                rust_install
                ;;
            [Nn]* | *)
                log "Rust installation aborted."
                exit 0
                ;;
            esac
        fi
    fi

    # Check FFmpeg library support basically
    for triple in "${TARGET[@]}"; do
        if [ ! -d "$PRPR_AVC_LIBS/$triple" ]; then
            log "FFmpeg static libraries not found."
            get_static_libs
            break
        fi
    done

    for triple in "${TARGET[@]}"; do
        if [ ! -d "$PRPR_AVC_LIBS/$triple" ]; then
            error "The existing static-lib does not support $triple. Please build manually from FFmpeg source code and put it into $PRPR_AVC_LIBS/$triple"
        fi
    done

    # Prepare to build
    cd "$PHIRA_HOME" || exit

    # Build for Linux x86_64
    log "Confirming toolchain has been downloaded..."
    for triple in "${TARGET[@]}"; do
        rustup target add "$triple"
    done

    log "Build args: $BUILD_ARGS"
    log "Building..."
    cargo build --bin phira-main $BUILD_ARGS
    
    OUTPUT_DIR="$PHIRA_HOME/out/$PROFILE"
    
    log "Packaging..."
    mkdir -p "$OUTPUT_DIR"/\{"$TARGET_COMMA"\}
    rm -rf "$OUTPUT_DIR"/{assets,cache,LICENSE,phira-main}

    if $CLEAR_DATA; then
        rm -rf "$OUTPUT_DIR"/data
    fi

    # Packaging
    if [ ! -f "$LATEST_PATH" ]; then
        log "Latest release not found."
        log "Downloading latest release..."

        # Get latest release
        curl -s https://api.github.com/repos/TeamFlos/phira/releases/latest |
            grep -o '"browser_download_url": *"[^"]*"' |
            grep "linux" |
            grep ".zip\"" |
            sed 's/"browser_download_url": "//' |
            sed 's/"$//' |
            xargs -n 1 curl -o "$LATEST_PATH" -L
    fi

    log "Unzipping latest release..."
    unzip -q "$LATEST_PATH" -d "$OUTPUT_DIR"

    log "Copying and Replacing assets..."
    cp -ru "$PHIRA_HOME/assets/" "$OUTPUT_DIR/assets" || exit 1

    for triple in "${TARGET[@]}"; do
        log "Copying and Replacing binary file..."
        cp -u "$PHIRA_HOME/target/$triple/$PROFILE/phira-main" "$OUTPUT_DIR/phira-main" || exit 1
    done

    log "Packaging successful!"

    log "Build successful!"
    log "Binary is saved in \`$OUTPUT_DIR/phira-main\`."

    if $ARCHIVE; then
        cd "$OUTPUT_DIR"

        log "Compressing..."
        ARCHIVE_NAME=Phira-$(date +%s%N)-$PROFILE.zip
        zip -rq "$PHIRA_HOME/$ARCHIVE_NAME" .

        log "Compression successful!"
        log "The zip file is saved in \`$PHIRA_HOME/$ARCHIVE_NAME\`."
    fi

    if $OPEN; then
        log "Opening phira..."
        "$OUTPUT_DIR/phira-main"
    fi
}

error() {
    local msg=$*

    echo -e "${YELLOW}$msg${NC}"
    exit 1
}

log() {
    local msg=$*

    echo -e "${GREEN}$msg${NC}"
}

join_arr() {
  local IFS="$1"
  shift
  echo "$*"
}

rust_install() {
    log "Installing Rust..."

    if $NO_CONFIRMATION; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -- -y
    fi

    # TODO: if user install rust in custom path

    source "$HOME/.bashrc"

    log "Rust has been installed"
    log "If you get error, please restart terminal and re-run this script."
}

check_dep() {
    sudo echo -n || exit 126

    for triple in "${TARGET[@]}"; do
        case $triple in
        x86_64-unknown-linux-gnu)
            if command -v apt-get >/dev/null; then
                sudo apt update
                sudo apt-get install -y curl zip unzip gcc make pkg-config libgtk-3-dev libasound2-dev
            elif command -v pacman >/dev/null; then
                sudo pacman -Sy curl wget zip unzip gcc make pkg-config gtk3 alsa-lib --noconfirm
            elif command -v dnf >/dev/null; then
                sudo dnf install -y curl wget zip unzip gcc make pkgconf-pkg-config gtk3-devel alsa-lib-devel
            else
                error "No supported package manager found. Please install a package similar to the following and add the argument \`--skip-dep-check\` when re-executing shell script:
curl zip unzip gcc make pkg-config gtk3-devel alsa-lib"
            fi
            ;;
        x86_64-pc-windows-gnu)
            if command -v apt-get >/dev/null; then
                sudo apt update
                sudo apt-get install -y curl zip unzip gcc make gcc-mingw-w64
            elif command -v pacman >/dev/null; then
                sudo pacman -Sy curl zip unzip gcc make mingw-w64-gcc --noconfirm
            elif command -v dnf >/dev/null; then
                sudo dnf install -y curl zip unzip gcc make mingw64-gcc perl
            else
                error "No supported package manager found. Please install a package similar to the following and add the argument \`--skip-dep-check\` when re-executing shell script:
curl zip unzip gcc make mingw64-gcc perl"
            fi
            ;;
        *)
            error "This script does not yet know the dependencies required by $triple, please install the dependencies manually and add the argument \`--skip-dep-check\` when re-executing shell script"
            ;;
        esac
    done
}

get_static_libs() {
    # Get prebuilt avcodec binaries
    mkdir -p "$PRPR_AVC_LIBS"
    cd "$PRPR_AVC_LIBS" || exit

    log "Downloading prebuilt static-lib..."

    curl -LO https://github.com/TeamFlos/phira-docs/raw/main/src/phira_build_guide/prpr-avc.zip

    log "Unzipping..."
    unzip -q static-lib.zip

    rm static-lib.zip
}

main "$@" || exit 1
