#!/bin/sh
# Helix Editor Installer
# Downloads and installs the latest Helix editor release from GitHub

{ \unalias command; \unset -f command; } >/dev/null 2>&1
tdir=''
cleanup() {
    [ -n "$tdir" ] && {
        command rm -rf "$tdir"
        tdir=''
    }
}

die() {
    cleanup
    printf "\033[31m%s\033[m\n\r" "$*" > /dev/stderr;
    exit 1;
}

detect_network_tool() {
    if command -v curl 2> /dev/null > /dev/null; then
        fetch() {
            command curl -fL "$1"
        }
        fetch_quiet() {
            command curl -fsSL "$1"
        }
    elif command -v wget 2> /dev/null > /dev/null; then
        fetch() {
            command wget -O- "$1"
        }
        fetch_quiet() {
            command wget --quiet -O- "$1"
        }
    else
        die "Neither curl nor wget available, cannot download Helix"
    fi
}

detect_os_arch() {
    os=""
    arch=""
    case "$(command uname -s)" in
        'Darwin') os="macos";;
        'Linux') os="linux";;
        *) die "Helix binaries are not available for $(command uname -s)";;
    esac
    
    case "$(command uname -m)" in
        x86_64) arch="x86_64";;
        aarch64) arch="aarch64";;
        arm64) arch="aarch64";;
        *) die "Helix binaries not available for architecture $(command uname -m)";;
    esac
}

expand_tilde() {
    tilde_less="${1#\~/}"
    [ "$1" != "$tilde_less" ] && tilde_less="$HOME/$tilde_less"
    printf '%s' "$tilde_less"
}

parse_args() {
    dest='~/.local'
    launch='y'
    installer=''
    while :; do
        case "$1" in
            dest=*) dest="${1#*=}";;
            launch=*) launch="${1#*=}";;
            installer=*) installer="${1#*=}";;
            "") break;;
            *) die "Unrecognized command line option: $1";;
        esac
        shift
    done
    dest=$(expand_tilde "${dest}")
    [ "$launch" != "y" -a "$launch" != "n" ] && die "Unrecognized command line option: launch=$launch"
}

get_latest_version() {
    version=$(fetch_quiet "https://api.github.com/repos/helix-editor/helix/releases/latest" | \
              command grep '"tag_name":' | \
              command sed -E 's/.*"([^"]+)".*/\1/' | \
              command sed 's/^v//')
    [ $? -ne 0 -o -z "$version" ] && die "Could not get Helix latest release version"
    printf '%s' "$version"
}

get_arch_platform_suffix() {
    case "${os}-${arch}" in
        linux-x86_64) suffix="x86_64-linux";;
        linux-aarch64) suffix="aarch64-linux";;
        macos-x86_64) suffix="x86_64-macos";;
        macos-aarch64) suffix="aarch64-macos";;
        *) die "No binary available for ${os}-${arch}";;
    esac
    printf '%s' "$suffix"
}

detect_archive_type() {
    case "${os}" in
        linux) archive="tar.xz";;
        macos) archive="tar.xz";;
        *) archive="tar.xz";;
    esac
    printf '%s' "$archive"
}

get_download_url() {
    base_version=$(get_latest_version)
    arch_platform=$(get_arch_platform_suffix)
    archive_ext=$(detect_archive_type)
    # Export base_version for use in other functions
    export base_version
    printf '%s' "https://github.com/helix-editor/helix/releases/download/${base_version}/helix-${base_version}-${arch_platform}.${archive_ext}"
}

download_installer() {
    tdir=$(command mktemp -d "/tmp/helix-install-XXXXXXXXXXXX")
    [ "$installer_is_file" != "y" ] && {
        printf '%s\n\n' "Downloading from: $url"
        installer="$tdir/helix-local.tar.xz"
        fetch "$url" > "$installer" || die "Failed to download: $url"
        installer_is_file="y"
    }
}

ensure_dest() {
    printf "%s\n" "Installing to $dest"
    # Remove existing helix directory and recreate
    command rm -rf "$dest/helix" || die "Failed to remove existing helix directory"
    command mkdir -p "$dest/helix" || die "Failed to mkdir -p $dest/helix"
    # Ensure bin directory exists for symlink
    command mkdir -p "$dest/bin" || die "Failed to mkdir -p $dest/bin"
}

install_helix() {
    # Extract archive
    command mkdir -p "$tdir/mp"
    command tar -C "$tdir/mp" "-xJf" "$installer" || die "Failed to extract Helix tarball"
    
    # Helix archives extract to a directory named like "helix-25.07.1-x86_64-linux"
    arch_platform=$(get_arch_platform_suffix)
    # Replace underscores with hyphens in arch_platform for directory naming
    platform_with_hyphens=$(printf '%s' "$arch_platform" | command sed 's/_/-/g')
    expected_name="helix-v${base_version}-${platform_with_hyphens}"
    
    extracted_dir="$tdir/mp/${expected_name}"
    
    # Fallback: try to find any directory with the hx binary
    if [ ! -d "$extracted_dir" ]; then
        for dir in "$tdir/mp"/*; do
            if [ -d "$dir" ] && [ -f "$dir/hx" ]; then
                extracted_dir="$dir"
                printf "Found alternative directory: %s\n" "$extracted_dir"
                break
            fi
        done
    fi
    
    if [ ! -d "$extracted_dir" ] || [ ! -f "$extracted_dir/hx" ]; then
        printf "Looking for extracted Helix in: %s\n" "$tdir/mp"
        command ls -la "$tdir/mp" || true
        if [ -d "$extracted_dir" ]; then
            printf "Contents of %s:\n" "$extracted_dir"
            command ls -la "$extracted_dir" || true
        fi
        die "Could not find Helix binary in expected location: $extracted_dir"
    fi
    
    printf "Found Helix directory: %s\n" "$extracted_dir"
    
    # Copy entire extracted directory to helix directory
    command cp -r "$extracted_dir/"* "$dest/helix/" || die "Failed to copy Helix files"
    
    # Create symlink from helix/hx to bin/hx
    if [ -f "$dest/helix/hx" ]; then
        command ln -sf "$dest/helix/hx" "$dest/bin/hx" || die "Failed to create symlink"
    else
        die "Helix binary not found in $extracted_dir"
    fi
}

exec_helix() {
    exec "$dest/bin/hx" "--version"
}

main() {
    detect_os_arch
    parse_args "$@"
    detect_network_tool
    
    printf '%s\n' "Helix Editor Installer"
    printf '%s\n' "Detected platform: ${os}-${arch}"
    
    url=$(get_download_url)
    download_installer
    ensure_dest
    install_helix
    cleanup
    
    printf '%s\n' "Helix installed successfully to $dest/helix/"
    printf '%s\n' "Symlinked to $dest/bin/hx"
    
    if [ "$launch" = "y" ]; then
        printf '%s\n' "To use Helix, add $dest/bin to your PATH or run: $dest/bin/hx"
    fi
}

main "$@"
