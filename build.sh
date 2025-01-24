#!/bin/bash
# shellcheck shell=bash

set -eo pipefail

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
BUILD_ARGS=()

TEMPDIR=""

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

error() {
    echo -e "${YELLOW}Error: $*${NC}" >&2
    exit 1
}

log() {
    echo -e "${GREEN}$*${NC}"
}

confirm_action() {
    if [[ "$NO_CONFIRMATION" = true ]]; then
        return 0
    fi
    read -rp "$1 (y/N): " response
    [[ ${response,,} =~ ^y(es)?$ ]]
}

cleanup() {
    if [[ -n "$TEMPDIR" && -d "$TEMPDIR" ]]; then
        rm -rf "$TEMPDIR"
    fi
}

trap cleanup EXIT

main() {
    # Parse primary commands
    while [[ $# -gt 0 ]]; do
        case $1 in
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
            BUILD_ARGS+=("$1")
            shift
            ;;
        esac
    done

    if [[ -z "$PROFILE" ]]; then
        if [[ "$RELEASE" = true ]]; then
            BUILD_ARGS+=("--release")
            PROFILE="release"
        else
            PROFILE="debug"
        fi
    else
        BUILD_ARGS+=("--profile=$PROFILE")
    fi

    # Default target
    if [[ ${#TARGET[@]} -eq 0 ]]; then
        if uname -r | grep -qe "[Mm]icrosoft"; then
            TARGET=("x86_64-pc-windows-gnu")
        else
            TARGET=("x86_64-unknown-linux-gnu")
        fi
        BUILD_ARGS+=("--target=${TARGET[0]}")
    else
        for triple in "${TARGET[@]}"; do
            BUILD_ARGS+=("--target=$triple")
        done
    fi

    TARGET_COMMA=$(IFS=,; echo "${TARGET[*]}")
    log "Build target(s): $TARGET_COMMA"

    if [[ "$SKIP_DEP_CHECK" = false ]]; then
        log "Check dependencies..."
        check_dep
        check_rust
        check_nightly
    fi

    # Check FFmpeg library support
    for triple in "${TARGET[@]}"; do
        if [[ ! -d "$PRPR_AVC_LIBS/$triple" ]]; then
            log "FFmpeg static libraries not found."
            get_static_libs
            break
        fi
    done

    for triple in "${TARGET[@]}"; do
        [[ -d "$PRPR_AVC_LIBS/$triple" ]] || error "The existing static-lib does not support $triple. Please build manually from FFmpeg source code and put it into $PRPR_AVC_LIBS/$triple"
    done

    # Prepare to build
    cd "$PHIRA_HOME" || error "Failed to change directory to $PHIRA_HOME."

    # Confirm toolchain download
    log "Confirming toolchain has been downloaded..."
    for triple in "${TARGET[@]}"; do
        rustup +nightly target add "$triple" || error "Failed to add target $triple."
    done

    log "Build args: ${BUILD_ARGS[*]}"
    log "Building..."

    # Build
    cargo +nightly build --bin phira-main "${BUILD_ARGS[@]}" || error "Build failed."
    log "Build successful!"
    
    for triple in "${TARGET[@]}"; do
        package_and_archive "$triple"
    done

    if [[ "$OPEN" = true ]]; then
        set_open_target

        log "Opening phira on $OPEN_TARGET..."

        # Open Linux executable first for debugging if exists
        "$PHIRA_HOME/out/$OPEN_TARGET/$PROFILE/phira-main" || "$PHIRA_HOME/out/$OPEN_TARGET/$PROFILE/phira-main.exe"
    fi
}

check_dep() {
    if [[ $EUID -ne 0 ]]; then
        if ! sudo -v; then
            error "This script requires sudo privileges. Please run with sudo or grant sudo permissions."
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi

    for triple in "${TARGET[@]}"; do
        case $triple in
        x86_64-unknown-linux-gnu)
            if command -v apt-get >/dev/null; then
                $SUDO apt-get update || error "Failed to update package lists."
                $SUDO apt-get install -y curl zip unzip gcc make perl pkg-config libgtk-3-dev libasound2-dev || error "Failed to install required packages."
            elif command -v pacman >/dev/null; then
                $SUDO pacman -Syu --noconfirm || error "Failed to update system."
                $SUDO pacman -S curl wget zip unzip gcc make perl pkg-config gtk3 alsa-lib --noconfirm || error "Failed to install required packages."
            elif command -v dnf >/dev/null; then
                $SUDO dnf install -y curl wget zip unzip gcc make perl pkgconf-pkg-config gtk3-devel alsa-lib-devel || error "Failed to install required packages."
            else
                error "No supported package manager found. Please install the following packages manually and add the argument \`--skip-dep-check\` when re-executing shell script: curl zip unzip gcc make perl pkg-config libgtk-3-dev libasound2-dev"
            fi
            ;;
        x86_64-pc-windows-gnu)
            if command -v apt-get >/dev/null; then
                $SUDO apt-get update || error "Failed to update package lists."
                $SUDO apt-get install -y curl zip unzip gcc make libfindbin-libs-perl gcc-mingw-w64 || error "Failed to install required packages."
            elif command -v pacman >/dev/null; then
                $SUDO pacman -Syu --noconfirm || error "Failed to update system."
                $SUDO pacman -S curl zip unzip gcc make perl mingw-w64-gcc --noconfirm || error "Failed to install required packages."
            elif command -v dnf >/dev/null; then
                $SUDO dnf install -y curl zip unzip gcc make perl mingw64-gcc || error "Failed to install required packages."
            else
                error "No supported package manager found. Please install the following packages manually and add the argument \`--skip-dep-check\` when re-executing shell script: curl zip unzip gcc make perl (libfindbin-libs-perl) gcc-mingw-w64"
            fi
            ;;
        *)
            error "This script does not yet know the dependencies required by $triple, please install the dependencies manually and add the argument \`--skip-dep-check\` when re-executing shell script"
            ;;
        esac
    done
}

check_rust() {
    if ! command -v rustc >/dev/null; then
        if [[ "$NO_CONFIRMATION" = true ]] || confirm_action "Rust is not installed. Do you want to install Rust now?"; then
            rust_install
        else
            error "Rust is required but not installed. Aborting."
        fi
    fi
}

rust_install() {
    log "Installing Rust..."

    TEMPDIR=$(mktemp -d)
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$TEMPDIR/rustup.sh" || error "Failed to download Rust installer."
    
    if [[ "$NO_CONFIRMATION" = true ]]; then
        sh "$TEMPDIR/rustup.sh" -y || error "Rust installation failed."
    else
        sh "$TEMPDIR/rustup.sh" || error "Rust installation failed."
    fi

    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"

    log "Rust has been installed."
    log "If you get an error, please restart the terminal and re-run this script."
}

check_nightly() {
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
    
    if ! rustup toolchain list | grep -q 'nightly'; then
        if [[ "$NO_CONFIRMATION" = true ]] || confirm_action "Rust nightly is not installed. Do you want to install Rust nightly now?"; then
            rust_nightly_install
        else
            error "Rust nightly is required but not installed. Aborting."
        fi
    fi
}

rust_nightly_install() {
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"

    log "Installing Rust nightly..."

    if [[ "$NO_CONFIRMATION" = true ]]; then
        rustup install nightly || error "Rust nightly installation failed."
    else
        rustup install nightly || error "Rust nightly installation failed."
    fi

    log "Rust nightly has been installed."
    log "If you get an error, please restart the terminal and re-run this script."
}

get_static_libs() {
    cd "$PHIRA_HOME" || error "Failed to change directory to $PHIRA_HOME."
    log "Downloading prebuilt static-lib..."

    curl -LO https://github.com/TeamFlos/phira-docs/raw/main/src/phira_build_guide/prpr-avc.zip || error "Failed to download prpr-avc.zip."

    log "Unzipping..."
    unzip -q prpr-avc.zip || error "Failed to unzip prpr-avc.zip."

    rm prpr-avc.zip || log "Warning: Failed to remove prpr-avc.zip."
}

package_and_archive() {
    local triple=$1
    local output_dir="$PHIRA_HOME/out/$triple/$PROFILE"

    log "Packaging for $triple..."

    mkdir -p "$output_dir" || error "Failed to create output directory."

    if confirm_action "This will remove existing files in $output_dir. Are you sure?"; then
        rm -rf "$output_dir"/{assets,cache,LICENSE,phira-main}
    else
        log "Packaging cancelled by user."
        return
    fi

    if [[ "$CLEAR_DATA" = true ]]; then
        rm -rf "$output_dir"/data || log "Warning: Failed to remove data directory."
    fi

    local target_os
    if [[ $triple == *"windows"* ]]; then
        target_os="windows"
    else
        target_os="linux"
    fi
    
    if [[ -z "$LATEST_PATH" ]]; then
        LATEST_PATH="official-$target_os.zip"
    fi
    
    # Packaging
    if [[ ! -f "$LATEST_PATH" ]]; then
        log "Latest release not found. Downloading..."

        LATEST_PATH="official-$target_os.zip"

        # Get latest release
        curl -s https://api.github.com/repos/TeamFlos/phira/releases/latest |
            grep -o '"browser_download_url": *"[^"]*"' |
            grep "$target_os" |
            grep ".zip\"" |
            sed 's/"browser_download_url": "//' |
            sed 's/"$//' |
            xargs -n 1 curl -o "$LATEST_PATH" -L || error "Failed to download latest release."
    fi

    log "Unzipping latest release..."
    unzip -q "$LATEST_PATH" -d "$output_dir" || error "Failed to unzip latest release."

    log "Copying and Replacing assets..."
    cp -rf "$PHIRA_HOME/assets" "$output_dir/" || error "Failed to copy assets."

    log "Copying and Replacing binary file..."
    if [[ $target_os == "windows" ]]; then
        cp -u "$PHIRA_HOME/target/$triple/$PROFILE/phira-main.exe" "$output_dir/" || error "Failed to copy binary file."
    else
        cp -u "$PHIRA_HOME/target/$triple/$PROFILE/phira-main" "$output_dir/" || error "Failed to copy binary file."
    fi

    log "Packaging successful!"
    log "Binary is saved in \`$output_dir/phira-main\`."

    if [[ "$ARCHIVE" = true ]]; then
        cd "$output_dir" || error "Failed to change directory to $output_dir."

        log "Compressing..."
        ARCHIVE_NAME=${ARCHIVE_NAME:-"Phira-$triple-$PROFILE-$(date +%s%N).zip"}
        zip -rq "$PHIRA_HOME/$ARCHIVE_NAME" . || error "Failed to create archive."

        log "Compression successful!"
        log "The zip file is saved in \`$PHIRA_HOME/$ARCHIVE_NAME\`."
    fi
}

search_triple_in_target() {
    local target_triple=$1

    for triple in "${TARGET[@]}"; do
        if [[ "$triple" = "$target_triple" ]]; then
            return 0
        fi
    done

    return 1
}

set_open_target() {
    if [[ -n "$OPEN_TARGET" ]]; then
        return 0
    fi

    if uname -r | grep -qe "[Mm]icrosoft" && search_triple_in_target "x86_64-pc-windows-gnu"; then
        OPEN_TARGET="x86_64-pc-windows-gnu"
        return 0
    fi

    local default_target
    default_target=$(rustc -vV | sed -n 's|host: ||p')

    if search_triple_in_target "$default_target"; then
        OPEN_TARGET="$default_target"
        return 0
    fi

    if search_triple_in_target "x86_64-unknown-linux-gnu"; then
        OPEN_TARGET="x86_64-unknown-linux-gnu"
        return 0
    fi

    OPEN_TARGET="${TARGET[0]}"
}

main "$@" || exit 1
