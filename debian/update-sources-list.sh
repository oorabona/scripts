#!/bin/bash
# Update Debian sources.list file properly and easily
# Heavily inspired by the work of: netselect-apt by Avery Pennarun (https://github.com/apenwarr/netselect)

# Current patterns taken from https://wiki.debian.org/SourcesList
# with the use of the Fastly CDN instead of seeking for the closest mirror.

# deb http://deb.debian.org/debian bullseye main contrib non-free
# deb-src http://deb.debian.org/debian bullseye main contrib non-free
#
# deb http://deb.debian.org/debian-security/ bullseye-security main contrib non-free
# deb-src http://deb.debian.org/debian-security/ bullseye-security main contrib non-free
#
# deb http://deb.debian.org/debian bullseye-updates main contrib non-free
# deb-src http://deb.debian.org/debian bullseye-updates main contrib non-free

host="http://deb.debian.org/debian"
want_security=${WANT_SECURITY:-1}
want_updates=${WANT_UPDATES:-1}
want_sources=${WANT_SOURCES:-0}
want_nonfree=${WANT_NONFREE:-0}
want_contrib=${WANT_CONTRIB:-0}
want_backports=${WANT_BACKPORTS:-0}
default_outfile="$(pwd)/sources.list"
default_arch=$(/usr/bin/dpkg --print-architecture)

# misc functions
log() {
	echo "$@" >&2
}

usage() {
	log "Usage: $0 [OPTIONS] [ Release Codename ]"
	log ""
	log "Release Codename is optional and defaults to the current release ($1)."
	log "Otherwise it refers to the release you want to generate the sources.list for."
	log "e.g. $0 buster"
	log "e.g. $0 stable"
	log ""
	log "Options:"
	log "   -a, --arch             Use mirrors containing arch (default: $2)"
	log "   -s, --sources          Include deb-src lines in generated file (default: no)"
	log "   -o, --outfile OUTFILE  Use OUTFILE as the output file"
	log "                            (default: $3)"
	log "   -n, --nonfree          Use also non-free packages in OUTFILE (default: no)"
	log "   -c, --contrib          Use contributed packages (default: no)"
	log "   -u, --updates          Use updates (default: yes)"
	log "   -S, --security         Use security updates (default: yes)"
	log "   -b, --backports        Use backports (default: no)"
	log "   -h, --help             Display this help"
}

# Process options
ARGPOS=()
while [ $# -gt 0 ]; do
	case "$1" in
	--arch | -a)
		arch=$2
		shift 2
		;;
	--sources | -s)
		want_sources=1
		shift
		;;
	--outfile | -o)
		outfile=$2
		shift 2
		;;
	--nonfree | -n)
		want_nonfree=1
		shift
		;;
	--contrib | -c)
		want_contrib=1
		shift
		;;
	--updates | -u)
		want_updates=1
		shift
		;;
	--backports | -b)
		want_backports=1
		shift
		;;
	--help | -h)
		want_help=1
		shift
		;;
	*)
		ARGPOS+=("$1")
		shift
		;;
	esac
done

# Process positional arguments
if [ -n "${ARGPOS[0]}" ]; then
	release=${ARGPOS[0]}
else
	release=$(lsb_release -cs)
fi

if [ -n "$want_help" ]; then
	usage "$release" "$default_arch" "$default_outfile"
	exit 0
fi

if [ -n "$arch" ]; then
	log "Using architecture $arch."
else
	log "Using default architecture $default_arch."
fi

if [ -n "$outfile" ]; then
	log "Using outfile $outfile."
else
	log "Using default outfile $default_outfile."
	outfile=$default_outfile
fi

log "Using distribution $release."

if [ -f "$outfile" ]; then
	backupOutfile="$outfile.$(date +%s)"
	log "$outfile exists, backing up to $backupOutfile"
	mv $outfile $backupOutfile
fi

stream=","
if [ "$want_security" -eq 1 ]; then
	stream="${stream}-security"
fi
if [ "$want_updates" -eq 1 ]; then
	stream="${stream},-updates"
fi
if [ "$want_backports" -eq 1 ]; then
	stream="${stream},-backports"
fi

if [ "$want_contrib" -eq 1 ]; then
	extra="${extra} contrib"
fi
if [ "$want_nonfree" -eq 1 ]; then
	extra="${extra} non-free"
fi

IFS=,
(
	echo "# Debian packages for $release"
	for s in $stream; do
		echo -n "deb "
		# Support for multi arch
		if [ -n "$arch" ]; then
			echo -n "[arch=${arch}] "
		fi
		echo -n "${host}"
		if [ "$s" = "-security" ]; then
			echo -n "$s"
		fi
		echo " ${release}${s} main ${extra}"

		# If we do not want to add sources, simply comment the line, you never know
		# when you might want to add them back.
		if [ "$want_sources" -eq 0 ]; then
			echo -n "# "
		fi
		echo -n "deb-src ${host}"
		if [ "$s" = "-security" ]; then
			echo -n "$s"
		fi
		echo " ${release}${s} main ${extra}"
	done
) >$outfile

echo "Done."
