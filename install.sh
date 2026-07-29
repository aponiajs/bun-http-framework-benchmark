#!/usr/bin/env bash
#
# Setup script for bun-http-framework-benchmark.
#
# Installs the load generator (bombardier) plus the JavaScript runtimes the
# benchmark drives (bun, deno, node), then installs project dependencies.
#
# Usage:
#   ./install.sh                  # install everything that is missing
#   ./install.sh --check          # report status only, install nothing
#   ./install.sh --skip-runtimes  # only bombardier + project dependencies
#   ./install.sh --skip-deps      # do not run "bun install"
#   ./install.sh --prefix DIR     # where to drop downloaded binaries
#   ./install.sh --no-modify-path # do not touch shell rc files
#
set -euo pipefail

PREFIX="${BENCH_INSTALL_PREFIX:-$HOME/.local/bin}"
CHECK_ONLY=0
SKIP_RUNTIMES=0
SKIP_DEPS=0
MODIFY_PATH=1
MISSING_NODE=0

while [ $# -gt 0 ]; do
	case "$1" in
	--check) CHECK_ONLY=1 ;;
	--skip-runtimes) SKIP_RUNTIMES=1 ;;
	--skip-deps) SKIP_DEPS=1 ;;
	--no-modify-path) MODIFY_PATH=0 ;;
	--prefix)
		PREFIX="${2:?--prefix needs a directory}"
		shift
		;;
	-h | --help)
		sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		exit 2
		;;
	esac
	shift
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*" >&2; }
die() {
	printf '\033[1;31m  xx\033[0m %s\n' "$*" >&2
	exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

os_name() {
	case "$(uname -s)" in
	Linux) echo linux ;;
	Darwin) echo darwin ;;
	*) echo unsupported ;;
	esac
}

arch_name() {
	case "$(uname -m)" in
	x86_64 | amd64) echo amd64 ;;
	aarch64 | arm64) echo arm64 ;;
	*) echo unsupported ;;
	esac
}

download() {
	url="$1"
	out="$2"
	if have curl; then
		curl -fsSL "$url" -o "$out"
	elif have wget; then
		wget -qO "$out" "$url"
	else
		die "need curl or wget to download $url"
	fi
}

# Runs a package manager install, tolerating failure so we can fall back to a
# plain binary download.
try_pkg() {
	log "trying: $*"
	"$@" >/dev/null 2>&1
}

install_bombardier() {
	if have bombardier; then
		ok "bombardier: $(bombardier --version 2>&1 | head -1)"
		return 0
	fi

	if [ "$CHECK_ONLY" = 1 ]; then
		warn "bombardier: missing"
		return 0
	fi

	log "installing bombardier"

	if [ "$(os_name)" = darwin ] && have brew; then
		try_pkg brew install bombardier && {
			ok "bombardier installed via brew"
			return 0
		}
	fi

	if have paru; then
		try_pkg paru -S --noconfirm bombardier && {
			ok "bombardier installed via paru"
			return 0
		}
	elif have yay; then
		try_pkg yay -S --noconfirm bombardier && {
			ok "bombardier installed via yay"
			return 0
		}
	fi

	os="$(os_name)"
	arch="$(arch_name)"
	if [ "$os" != unsupported ] && [ "$arch" != unsupported ]; then
		url="https://github.com/codesenberg/bombardier/releases/latest/download/bombardier-${os}-${arch}"
		mkdir -p "$PREFIX"
		log "downloading $url"
		download "$url" "$PREFIX/bombardier"
		chmod +x "$PREFIX/bombardier"
		ok "bombardier installed to $PREFIX/bombardier"
		return 0
	fi

	if have go; then
		log "building bombardier from source with go"
		go install github.com/codesenberg/bombardier@latest
		ok "bombardier installed via go install"
		return 0
	fi

	die "could not install bombardier automatically; see https://github.com/codesenberg/bombardier"
}

install_bun() {
	if have bun; then
		ok "bun: $(bun --version)"
		return 0
	fi
	if [ "$CHECK_ONLY" = 1 ]; then
		warn "bun: missing"
		return 0
	fi

	log "installing bun from https://bun.sh/install"
	if have curl; then
		curl -fsSL https://bun.sh/install | bash
	else
		die "need curl to install bun"
	fi
	export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
	export PATH="$BUN_INSTALL/bin:$PATH"
	have bun || die "bun installed but not on PATH; open a new shell and re-run"
	ok "bun: $(bun --version)"
}

install_deno() {
	if have deno; then
		ok "deno: $(deno --version | head -1)"
		return 0
	fi
	if [ "$CHECK_ONLY" = 1 ]; then
		warn "deno: missing (deno targets will be skipped)"
		return 0
	fi

	log "installing deno from https://deno.land/install.sh"
	if have curl; then
		curl -fsSL https://deno.land/install.sh | sh -s -- -y
	else
		warn "need curl to install deno; deno targets will be skipped"
		return 0
	fi
	export DENO_INSTALL="${DENO_INSTALL:-$HOME/.deno}"
	export PATH="$DENO_INSTALL/bin:$PATH"
	have deno && ok "deno: $(deno --version | head -1)" ||
		warn "deno installed but not on PATH; open a new shell"
}

# Latest LTS version tag, resolved through bun so no jq dependency is needed.
node_lts_version() {
	bun -e 'const releases = await (await fetch("https://nodejs.org/dist/index.json")).json(); const lts = releases.find((release) => release.lts); if (!lts) process.exit(1); console.log(lts.version)'
}

install_node_tarball() {
	os="$(os_name)"
	case "$(arch_name)" in
	amd64) narch=x64 ;;
	arm64) narch=arm64 ;;
	*) return 1 ;;
	esac
	[ "$os" = unsupported ] && return 1
	have bun || return 1
	have tar || return 1

	version="$(node_lts_version)" || return 1
	name="node-${version}-${os}-${narch}"
	libdir="${PREFIX%/bin}/lib"
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' RETURN

	log "downloading $name"
	download "https://nodejs.org/dist/${version}/${name}.tar.gz" "$tmp/node.tar.gz" || return 1
	mkdir -p "$libdir" "$PREFIX"
	tar -xzf "$tmp/node.tar.gz" -C "$libdir" || return 1
	rm -rf "$libdir/node"
	mv "$libdir/$name" "$libdir/node"
	for binary in node npm npx; do
		[ -e "$libdir/node/bin/$binary" ] && ln -sf "$libdir/node/bin/$binary" "$PREFIX/$binary"
	done

	return 0
}

install_node() {
	if have node; then
		ok "node: $(node --version)"
		return 0
	fi
	if [ "$CHECK_ONLY" = 1 ]; then
		MISSING_NODE=1
		warn "node: missing (node targets will be skipped)"
		return 0
	fi

	log "installing node"

	if [ "$(os_name)" = darwin ] && have brew; then
		try_pkg brew install node && {
			ok "node: $(node --version)"
			return 0
		}
	fi

	if have fnm; then
		try_pkg fnm install --lts && have node && {
			ok "node: $(node --version)"
			return 0
		}
	fi

	if install_node_tarball; then
		hash -r 2>/dev/null || true
		ok "node installed to $PREFIX/node ($("$PREFIX/node" --version))"
		return 0
	fi

	MISSING_NODE=1
	warn "could not install node automatically (node targets will be skipped)"
	warn "install one of: mise use -g node@lts | fnm install --lts | nvm install --lts"
}

# Downloaded binaries are useless if the shell cannot see them, so persist the
# PATH entry instead of only printing it.
persist_path() {
	case ":$ORIGINAL_PATH:" in
	*":$PREFIX:"*) return 0 ;;
	esac
	[ -d "$PREFIX" ] || return 0

	if [ "$MODIFY_PATH" = 0 ] || [ "$CHECK_ONLY" = 1 ]; then
		warn "$PREFIX is not on PATH. Add to your shell rc:"
		warn "  export PATH=\"$PREFIX:\$PATH\""
		return 0
	fi

	line="export PATH=\"$PREFIX:\$PATH\""
	written=0
	for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
		[ -f "$rc" ] || continue
		grep -qF "$PREFIX" "$rc" && continue
		printf '\n# added by bun-http-framework-benchmark install.sh\n%s\n' "$line" >>"$rc"
		ok "added $PREFIX to PATH in $rc"
		written=1
	done

	[ "$written" = 0 ] && warn "no shell rc found; add to yours: $line"
	warn "run this in the current shell to use it now:"
	warn "  $line"
	return 0
}

install_dependencies() {
	[ "$SKIP_DEPS" = 1 ] && return 0
	[ "$CHECK_ONLY" = 1 ] && return 0
	have bun || {
		warn "skipping dependency install: bun is missing"
		return 0
	}
	log "installing project dependencies"
	bun install
	ok "dependencies installed"
}

log "bun-http-framework-benchmark setup"
ORIGINAL_PATH="$PATH"
export PATH="$PREFIX:$PATH"

install_bombardier
if [ "$SKIP_RUNTIMES" = 0 ]; then
	install_bun
	install_deno
	install_node
fi
install_dependencies
persist_path

echo
if [ "$CHECK_ONLY" = 1 ]; then
	log "check finished"
else
	log "setup finished"
fi
echo "  bun benchmark                 run every framework"
echo "  bun benchmark bun/elysia      run one framework"
echo "  bun benchmark --interactive   pick frameworks and an RPS cap"
[ "$MISSING_NODE" = 1 ] && echo "  (node targets are skipped until node is installed)"
exit 0
