# Purpose

Update the sources.list file for the current distribution.

# Installation

No special need to install this script per se.
You can directly run from `curl` as follows:

```bash
$ bash <(curl -sL https://raw.githubusercontent.com/oorabona/scripts/master/debian/update-sources-list.sh) -s -c -n stable
```

See the options just below.

# Help

```bash
$ ./update-sources-list.sh -h
Usage: ./update-sources-list.sh [OPTIONS] [ Release Codename ]

Release Codename is optional and defaults to the current release.
Otherwise it refers to the release you want to generate the sources.list for.
e.g. ./update-sources-list.sh jessie
e.g. ./update-sources-list.sh stable

Options:
   -a, --arch             Use mirrors containing arch (default: amd64)
   -s, --sources          Include deb-src lines in generated file (default: no)
   -o, --outfile OUTFILE  Use OUTFILE as the output file
                            (default: sources.list)
   -n, --nonfree          Use also non-free packages in OUTFILE (default: no)
   -c, --contrib          Use contributed packages (default: no)
   -u, --updates          Use updates (default: yes)
   -S, --security         Use security updates (default: yes)
   -h, --help             Display this help
```

It will be using informations found in Debian related files / applications (i.e. `lsb_release` and `dpkg`) to automatically detect the architecture.

As you can see, it has detected `amd64` as the architecture.
Of course you can use the `--arch` option to force the architecture.

As for the release codename, it will use the current release if no codename is provided.
Otherwise any codename starting with `stretch` will be compatible [see here why](http://deb.debian.org/).

When no argument is given, a `sources.list` file will be generated in the working directory for the current release.

### Example

```bash
$ bash <(curl -sL https://raw.githubusercontent.com/oorabona/scripts/master/debian/update-sources-list.sh)               
Using distribution bullseye.
Writing sources.list.
Done.
$ cat sources.list
# Debian packages for bullseye
deb http://deb.debian.org/debian bullseye main 
deb http://deb.debian.org/debian-security bullseye-security main 
deb http://deb.debian.org/debian bullseye-updates main
```