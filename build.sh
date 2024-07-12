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
LATEST_PATH="" # Release with complete assets published by official
TARGET=()
SKIP_DEP_CHECK=false
RELEASE=false
PROFILE=""
CLEAR_DATA=false
ARCHIVE=false
ARCHIVE_NAME=""
OPEN=false
OPEN_TARGET=""
NO_CONFIRMATION=false
BUILD_ARGS=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTION]... [CARGO_BUILD_FLAGS]...

Options:
  -h, --help                 Show this help text and exit 
  --phira-home=<path>        Set the Phira repo parent directory (\$PHIRA_HOME)            (default: \$PWD)
  --static-lib-path=<path>   Set the path for FFmpeg static libraries (\$PRPR_AVC_LIBS)    (default: \$PWD/prpr-avc/static-lib)
  --latest-path=<path>       Set the path for the latest release zip file                 (default: \$PWD/out/official-\{linux,windows\}.zip)
  --target=<TRIPLE>          Build for the target triple(s) (Support multiple specifying) (default: x86_64-unknown-linux-gnu)
                                                                                          (    WSL: x86_64-pc-windows-gnu)
  --skip-dep-check           Skip dependency check                                        (default: false)
  -r, --release              Build in release mode, with optimizations                    (default: false)
  --profile=<PROFILE-NAME>   Build with the specified profile                             (default: debug|release)
  --clear-data               Delete login info, chart etc.                                (default: false)
  --archive                  Package into ZIP file                                        (default: false)
  --archive-name=<name|path> Specify name/path of ZIP file                                (default: Phira-\$(date +%s%N)-[profile].zip)
  --open                     Open Phira after building                                    (default: false)
  --open-target=<TRIPLE>     Open Phira with specified target                             (default: See DEFAULT_OPEN_TARGET_PRIORITY)
  -y, --yes                  Disable confirmation prompt                                  (default: false)

CARGO_BUILD_FLAGS:
  Any additional arguments are passed to 'cargo build'.
  For a full list of available options, see 'cargo build --help'
  or visit https://doc.rust-lang.org/cargo/commands/cargo-build.html

DEFAULT_OPEN_TARGET_PRIORITY:
[x86_64-pc-windows-gnu](on WSL) -> rust_default_target -> x86_64-unknown-linux-gnu -> first_target_specified
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
        --open-target=*)
            OPEN_TARGET="${1#*=}"
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
        # log Waiting for target list...
        # AVAILABLE_TRIPLES="$(rustc --print target-list)"
        for triple in "${TARGET[@]}"; do
        #     echo "$AVAILABLE_TRIPLES" | grep -qE "^$triple\$" || error "Unknown target triple: $triple"
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

            if $NO_CONFIRMATION; then
                rust_install
            else
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

    # shellcheck disable=SC2086
    cargo build --bin phira-main $BUILD_ARGS
    log "Build successful!"
    
    for tuple in "${TARGET[@]}"; do
        package_and_archive "$tuple"
    done

    if $OPEN; then
        set_open_target

        log "Opening phira on $OPEN_TARGET..."
        "$PHIRA_HOME/out/$OPEN_TARGET/$PROFILE/phira-main"
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
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    fi

    . "$HOME/.cargo/env"

    log "Rust has been installed"
    log "If you get error, please restart terminal and re-run this script."
}

check_dep() {
    SUDO=""
    if [ "$EUID" -ne 0 ]; then
        SUDO="sudo"
        sudo echo -n || exit 126
    fi

    for triple in "${TARGET[@]}"; do
        case $triple in
        x86_64-unknown-linux-gnu)
            if command -v apt-get >/dev/null; then
                $SUDO apt-get update
                $SUDO apt-get install -y curl zip unzip gcc make perl pkg-config libgtk-3-dev libasound2-dev
            elif command -v pacman >/dev/null; then
                $SUDO pacman -Syu --noconfirm
                $SUDO pacman -S curl wget zip unzip gcc make perl pkg-config gtk3 alsa-lib --noconfirm
            elif command -v dnf >/dev/null; then
                $SUDO dnf install -y curl wget zip unzip gcc make perl pkgconf-pkg-config gtk3-devel alsa-lib-devel
            else
                error "No supported package manager found. Please install a package similar to the following and add the argument \`--skip-dep-check\` when re-executing shell script:
curl zip unzip gcc make pkg-config gtk3-devel alsa-lib"
            fi
            ;;
        x86_64-pc-windows-gnu)
            if command -v apt-get >/dev/null; then
                $SUDO apt-get update
                $SUDO apt-get install -y curl zip unzip gcc make libfindbin-libs-perl gcc-mingw-w64
            elif command -v pacman >/dev/null; then
                $SUDO pacman -Syu --noconfirm
                $SUDO pacman -S curl zip unzip gcc make perl mingw-w64-gcc --noconfirm
            elif command -v dnf >/dev/null; then
                $SUDO dnf install -y curl zip unzip gcc make perl mingw64-gcc
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
    cd "$PHIRA_HOME"
    log "Downloading prebuilt static-lib..."

    curl -LO https://github.com/TeamFlos/phira-docs/raw/main/src/phira_build_guide/prpr-avc.zip

    log "Unzipping..."
    unzip -q prpr-avc.zip

    rm prpr-avc.zip
}

package_and_archive() {
    local tuple=$1
    local output_dir="$PHIRA_HOME/out/$tuple/$PROFILE"

    log "Packaging for $tuple..."

    mkdir -p "$output_dir"

    rm -rf "$output_dir"/{assets,cache,LICENSE,phira-main}

    if $CLEAR_DATA; then
        rm -rf "$output_dir"/data
    fi

    if [[ $triple == *"windows"* ]]; then
        local target_os="windows"
    else
        local target_os="linux"
    fi
    
    if [ ! "$LATEST_PATH" ];then
        LATEST_PATH="official-$target_os.zip"
    fi
    
    # Packaging
    if [ ! -f "$LATEST_PATH" ]; then
        log "Latest release not found."
        log "Downloading latest release..."

        LATEST_PATH="official-$target_os.zip"

        # Get latest release
        curl -s https://api.github.com/repos/TeamFlos/phira/releases/latest |
            grep -o '"browser_download_url": *"[^"]*"' |
            grep "$target_os" |
            grep ".zip\"" |
            sed 's/"browser_download_url": "//' |
            sed 's/"$//' |
            xargs -n 1 curl -o "$LATEST_PATH" -L
    fi

    log "Unzipping latest release..."
    unzip -q "$LATEST_PATH" -d "$output_dir"

    log "Copying and Replacing assets..."
    cp -ru "$PHIRA_HOME/assets/" "$output_dir/assets"

    log "Copying and Replacing binary file..."
    if [[ $target_os == "windows" ]]; then
        cp -u "$PHIRA_HOME/target/$triple/$PROFILE/phira-main.exe" "$output_dir/"
    else
        cp -u "$PHIRA_HOME/target/$triple/$PROFILE/phira-main" "$output_dir/"
    fi

    log "Packaging successful!"
    log "Binary is saved in \`$output_dir/phira-main\`."

    if $ARCHIVE; then
        cd "$output_dir"

        log "Compressing..."
        ARCHIVE_NAME=Phira-$tuple-$PROFILE-$(date +%s%N).zip
        zip -rq "$PHIRA_HOME/$ARCHIVE_NAME" .

        log "Compression successful!"
        log "The zip file is saved in \`$PHIRA_HOME/$ARCHIVE_NAME\`."
    fi
}

search_tuple_in_target() {
    local target_tuple=$1

    for tuple in "${TARGET[@]}"; do
        if [ "$tuple" = "$target_tuple" ]; then
            return 0
        fi
    done

    return 1
}

set_open_target() {
    if [ -n "$OPEN_TARGET" ]; then
        return 0
    fi

    if uname -r | grep -qe "[Mm]icrosoft" && search_tuple_in_target "x86_64-pc-windows-gnu"; then
        OPEN_TARGET="x86_64-pc-windows-gnu"
        return 0
    fi

    local default_target
    default_target=$(rustc -vV | sed -n 's|host: ||p')

    if search_tuple_in_target "$default_target"; then
        OPEN_TARGET="$default_target"
        return 0
    fi

    if search_tuple_in_target "x86_64-unknown-linux-gnu"; then
        OPEN_TARGET="x86_64-unknown-linux-gnu"
        return 0
    fi

    OPEN_TARGET="${TARGET[0]}"
}

main "$@" || exit 1
