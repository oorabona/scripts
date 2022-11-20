# OpenVPN setup script

This script will let you setup your own secure VPN server in just a few seconds.
It does not handle pure software installation as this is something that can be handled by your package manager, or any other tool at your disposal (e.g. Ansible, Docker, etc.).

## Installation

You can either run the script directly from the repository, or download it and run it locally.

### Run directly from the repository

```bash
bash <(curl -sL https://raw.githubusercontent.com/oorabona/scripts/master/openvpn/setup.sh)
```

### Download and run locally

```bash
curl -sL https://raw.githubusercontent.com/oorabona/scripts/master/openvpn/setup.sh -o openvpn-setup.sh
chmod +x openvpn-setup.sh
```

Then run it:

```sh
./openvpn-setup.sh
```

You need to run the script as root and have the TUN module enabled.

The first time you run it, you'll have to follow the assistant and answer a few questions to setup your VPN server.

When OpenVPN is installed, you can run the script again, and you will get the choice to:

- Add a client
- Remove a client
- Clean OpenVPN configuration
- Update EasyRSA

In your home directory, you will have `.ovpn` files. These are the client configuration files. Download them from your server and connect using your favorite OpenVPN client.

If you have any question, head to the [FAQ](#faq) first. Please read everything before opening an issue.

## Usage

At the moment you have only two options, either you:

- Run the script and follow the assistant
- Run the script in headless mode

### Headless mode

It's possible to run the script headless, e.g. without waiting for user input, in an automated manner.

Example usage:

```bash
AUTO_INSTALL=y ./openvpn-setup.sh
```

Or if you don't want to install the script locally:

```bash
AUTO_INSTALL=y bash <(curl -sL https://raw.githubusercontent.com/oorabona/scripts/master/openvpn/setup.sh)
```

A default set of variables will then be set, by passing the need for user input.

If you want to customise your installation, you can export them or specify them on the same line, as shown above.

- APPROVE_INSTALL (default: y)

> Description:
> Tells the script to automatically approve the installation of OpenVPN and EasyRSA.

- IPV4_SUPPORT (default: y)

> Description:
> Tells the script to enable IPv4 support. This is at the moment unused due to the way OpenVPN handles IPv4 and IPv6.

- IPV6_SUPPORT (default: n)

> Description:
> Tells the script to (force) enable IPv6 support. When in **interactive** mode, the script will try to detect if IPv6 is supported by the system. If it is, it will ask you if you want to enable it. If you don't, you can force it by setting this variable to `y`.

- PORT_CHOICE (default: 1)

> Description:
> Tells the script which port to use for OpenVPN. The default is `1`, which is the menu item referring to the default port for OpenVPN (e.g. 1194). Option `2` will let you specify a `PORT` of your own choice. You can also choose `3`, which will use a random port between 49152 and 65535.

- PORT (default: 1194)

> Description:
> Tells the script which port to use for OpenVPN. This is only used if `PORT_CHOICE` is set to `2`.

- PROTOCOL_CHOICE (default: 1)

> Description:
> Tells the script which protocol to use for OpenVPN. The default is `1`, which is the menu item referring to the default protocol for OpenVPN (e.g. UDP). Option `2` will let you use `TCP` instead.

- DNS (default: 1)

> Description:
> Tells the script which DNS provider to use. The default is `1`, which is the menu item referring to the default DNS provider (e.g. from `/etc/resolv.conf`). The other options are as follows:
>
> - 0 = Do not push any DNS server
> - 1 = Current system resolvers (from /etc/resolv.conf)
> - 2 = Cloudflare (Anycast: worldwide)
> - 3 = Quad9 (Anycast: worldwide)
> - 4 = Quad9 uncensored (Anycast: worldwide)
> - 5 = FDN (France)
> - 6 = DNS.WATCH (Germany)
> - 7 = OpenDNS (Anycast: worldwide)
> - 8 = Google (Anycast: worldwide)
> - 9 = AdGuard DNS (Anycast: worldwide)
> - 10 = NextDNS (Anycast: worldwide)
> - 11 = Custom

-----------------------------
> Note:
> If you choose `11`, you will be asked to specify a custom DNS server using environment variables `DNS1` and `DNS2`.
> If you choose `0`, there will be no DNS pushed to the client, with various repercussions. You will have to specify a DNS server in your client configuration file.

- COMPRESSION_ENABLED (default: n)

> Description:
> Have compression enabled or not. The default is `n`, which will disable compression totally.
> Although you can set this to `y`, it is not recommended to do so, since the VORACLE attack makes use of it...

- CUSTOMIZE_ENC (default: n)

> Description:
> Tells the script to use custom encryption settings. The default is `n`, which will use the default encryption settings.
> If you set this to `y`, you will be asked to specify a custom encryption cipher and key size.

- CLIENT (default: client)

> Description:
> Client name to create configuration for.

- PASS (default: 1)

> Description:
> Tells the script to use a password for the client configuration file. The default is `1`, which will create a passwordless client certificate. You can also set it to `2`, which will let you specify a password for the client certificate.

-----------------------------
> Note:
> If you enable `OTP` (see below), it is equivalent of setting `PASS` to `2`, and you will be asked to specify a password for the client certificate. So you do not need to set `PASS` to `2` if you enable `OTP`.

- CONTINUE (default: y)

> Description:
> Tells the script to continue till the end of the installation of OpenVPN and EasyRSA. The default is `y`, which will continue the installation. You can also set it to `n`, which will stop the installation if important decision has to be made.

- CLIENT_TO_CLIENT (default: n)

> Description:
> Tells the script to enable client-to-client communication. The default is `n`, which will disable client-to-client communication. You can also set it to `y`, which will enable client-to-client communication.

- BLOCK_OUTSIDE_DNS (default: y)

> Description:
> Tells the script to block DNS requests to outside DNS servers. The default is `y`, which will block DNS requests to outside DNS servers. You can also set it to `n`, which will allow DNS requests to outside DNS servers.
> This is useful if you want to use a DNS server that is not in the list above, but you don't want to allow DNS requests to outside DNS servers.
> Note that this is a client configuration option, so you will have to specify it in your client configuration file.

- OTP (default: 1)

> Description:
> Tells the script to use a one-time password for the client configuration file. The default is option `1`, which tells the script to not use a one-time password. You can also set it to `2`, which will let you specify a one-time password for the client certificate. Google Authenticator is used to generate the one-time password.

-----------------------------
> Note:
> If you enable `OTP`, it is equivalent of setting `PASS` to `2`, and you will be asked to specify a password for the client certificate. So you do not need to set `PASS` to `2` if you enable `OTP`.
> A third option is provided for `OATH`, which is a more secure alternative to `OTP`. It is not yet implemented, but will be in the future.
> For more information about how to set up `OTP` or `OATH`, please refer to the [wiki](https://github.com/oorabona/scripts/wiki/OpenVPN-OTP)

- EASYRSA_CRL_DAYS (default: 3650)

> Description:
> Tells the script how many days the certificate revocation list (CRL) should be valid for. The default is `3650`, which is 10 years.

- SUBNET_IPv4 (default: 10.8.0.0)

> Description:
> Tells the script which IPv4 subnet to use for OpenVPN. This subnet shall **NOT** be used by any other network on your system.
> Any other value if acceptable as long as it is a valid IPv4 subnet (RFC1918).

- SUBNET_IPv6 (default: fd42:42:42::)

> Description:
> Tells the script which IPv6 subnet to use for OpenVPN. This subnet shall **NOT** be used by any other network on your system.
> Any other value if acceptable as long as it is a valid IPv6 subnet (RFC4193).

- SUBNET_MASKv4 (default: 24)

> Description:
> Tells the script which IPv4 subnet mask to use for OpenVPN. The default is `24`, which is a /24 subnet.
> Possible values range from `8` to `30`.

- SUBNET_MASKv6 (default: 112)

> Description:
> Tells the script which IPv6 subnet mask to use for OpenVPN. The default is `112`, which is a /112 subnet.
> Possible values range from `64` to `126`.

- ENDPOINT (default: _determined automatically at runtime by asking <https://api.ipify.org>_)

> Description:
> Tells the script which endpoint to use for OpenVPN. The default is to determine the endpoint automatically at runtime by asking <https://api.ipify.org>. Usually this is the public IP address of the server.

If the server is behind NAT, you can specify its endpoint with the `ENDPOINT` variable. The endpoint can be an IPv4 or a domain.

The headless install is more-or-less idempotent, in that it has been made safe to run multiple times with the same parameters, e.g. by a state provisioner like Ansible/Terraform/Salt/Chef/Puppet. It will only install and regenerate the Easy-RSA PKI if it doesn't already exist, and it will only recreate all local config and re-generate the client file on each headless run.

Contrary to the interactive install, the headless install will not prompt for user input, and will not ask for confirmation. It will also not ask for a client name, and will not generate a client file. It will also not ask for a password, and will not generate a password-protected client file.

### Headless User Addition

It's also possible to automate the addition of a new user. Here, the key is to provide the (string) value of the `MENU_OPTION` variable along with the remaining mandatory variables before invoking the script.

The following Bash script adds a new user `foo` to an existing OpenVPN configuration

```bash
#!/bin/bash
export MENU_OPTION="1"
export CLIENT="foo"
export PASS="1"
./openvpn-install.sh
```

## Features

- Configures a ready-to-use OpenVPN server
- Iptables rules and forwarding managed in a seamless way
- If needed, the script can cleanly remove OpenVPN configuration and iptables rules
- Customisable encryption settings, enhanced default settings (see [Security and Encryption](#security-and-encryption) below)
- OpenVPN 2.4 features, mainly encryption improvements (see [Security and Encryption](#security-and-encryption) below)
- Variety of DNS resolvers to be pushed to the clients
- Choice between TCP and UDP
- NATed IPv6 support
- Compression disabled by default to prevent VORACLE. LZ4 (v1/v2) and LZ0 algorithms available otherwise.
- Unprivileged mode: run as `nobody`/`nogroup`
- Block DNS leaks on Windows 10
- Randomised server certificate name
- Choice to protect clients with a password (private key encryption)
- Add option for `client-to-client` connections
- Easy-RSA update management
- TOTP (Google Authenticator) support
- Many other little things!

## Features dropped from Angristan's script

- No installation whatsoever of OpenVPN binaries !
- No removal of OpenVPN binaries !
- No installation or removal or use of `Unbound` !

## Compatibility

The script supports all OS and architectures, provided that :

- The OS is supported by OpenVPN.
- The script requires `systemd`.
- The script requires `iptables` and `netfilter-persistent` (Debian) or `iptables-persistent` (Ubuntu).

## Fork

This script is originally based on the great work of [Nyr and its contributors](https://github.com/Nyr/openvpn-install).
And the derivative work done by [angristan](https://github.com/angristan/openvpn-install).

Among the changes:

- no install of OpenVPN, only configuration
- integrated update of Easy-RSA
- support for additional OpenVPN features

## FAQ

More Q&A in [FAQ.md](FAQ.md).

-----------------------------

**Q:** Which OpenVPN client do you recommend?

**A:** If possible, an official OpenVPN 2.4 client.

- Windows: [The official OpenVPN community client](https://openvpn.net/index.php/download/community-downloads.html).
- Linux: The `openvpn` package from your distribution. There is an [official APT repository](https://community.openvpn.net/openvpn/wiki/OpenvpnSoftwareRepos) for Debian/Ubuntu based distributions.
- macOS: [Tunnelblick](https://tunnelblick.net/), [Viscosity](https://www.sparklabs.com/viscosity/), [OpenVPN for Mac](https://openvpn.net/client-connect-vpn-for-mac-os/).
- Android: [OpenVPN for Android](https://play.google.com/store/apps/details?id=de.blinkt.openvpn).
- iOS: [The official OpenVPN Connect client](https://itunes.apple.com/us/app/openvpn-connect/id590379981).

-----------------------------

**Q:** Is there an OpenVPN documentation?

**A:** Yes, please head to the [OpenVPN Manual](https://community.openvpn.net/openvpn/wiki/Openvpn24ManPage), which references all the options.

-----------------------------

More Q&A in [FAQ.md](FAQ.md).

## One-stop solutions for public cloud

Docker image: [oorabona/openvpn](https://hub.docker.com/r/oorabona/openvpn)
GitHub: [oorabona/docker-containers](https://github.com/oorabona/docker-containers)

## Contributing

### Code formatting

We use [shellcheck](https://github.com/koalaman/shellcheck) and [shfmt](https://github.com/mvdan/sh) to enforce bash styling guidelines and good practices. They are executed for each commit / PR with GitHub Actions, so you can check the configuration [here](https://github.com/angristan/openvpn-install/blob/master/.github/workflows/push.yml).

## Security and Encryption

OpenVPN's default settings are pretty weak regarding encryption. This script aims to improve that.

OpenVPN 2.4 was a great update regarding encryption. It added support for ECDSA, ECDH, AES GCM, NCP and tls-crypt.

If you want more information about an option mentioned below, head to the [OpenVPN manual](https://community.openvpn.net/openvpn/wiki/Openvpn24ManPage). It is very complete.

Most of OpenVPN's encryption-related stuff is managed by [Easy-RSA](https://github.com/OpenVPN/easy-rsa). Defaults parameters are in the [vars.example](https://github.com/OpenVPN/easy-rsa/blob/master/easyrsa3/vars.example) file.

### Compression

By default, OpenVPN doesn't enable compression. This script provides support for LZ0 and LZ4 (v1/v2) algorithms, the latter being more efficient.

However, it is discouraged to use compression since the [VORACLE attack](https://protonvpn.com/blog/voracle-attack/) makes use of it.

### TLS version

OpenVPN accepts TLS 1.0 by default, which is nearly [20 years old](https://en.wikipedia.org/wiki/Transport_Layer_Security#TLS_1.0).

With `tls-version-min 1.2` we enforce TLS 1.2, which the best protocol available currently for OpenVPN.

TLS 1.2 is supported since OpenVPN 2.3.3.

### Certificate

OpenVPN uses an RSA certificate with a 2048 bits key by default.

OpenVPN 2.4 added support for ECDSA. Elliptic curve cryptography is faster, lighter and more secure.

This script provides:

- ECDSA: `prime256v1`/`secp384r1`/`secp521r1` curves
- RSA: `2048`/`3072`/`4096` bits keys

It defaults to ECDSA with `prime256v1`.

OpenVPN uses `SHA-256` as the signature hash by default, and so does the script. It provides no other choice as of now.

### Data channel

By default, OpenVPN uses `BF-CBC` as the data channel cipher. Blowfish is an old (1993) and weak algorithm. Even the official OpenVPN documentation admits it.

> The default is BF-CBC, an abbreviation for Blowfish in Cipher Block Chaining mode.
>
> Using BF-CBC is no longer recommended, because of its 64-bit block size. This small block size allows attacks based on collisions, as demonstrated by SWEET32. See <https://community.openvpn.net/openvpn/wiki/SWEET32> for details.
> Security researchers at INRIA published an attack on 64-bit block ciphers, such as 3DES and Blowfish. They show that they are able to recover plaintext when the same data is sent often enough, and show how they can use cross-site scripting vulnerabilities to send data of interest often enough. This works over HTTPS, but also works for HTTP-over-OpenVPN. See <https://sweet32.info/> for a much better and more elaborate explanation.
>
> OpenVPN's default cipher, BF-CBC, is affected by this attack.

Indeed, AES is today's standard. It's the fastest and more secure cipher available today. [SEED](https://en.wikipedia.org/wiki/SEED) and [Camellia](<https://en.wikipedia.org/wiki/Camellia_(cipher)>) are not vulnerable to date but are slower than AES and relatively less trusted.

> Of the currently supported ciphers, OpenVPN currently recommends using AES-256-CBC or AES-128-CBC. OpenVPN 2.4 and newer will also support GCM. For 2.4+, we recommend using AES-256-GCM or AES-128-GCM.

AES-256 is 40% slower than AES-128, and there isn't any real reason to use a 256 bits key over a 128 bits key with AES. (Source: [1](http://security.stackexchange.com/questions/14068/why-most-people-use-256-bit-encryption-instead-of-128-bit),[2](http://security.stackexchange.com/questions/6141/amount-of-simple-operations-that-is-safely-out-of-reach-for-all-humanity/6149#6149)). Moreover, AES-256 is more vulnerable to [Timing attacks](https://en.wikipedia.org/wiki/Timing_attack).

AES-GCM is an [AEAD cipher](https://en.wikipedia.org/wiki/Authenticated_encryption) which means it simultaneously provides confidentiality, integrity, and authenticity assurances on the data.

The script supports the following ciphers:

- `AES-128-GCM`
- `AES-192-GCM`
- `AES-256-GCM`
- `AES-128-CBC`
- `AES-192-CBC`
- `AES-256-CBC`

And defaults to `AES-128-GCM`.

OpenVPN 2.4 added a feature called "NCP": _Negotiable Crypto Parameters_. It means you can provide a cipher suite like with HTTPS. It is set to `AES-256-GCM:AES-128-GCM` by default and overrides the `--cipher` parameter when used with an OpenVPN 2.4 client. For the sake of simplicity, the script set both the `--cipher` and `--ncp-cipher` to the cipher chosen above.

### Control channel

OpenVPN 2.4 will negotiate the best cipher available by default (e.g ECDHE+AES-256-GCM)

The script proposes the following options, depending on the certificate:

- ECDSA:
  - `TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256`
  - `TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384`
- RSA:
  - `TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256`
  - `TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384`

It defaults to `TLS-ECDHE-*-WITH-AES-128-GCM-SHA256`.

### Diffie-Hellman key exchange

OpenVPN uses a 2048 bits DH key by default.

OpenVPN 2.4 added support for ECDH keys. Elliptic curve cryptography is faster, lighter and more secure.

Also, generating a classic DH keys can take a long, looong time. ECDH keys are ephemeral: they are generated on-the-fly.

The script provides the following options:

- ECDH: `prime256v1`/`secp384r1`/`secp521r1` curves
- DH: `2048`/`3072`/`4096` bits keys

It defaults to `prime256v1`.

### HMAC digest algorithm

From the OpenVPN wiki, about `--auth`:

> Authenticate data channel packets and (if enabled) tls-auth control channel packets with HMAC using message digest algorithm alg. (The default is SHA1 ). HMAC is a commonly used message authentication algorithm (MAC) that uses a data string, a secure hash algorithm, and a key, to produce a digital signature.
>
> If an AEAD cipher mode (e.g. GCM) is chosen, the specified --auth algorithm is ignored for the data channel, and the authentication method of the AEAD cipher is used instead. Note that alg still specifies the digest used for tls-auth.

The script provides the following choices:

- `SHA256`
- `SHA384`
- `SHA512`

It defaults to `SHA256`.

### `tls-auth` and `tls-crypt`

From the OpenVPN wiki, about `tls-auth`:

> Add an additional layer of HMAC authentication on top of the TLS control channel to mitigate DoS attacks and attacks on the TLS stack.
>
> In a nutshell, --tls-auth enables a kind of "HMAC firewall" on OpenVPN's TCP/UDP port, where TLS control channel packets bearing an incorrect HMAC signature can be dropped immediately without response.

About `tls-crypt`:

> Encrypt and authenticate all control channel packets with the key from keyfile. (See --tls-auth for more background.)
>
> Encrypting (and authenticating) control channel packets:
>
> - provides more privacy by hiding the certificate used for the TLS connection,
> - makes it harder to identify OpenVPN traffic as such,
> - provides "poor-man's" post-quantum security, against attackers who will never know the pre-shared key (i.e. no forward secrecy).

So both provide an additional layer of security and mitigate DoS attacks. They aren't used by default by OpenVPN.

`tls-crypt` is an OpenVPN 2.4 feature that provides encryption in addition to authentication (unlike `tls-auth`). It is more privacy-friendly.

The script supports both and uses `tls-crypt` by default.

## Credits & Licence

Many thanks to the [contributors from Angristan work](https://github.com/Angristan/OpenVPN-install/graphs/contributors) and Nyr's original work.

This project is under the [MIT Licence](https://github.com/oorabona/scripts/blob/main/LICENSE)
