# Purpose

Create a brand new `sources.list` file fit to your requirements !

> This script does *not* requires `sudo` rights.
> It will by default create a `sources.list` file in the current working directory, letting you decide what to do with it.

## Installation

No special need to install this script per se.
You can directly run from `curl` as follows:

```bash
bash <(curl -sL https://raw.githubusercontent.com/oorabona/scripts/master/debian/update-sources-list.sh) -s -c -n stable
```

See the options just below.

## Help

```bash
$ ./update-sources-list.sh -h
Usage: ./update-sources-list.sh [OPTIONS] [ Release Codename ]

Release Codename is optional and defaults to the current release (bullseye).
Otherwise it refers to the release you want to generate the sources.list for.
e.g. ./update-sources-list.sh buster
e.g. ./update-sources-list.sh stable

Options:
   -a, --arch             Use mirrors containing arch (default: amd64)
   -s, --sources          Include deb-src lines in generated file (default: no)
   -o, --outfile OUTFILE  Use OUTFILE as the output file
                            (default: /home/user/dev/scripts/debian/sources.list)
   -n, --nonfree          Use also non-free packages in OUTFILE (default: no)
   -c, --contrib          Use contributed packages (default: no)
   -u, --updates          Use updates (default: yes)
   -S, --security         Use security updates (default: yes)
   -b, --backports        Use backports (default: no)
   -h, --help             Display this help
```

It will do its best to automatically detect what it needs (i.e. using `lsb_release` and `dpkg`):

- the current distribution codename (in this exemple `bullseye`)

> Otherwise any codename starting with `stretch` will be compatible [see here why](http://deb.debian.org/).

- the current architecture (in this exemple `amd64`)

> Of course you can use the `--arch` option to force the architecture(s) you want to add to the [arch=...].

When no argument is given, a `sources.list` file will be generated in the current working directory for the current release.

### Example

```bash
$ bash <(curl -sL https://raw.githubusercontent.com/oorabona/scripts/master/debian/update-sources-list.sh)               
Using default architecture amd64.
Using default outfile /home/user/dev/scripts/debian/sources.list.
Using distribution bullseye.
Done.
```

```bash
$ cat sources.list
# Debian packages for bullseye
deb http://deb.debian.org/debian bullseye main 
# deb-src http://deb.debian.org/debian bullseye main 
deb http://deb.debian.org/debian-security bullseye-security main 
# deb-src http://deb.debian.org/debian-security bullseye-security main 
deb http://deb.debian.org/debian bullseye-updates main 
# deb-src http://deb.debian.org/debian bullseye-updates main 
```
