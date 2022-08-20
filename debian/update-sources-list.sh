#!/bin/bash
# Update sources.list file properly and easily
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
outfile="sources.list"
arch=$(/usr/bin/dpkg --print-architecture)

options="-o a:so:ncuSbh -l arch:,sources,outfile:,nonfree,contrib,updates,security,backports,help"

# misc functions
log() {
	echo "$@" >&2
}

usage() {
	log "Usage: $0 [OPTIONS] [ Release Codename ]"
	log ""
	log "Release Codename is optional and defaults to the current release."
	log "Otherwise it refers to the release you want to generate the sources.list for."
	log "e.g. $0 buster"
	log "e.g. $0 stable"
	log ""
	log "Options:"
	log "   -a, --arch             Use mirrors containing arch (default: $arch)"
	log "   -s, --sources          Include deb-src lines in generated file (default: no)"
	log "   -o, --outfile OUTFILE  Use OUTFILE as the output file"
	log "                            (default: sources.list)"
	log "   -n, --nonfree          Use also non-free packages in OUTFILE (default: no)"
	log "   -c, --contrib          Use contributed packages (default: no)"
	log "   -u, --updates          Use updates (default: yes)"
	log "   -S, --security         Use security updates (default: yes)"
	log "   -b, --backports        Use backports (default: no)"
	log "   -h, --help             Display this help"
}

# commandline parsing
temp=$(getopt $options -n 'update-sources-list.sh' -- "$@")
if [ $? != 0 ]; then
	echo "Terminating..." >&2
	exit 2
fi
eval set -- "$temp"
while true; do
	case "$1" in
	-a | --arch)
		arch=$2
		shift 2
		;;
	-s | --sources)
		want_sources=1
		shift
		;;
	-o | --outfile)
		outfile="$2"
		shift 2
		;;
	-n | --nonfree)
		want_nonfree=1
		shift
		;;
	-c | --contrib)
		want_contrib=1
		shift
		;;
	-u | --updates)
		want_updates=1
		shift
		;;
	-S | --security)
		want_security=1
		shift
		;;
	-b | --backports)
		want_backports=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	--)
		shift
		break
		;;
	*)
		echo "Internal Error!"
		echo "args: $@"
		exit 1
		;;
	esac
done

# check if we have a release codename
release=${1:-$(lsb_release -sc)}

log "Using distribution $release."

log "Writing $outfile."

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
		echo -n "deb ${host}"
		if [ "$s" = "-security" ]; then
			echo -n "$s"
		fi
		echo " ${release}${s} main ${extra}"
		if [ "$want_sources" -eq 1 ]; then
			echo -n "deb-src ${host}"
			if [ "$s" = "-security" ]; then
				echo -n "$s"
			fi
			echo " ${release}${s} main ${extra}"
		fi
	done
) >$outfile

echo "Done."
