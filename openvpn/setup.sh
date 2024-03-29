#!/bin/bash
# shellcheck disable=SC1091,SC2164,SC2034,SC1072,SC1073,SC1009

# Secure OpenVPN server setup
# Adapted from https://github.com/angristan/openvpn-install

function isRoot() {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
}

function tunAvailable() {
	if [ ! -e /dev/net/tun ]; then
		return 1
	fi
}

function checkOS() {
	if [[ -e /etc/debian_version ]]; then
		OS="debian"
		source /etc/os-release

		if [[ $ID == "debian" || $ID == "raspbian" ]]; then
			if [[ $VERSION_ID -lt 9 ]]; then
				echo "⚠️ Your version of Debian is not supported."
				echo ""
				echo "However, if you're using Debian >= 9 or unstable/testing then you can continue, at your own risk."
				echo ""
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Continue? [y/n]: " -e CONTINUE
				done
				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		elif [[ $ID == "ubuntu" ]]; then
			OS="ubuntu"
			MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
			if [[ $MAJOR_UBUNTU_VERSION -lt 16 ]]; then
				echo "⚠️ Your version of Ubuntu is not supported."
				echo ""
				echo "However, if you're using Ubuntu >= 16.04 or beta, then you can continue, at your own risk."
				echo ""
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Continue? [y/n]: " -e CONTINUE
				done
				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		fi
	elif [[ -e /etc/system-release ]]; then
		source /etc/os-release
		if [[ $ID == "fedora" || $ID_LIKE == "fedora" ]]; then
			OS="fedora"
		fi
		if [[ $ID == "centos" || $ID == "rocky" || $ID == "almalinux" ]]; then
			OS="centos"
			if [[ ! $VERSION_ID =~ (7|8) ]]; then
				echo "⚠️ Your version of CentOS is not supported."
				echo ""
				echo "The script only support CentOS 7 and CentOS 8."
				echo ""
				exit 1
			fi
		fi
		if [[ $ID == "ol" ]]; then
			OS="oracle"
			if [[ ! $VERSION_ID =~ (8) ]]; then
				echo "Your version of Oracle Linux is not supported."
				echo ""
				echo "The script only support Oracle Linux 8."
				exit 1
			fi
		fi
		if [[ $ID == "amzn" ]]; then
			OS="amzn"
			if [[ $VERSION_ID != "2" ]]; then
				echo "⚠️ Your version of Amazon Linux is not supported."
				echo ""
				echo "The script only support Amazon Linux 2."
				echo ""
				exit 1
			fi
		fi
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	elif [[ "$OS" == "" ]]; then
		echo "Looks like you aren't running this installer on a Debian, Ubuntu, Fedora, CentOS, Amazon Linux 2, Oracle Linux 8 or Arch Linux system"
		echo ""
		echo "Do you still want to run this installer? (If yes, only systemctl scripts will not be installed)"
		echo ""
		until [[ $CONTINUE =~ (y|n) ]]; do
			read -rp "Continue? [y/n]: " -e CONTINUE
		done
		if [[ $CONTINUE == "n" ]]; then
			exit 1
		fi
		OS=other
	fi
}

function initialCheck() {
	if ! isRoot; then
		echo "Sorry, you need to run this as root"
		exit 1
	fi
	if ! tunAvailable; then
		echo "TUN is not available"
		exit 1
	fi
	checkOS
}

function calc_subnet_mask() {
	local mask=$((0xffffffff << (32 - $1)))
	echo $((mask >> 24 & 0xff)).$((mask >> 16 & 0xff)).$((mask >> 8 & 0xff)).$((mask & 0xff))
}

function installQuestions() {
	echo "Welcome to the OpenVPN installer!"
	echo "The git repository is available at: https://github.com/oorabona/scripts/"
	echo ""

	echo "I need to ask you a few questions before starting the setup."
	echo "You can leave the default options and just press enter if you are ok with them."
	echo ""

	if [[ $IPV4_SUPPORT == "y" && -z $ENDPOINT ]]; then
		echo "I need to know the IPv4 address of the network interface you want OpenVPN listening to."
		echo "Unless your server is behind NAT, it should be your public IPv4 address."

		# Detect public IPv4 address and pre-fill for the user
		IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)

		if [[ -z $IP ]]; then
			# Ask for the public IPv4 address if not found
			until [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; do
				read -rp "IP address: " -e IP
			done
		fi
		# If $IP is a private IP address, the server must be behind NAT
		if echo "$IP" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
			echo ""
			echo "It seems this server is behind NAT. What is its public IPv4 address or hostname?"
			echo "We need it for the clients to connect to the server."

			PUBLICIP=$(curl -s https://api.ipify.org)

			if [[ "$AUTO_INSTALL" == "y" ]]; then
				ENDPOINT=$PUBLICIP
			else
				until [[ "$ENDPOINT" != "" ]]; do
					read -rp "Public IPv4 address or hostname: " -i "$PUBLICIP" -e ENDPOINT
				done
			fi
		fi
	fi

	echo ""
	echo "Checking for IPv6 connectivity..."
	echo ""
	# "ping6" and "ping -6" availability varies depending on the distribution
	if type ping6 >/dev/null 2>&1; then
		PING6="ping6 -c3 ipv6.google.com > /dev/null 2>&1"
	else
		PING6="ping -6 -c3 ipv6.google.com > /dev/null 2>&1"
	fi
	if eval "$PING6"; then
		echo "Your host appears to have IPv6 connectivity."
		SUGGESTION="y"
	else
		echo "Your host does not appear to have IPv6 connectivity."
		SUGGESTION="n"
	fi
	echo ""
	# Ask the user if they want to enable IPv6 regardless its availability.
	until [[ "$IPV6_SUPPORT" =~ (y|n) ]]; do
		read -rp "Do you want to enable IPv6 support (NAT)? [y/n]: " -i $SUGGESTION -e IPV6_SUPPORT
	done

	if [[ $IPV6_SUPPORT == "y" && -z $ENDPOINT6 ]]; then
		echo ""
		echo "I need to know the IPv6 address of the network interface you want OpenVPN listening to."
		echo "Unless your server is behind NAT, it should be your public IPv6 address."

		# Detect public IPv6 address and pre-fill for the user
		IP6=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)

		if [[ -z $IP6 ]]; then
			# Ask for the public IPv6 address if not found
			until [[ "$IP6" =~ ^([a-f0-9]{1,4}:){7}[a-f0-9]{1,4}$ ]]; do
				read -rp "IPv6 address: " -e IP6
			done
		fi
		# If $IP6 is a private IP address, the server must be behind NAT
		if echo "$IP6" | grep -qE '^fd'; then
			echo ""
			echo "It seems this server is behind NAT. What is its public IPv6 address or hostname?"
			echo "We need it for the clients to connect to the server."

			PUBLICIP6=$(curl -s https://api6.ipify.org)
			until [[ "$ENDPOINT6" != "" ]]; do
				read -rp "Public IPv6 address or hostname: " -i "$PUBLICIP6" -e ENDPOINT6
			done
		fi
	fi

	echo ""
	echo "Do you want to enable client-to-client traffic?"
	echo "This will allow clients to communicate with each other without going through the server."
	echo "It is recommended to enable this if you are using a VPN for games."
	echo "Otherwise, leave it disabled."
	echo ""
	until [[ "$CLIENT_TO_CLIENT" =~ (y|n) ]]; do
		read -rp "Enable client-to-client traffic? [y/n]: " -e CLIENT_TO_CLIENT
	done
	
	echo ""
	echo "Which subnet do you want to use for the VPN?"
	echo "The default is 10.8.0.0, but you can use any private subnet (RFC1918)."
	echo ""
	until [[ "$SUBNET_IPv4" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; do
		read -rp "Subnet: " -i 10.8.0.0 -e SUBNET_IPv4
	done

	echo ""
	echo "Please enter the SUBNET MASK you want to use for the VPN."
	echo "The default is 24 bits (e.g. 255.255.255.0), but you can use any private subnet mask (RFC1918)."
	echo ""
	until [[ $SUBNET_MASKv4 =~ ^[0-9]+$ ]] && [ "$SUBNET_MASKv4" -ge 8 ] && [ "$SUBNET_MASKv4" -le 30 ]; do
		read -rp "Subnet Mask [8-30]: " -i 24 -e SUBNET_MASKv4
	done

	# If we need to enable IPv6 support, ask for the IPv6 subnet
	if [[ $IPV6_SUPPORT == "y" ]]; then
		echo ""
		echo "Which subnet do you want to use for the VPN?"
		echo "The default is fd42:42:42::, but you can use any private subnet (RFC1918)."
		echo ""
		until [[ "$SUBNET_IPv6" =~ ^([a-f0-9]{1,4}:){7}[a-f0-9]{1,4}$ ]]; do
			read -rp "Subnet: " -i fd42:42:42:: -e SUBNET_IPv6
		done

		echo ""
		echo "Please enter the SUBNET MASK you want to use for the VPN."
		echo "The default is 112, but you can use any private subnet mask (RFC1918)."
		echo ""
		until [[ $SUBNET_MASKv6 =~ ^[0-9]+$ ]] && [ "$SUBNET_MASKv6" -ge 64 ] && [ "$SUBNET_MASKv6" -le 126 ]; do
			read -rp "Subnet Mask [64-126]: " -i 112 -e SUBNET_MASKv6
		done
	fi

	echo ""
	echo "What port do you want OpenVPN to listen to?"
	echo "   1) Default: 1194"
	echo "   2) Custom"
	echo "   3) Random [49152-65535]"
	until [[ $PORT_CHOICE =~ ^[1-3]$ ]]; do
		read -rp "Port choice [1-3]: " -e -i 1 PORT_CHOICE
	done
	case $PORT_CHOICE in
	1)
		PORT="1194"
		;;
	2)
		until [[ $PORT =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; do
			read -rp "Custom port [1-65535]: " -e -i 1194 PORT
		done
		;;
	3)
		# Generate random number within private ports range
		PORT=$(shuf -i49152-65535 -n1)
		echo "Random Port: $PORT"
		;;
	esac
	echo ""
	echo "What protocol do you want OpenVPN to use?"
	echo "UDP is faster. Unless it is not available, you shouldn't use TCP."
	echo "   1) UDP"
	echo "   2) TCP"
	until [[ $PROTOCOL_CHOICE =~ ^[1-2]$ ]]; do
		read -rp "Protocol [1-2]: " -e -i 1 PROTOCOL_CHOICE
	done
	case $PROTOCOL_CHOICE in
	1)
		PROTOCOL="udp"
		;;
	2)
		PROTOCOL="tcp"
		;;
	esac
	echo ""
	echo "What DNS resolvers do you want to use with the VPN?"
	echo "   0) Do not push any DNS server"
	echo "   1) Current system resolvers (from /etc/resolv.conf)"
	echo "   2) Cloudflare (Anycast: worldwide)"
	echo "   3) Quad9 (Anycast: worldwide)"
	echo "   4) Quad9 uncensored (Anycast: worldwide)"
	echo "   5) FDN (France)"
	echo "   6) DNS.WATCH (Germany)"
	echo "   7) OpenDNS (Anycast: worldwide)"
	echo "   8) Google (Anycast: worldwide)"
	echo "   9) AdGuard DNS (Anycast: worldwide)"
	echo "   10) NextDNS (Anycast: worldwide)"
	echo "   11) Custom"
	until [[ $DNS =~ ^[0-9]+$ ]] && [ "$DNS" -ge 0 ] && [ "$DNS" -le 11 ]; do
		read -rp "DNS [0-11]: " -e -i 1 DNS
		if [[ $DNS == "11" ]]; then
			until [[ $DNS1 =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
				read -rp "Primary DNS: " -e DNS1
			done
			until [[ $DNS2 =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
				read -rp "Secondary DNS (optional): " -e DNS2
				if [[ $DNS2 == "" ]]; then
					break
				fi
			done
		fi
	done
	echo ""
	echo "Do you want to block outside DNS requests?"
	echo "This will prevent clients from using the DNS of their ISP, and force them to use the DNS of the VPN."
	echo "This can be useful to protect your privacy, but may break some applications."
	until [[ "$BLOCK_OUTSIDE_DNS" =~ (y|n) ]]; do
		read -rp "Block outside DNS requests? [y/n]: " -e BLOCK_OUTSIDE_DNS
	done

	# Warn if the user wants to block outside dns while not having any dns server pushed
	if [[ "$BLOCK_OUTSIDE_DNS" == "y" ]] && [[ "$DNS" == "0" ]]; then
		echo ""
		echo "You have chosen to block outside DNS requests, but you have not chosen to push any DNS server!"
		echo "This will probably not work as expected!"
		echo ""
		until [[ "$CONTINUE" =~ (y|n) ]]; do
			read -rp "Are you sure you want to proceed with the current configuration? [y/n]: " -i n -e CONTINUE
		done
		if [[ "$CONTINUE" == "n" ]]; then
			exit 1
		fi
	fi

	echo ""
	echo "Do you want to use compression? It is not recommended since the VORACLE attack makes use of it."
	until [[ $COMPRESSION_ENABLED =~ (y|n) ]]; do
		read -rp"Enable compression? [y/n]: " -e -i n COMPRESSION_ENABLED
	done
	if [[ $COMPRESSION_ENABLED == "y" ]]; then
		echo "Choose which compression algorithm you want to use: (they are ordered by efficiency)"
		echo "   1) LZ4-v2"
		echo "   2) LZ4"
		echo "   3) LZ0"
		until [[ $COMPRESSION_CHOICE =~ ^[1-3]$ ]]; do
			read -rp"Compression algorithm [1-3]: " -e -i 1 COMPRESSION_CHOICE
		done
		case $COMPRESSION_CHOICE in
		1)
			COMPRESSION_ALG="lz4-v2"
			;;
		2)
			COMPRESSION_ALG="lz4"
			;;
		3)
			COMPRESSION_ALG="lzo"
			;;
		esac
	fi
	echo ""
	echo "Do you want to customize encryption settings?"
	echo "Unless you know what you're doing, you should stick with the default parameters provided by the script."
	echo "Note that whatever you choose, all the choices presented in the script are safe. (Unlike OpenVPN's defaults)"
	echo "See https://github.com/oorabona/scripts/openvpn/README.md#security-and-encryption to learn more."
	echo ""
	until [[ $CUSTOMIZE_ENC =~ (y|n) ]]; do
		read -rp "Customize encryption settings? [y/n]: " -e -i n CUSTOMIZE_ENC
	done
	if [[ $CUSTOMIZE_ENC == "n" ]]; then
		# Use default, sane and fast parameters
		CIPHER="AES-128-GCM"
		CERT_TYPE="1" # ECDSA
		CERT_CURVE="prime256v1"
		CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256"
		DH_TYPE="1" # ECDH
		DH_CURVE="prime256v1"
		HMAC_ALG="SHA256"
		TLS_SIG="1" # tls-crypt
	else
		echo ""
		echo "Choose which cipher you want to use for the data channel:"
		echo "   1) AES-128-GCM (recommended)"
		echo "   2) AES-192-GCM"
		echo "   3) AES-256-GCM"
		echo "   4) AES-128-CBC"
		echo "   5) AES-192-CBC"
		echo "   6) AES-256-CBC"
		until [[ $CIPHER_CHOICE =~ ^[1-6]$ ]]; do
			read -rp "Cipher [1-6]: " -e -i 1 CIPHER_CHOICE
		done
		case $CIPHER_CHOICE in
		1)
			CIPHER="AES-128-GCM"
			;;
		2)
			CIPHER="AES-192-GCM"
			;;
		3)
			CIPHER="AES-256-GCM"
			;;
		4)
			CIPHER="AES-128-CBC"
			;;
		5)
			CIPHER="AES-192-CBC"
			;;
		6)
			CIPHER="AES-256-CBC"
			;;
		esac
		echo ""
		echo "Choose what kind of certificate you want to use:"
		echo "   1) ECDSA (recommended)"
		echo "   2) RSA"
		until [[ $CERT_TYPE =~ ^[1-2]$ ]]; do
			read -rp"Certificate key type [1-2]: " -e -i 1 CERT_TYPE
		done
		case $CERT_TYPE in
		1)
			echo ""
			echo "Choose which curve you want to use for the certificate's key:"
			echo "   1) prime256v1 (recommended)"
			echo "   2) secp384r1"
			echo "   3) secp521r1"
			until [[ $CERT_CURVE_CHOICE =~ ^[1-3]$ ]]; do
				read -rp"Curve [1-3]: " -e -i 1 CERT_CURVE_CHOICE
			done
			case $CERT_CURVE_CHOICE in
			1)
				CERT_CURVE="prime256v1"
				;;
			2)
				CERT_CURVE="secp384r1"
				;;
			3)
				CERT_CURVE="secp521r1"
				;;
			esac
			;;
		2)
			echo ""
			echo "Choose which size you want to use for the certificate's RSA key:"
			echo "   1) 2048 bits (recommended)"
			echo "   2) 3072 bits"
			echo "   3) 4096 bits"
			until [[ $RSA_KEY_SIZE_CHOICE =~ ^[1-3]$ ]]; do
				read -rp "RSA key size [1-3]: " -e -i 1 RSA_KEY_SIZE_CHOICE
			done
			case $RSA_KEY_SIZE_CHOICE in
			1)
				RSA_KEY_SIZE="2048"
				;;
			2)
				RSA_KEY_SIZE="3072"
				;;
			3)
				RSA_KEY_SIZE="4096"
				;;
			esac
			;;
		esac
		echo ""
		echo "Choose which cipher you want to use for the control channel:"
		case $CERT_TYPE in
		1)
			echo "   1) ECDHE-ECDSA-AES-128-GCM-SHA256 (recommended)"
			echo "   2) ECDHE-ECDSA-AES-256-GCM-SHA384"
			until [[ $CC_CIPHER_CHOICE =~ ^[1-2]$ ]]; do
				read -rp"Control channel cipher [1-2]: " -e -i 1 CC_CIPHER_CHOICE
			done
			case $CC_CIPHER_CHOICE in
			1)
				CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256"
				;;
			2)
				CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384"
				;;
			esac
			;;
		2)
			echo "   1) ECDHE-RSA-AES-128-GCM-SHA256 (recommended)"
			echo "   2) ECDHE-RSA-AES-256-GCM-SHA384"
			until [[ $CC_CIPHER_CHOICE =~ ^[1-2]$ ]]; do
				read -rp"Control channel cipher [1-2]: " -e -i 1 CC_CIPHER_CHOICE
			done
			case $CC_CIPHER_CHOICE in
			1)
				CC_CIPHER="TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256"
				;;
			2)
				CC_CIPHER="TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384"
				;;
			esac
			;;
		esac
		echo ""
		echo "Choose what kind of Diffie-Hellman key you want to use:"
		echo "   1) ECDH (recommended)"
		echo "   2) DH"
		until [[ $DH_TYPE =~ [1-2] ]]; do
			read -rp"DH key type [1-2]: " -e -i 1 DH_TYPE
		done
		case $DH_TYPE in
		1)
			echo ""
			echo "Choose which curve you want to use for the ECDH key:"
			echo "   1) prime256v1 (recommended)"
			echo "   2) secp384r1"
			echo "   3) secp521r1"
			while [[ $DH_CURVE_CHOICE != "1" && $DH_CURVE_CHOICE != "2" && $DH_CURVE_CHOICE != "3" ]]; do
				read -rp"Curve [1-3]: " -e -i 1 DH_CURVE_CHOICE
			done
			case $DH_CURVE_CHOICE in
			1)
				DH_CURVE="prime256v1"
				;;
			2)
				DH_CURVE="secp384r1"
				;;
			3)
				DH_CURVE="secp521r1"
				;;
			esac
			;;
		2)
			echo ""
			echo "Choose what size of Diffie-Hellman key you want to use:"
			echo "   1) 2048 bits (recommended)"
			echo "   2) 3072 bits"
			echo "   3) 4096 bits"
			until [[ $DH_KEY_SIZE_CHOICE =~ ^[1-3]$ ]]; do
				read -rp "DH key size [1-3]: " -e -i 1 DH_KEY_SIZE_CHOICE
			done
			case $DH_KEY_SIZE_CHOICE in
			1)
				DH_KEY_SIZE="2048"
				;;
			2)
				DH_KEY_SIZE="3072"
				;;
			3)
				DH_KEY_SIZE="4096"
				;;
			esac
			;;
		esac
		echo ""
		# The "auth" options behaves differently with AEAD ciphers
		if [[ $CIPHER =~ CBC$ ]]; then
			echo "The digest algorithm authenticates data channel packets and tls-auth packets from the control channel."
		elif [[ $CIPHER =~ GCM$ ]]; then
			echo "The digest algorithm authenticates tls-auth packets from the control channel."
		fi
		echo "Which digest algorithm do you want to use for HMAC?"
		echo "   1) SHA-256 (recommended)"
		echo "   2) SHA-384"
		echo "   3) SHA-512"
		until [[ $HMAC_ALG_CHOICE =~ ^[1-3]$ ]]; do
			read -rp "Digest algorithm [1-3]: " -e -i 1 HMAC_ALG_CHOICE
		done
		case $HMAC_ALG_CHOICE in
		1)
			HMAC_ALG="SHA256"
			;;
		2)
			HMAC_ALG="SHA384"
			;;
		3)
			HMAC_ALG="SHA512"
			;;
		esac
		echo ""
		echo "You can add an additional layer of security to the control channel with tls-auth and tls-crypt"
		echo "tls-auth authenticates the packets, while tls-crypt authenticate and encrypt them."
		echo "   1) tls-crypt (recommended)"
		echo "   2) tls-auth"
		until [[ $TLS_SIG =~ [1-2] ]]; do
			read -rp "Control channel additional security mechanism [1-2]: " -e -i 1 TLS_SIG
		done
	fi
	
	# Finally, ask for OTP enablement
	echo ""
	echo "Do you want to enable one-time-password authentication for your users?"
	echo "   1) Disable"
	echo "   2) Enable with Google Authenticator (recommended)"
	echo "   3) Enable with OATH Toolkit"
	until [[ $OTP =~ [1-3] ]]; do
		read -rp "OTP [1-3]: " -e -i 1 OTP
	done

	echo ""
	echo "Okay, that was all I needed. We are ready to setup your OpenVPN server now."
	echo "You will be able to generate a client at the end of the installation."
	APPROVE_INSTALL=${APPROVE_INSTALL:-n}
	if [[ $APPROVE_INSTALL =~ n ]]; then
		read -n1 -r -p "Press any key to continue..."
	fi
}

function getLatestEasyRSAVersion() {
	LATEST_EASYRSA_VERSION=$(curl -s https://api.github.com/repos/OpenVPN/easy-rsa/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')
	if [[ -z $LATEST_EASYRSA_VERSION ]]; then
		echo "Could not get the latest EasyRSA version."
		exit 1
	fi
	echo $LATEST_EASYRSA_VERSION
}

function installEasyRSA() {
	local version="${1}"
	if [[ -z $version ]]; then
		version=$(getLatestEasyRSAVersion)
	fi
	wget -O ~/easy-rsa.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v${version}/EasyRSA-${version}.tgz \
	&& mkdir -p /etc/openvpn/easy-rsa \
	&& tar xzf ~/easy-rsa.tgz --strip-components=1 --directory /etc/openvpn/easy-rsa \
	&& rm -f ~/easy-rsa.tgz || (echo "Could not download EasyRSA." && exit 1)
}

function installOpenVPN() {
	if [[ $AUTO_INSTALL == "y" ]]; then
		# Set default choices so that no questions will be asked.
		APPROVE_INSTALL=${APPROVE_INSTALL:-y}
		IPV4_SUPPORT=${IPV4_SUPPORT:-y}
		IPV6_SUPPORT=${IPV6_SUPPORT:-n}
		PORT_CHOICE=${PORT_CHOICE:-1}
		PROTOCOL_CHOICE=${PROTOCOL_CHOICE:-1}
		DNS=${DNS:-1}
		COMPRESSION_ENABLED=${COMPRESSION_ENABLED:-n}
		CUSTOMIZE_ENC=${CUSTOMIZE_ENC:-n}
		CLIENT=${CLIENT:-client}
		PASS=${PASS:-1}
		CONTINUE=${CONTINUE:-y}
		CLIENT_TO_CLIENT=${CLIENT_TO_CLIENT:-n}
		BLOCK_OUTSIDE_DNS=${BLOCK_OUTSIDE_DNS:-y}
		OTP=${OTP:-1}
		EASYRSA_CRL_DAYS=${EASYRSA_CRL_DAYS:-3650} # 10 years
		SUBNET_IPv4=${SUBNET_IPv4:-10.8.0.0}
		SUBNET_IPv6=${SUBNET_IPv6:-fd42:42:42::}
		SUBNET_MASKv4=${SUBNET_MASKv4:-24}
		SUBNET_MASKv6=${SUBNET_MASKv6:-112}
	fi

	# Run setup questions first, and set other variables if auto-install
	installQuestions

	# Get the "public" interface from the default route
	# For maximum compatibility (e.g. Alpine), we cannot use "grep -P", neither can use "ip route ls"
	NIC=$(ip -4 route show default | sed -ne 's/^default .* dev \([^ ]*\) .*$/\1/p')
	if [[ -z $NIC ]] && [[ $IPV6_SUPPORT == 'y' ]]; then
		NIC=$(ip -6 route show default | sed -ne 's/^default .* dev \([^ ]*\) .*$/\1/p')
	fi

	# $NIC can not be empty for script rm-openvpn-rules.sh
	if [[ -z $NIC ]]; then
		echo
		echo "Can not detect public interface."
		echo "This needs for setup MASQUERADE."
		until [[ $CONTINUE =~ (y|n) ]]; do
			read -rp "Continue? [y/n]: " -e CONTINUE
		done
		if [[ $CONTINUE == "n" ]]; then
			exit 1
		fi
	fi

	# If OpenVPN is not installed, we will not install it, it is up to the user to install it.
	if [[ ! -d /etc/openvpn/ ]]; then
		echo ""
		echo "OpenVPN does not seem to be installed. Please install it first."
		exit 1
	fi

	# Find out if the machine uses nogroup or nobody for the permissionless group
	if grep -qs "^nogroup:" /etc/group; then
		NOGROUP=nogroup
	else
		NOGROUP=nobody
	fi

	# Install the latest version of easy-rsa from source, if not already installed.
	if [[ ! -d /etc/openvpn/easy-rsa/ ]]; then
		updateEasyRSA

		cd /etc/openvpn/easy-rsa/ || return
		echo "set_var EASYRSA_VERSION ${version}" > vars
		case $CERT_TYPE in
		1)
			echo "set_var EASYRSA_ALGO ec" >>vars
			echo "set_var EASYRSA_CURVE $CERT_CURVE" >>vars
			;;
		2)
			echo "set_var EASYRSA_KEY_SIZE $RSA_KEY_SIZE" >>vars
			;;
		esac

		# Generate a random, alphanumeric identifier of 16 characters for CN and one for server name
		SERVER_CN="cn_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
		echo "$SERVER_CN" >SERVER_CN_GENERATED
		SERVER_NAME="server_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
		echo "$SERVER_NAME" >SERVER_NAME_GENERATED

		echo "set_var EASYRSA_REQ_CN $SERVER_CN" >>vars

		# Create the PKI, set up the CA, the DH params and the server certificate
		./easyrsa init-pki
		./easyrsa --batch build-ca nopass

		if [[ $DH_TYPE == "2" ]]; then
			# ECDH keys are generated on-the-fly so we don't need to generate them beforehand
			openssl dhparam -out dh.pem $DH_KEY_SIZE
		fi

		./easyrsa build-server-full "$SERVER_NAME" nopass
		./easyrsa gen-crl

		case $TLS_SIG in
		1)
			# Generate tls-crypt key
			openvpn --genkey --secret /etc/openvpn/tls-crypt.key
			;;
		2)
			# Generate tls-auth key
			openvpn --genkey --secret /etc/openvpn/tls-auth.key
			;;
		esac
	else
		# If easy-rsa is already installed, grab the generated SERVER_NAME
		# for client configs
		cd /etc/openvpn/easy-rsa/ || return
		SERVER_NAME=$(cat SERVER_NAME_GENERATED)
	fi

	# Move all the generated files
	cp pki/ca.crt pki/private/ca.key "pki/issued/$SERVER_NAME.crt" "pki/private/$SERVER_NAME.key" /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn
	if [[ $DH_TYPE == "2" ]]; then
		cp dh.pem /etc/openvpn
	fi

	# Make cert revocation list readable for non-root
	chmod 644 /etc/openvpn/crl.pem

	# Generate server.conf
	echo "# Automagically generated server.conf file" > /etc/openvpn/server.conf

	# Probably not needed at the moment, OpenVPN seems to be able to do this on its own
	# https://blog.djoproject.net/2019/10/19/configuring-a-dualstack-ipv4-ipv6-openvnp-2-4-server/
	# if [[ $IPV4_SUPPORT == "y" ]]; then
	# 	echo "local $ENDPOINT" >> /etc/openvpn/server.conf
	# elif [[ $IPV6_SUPPORT == "y" ]]; then
	# 	echo "local $ENDPOINT6" >> /etc/openvpn/server.conf
	# fi
	echo "port $PORT" >>/etc/openvpn/server.conf
	if [[ $IPV6_SUPPORT == 'n' ]]; then
		echo "proto $PROTOCOL" >>/etc/openvpn/server.conf
	elif [[ $IPV6_SUPPORT == 'y' ]]; then
		echo "proto ${PROTOCOL}6" >>/etc/openvpn/server.conf
	fi

	echo "dev tun
user nobody
group $NOGROUP
persist-key
persist-tun
keepalive 10 120
topology subnet
server ${SUBNET_IPv4} $(calc_subnet_mask $SUBNET_MASKv4)
ifconfig-pool-persist ipp.txt" >>/etc/openvpn/server.conf

	# Add client-to-client if enabled
	if [[ $CLIENT_TO_CLIENT == 'y' ]]; then
		echo "client-to-client" >>/etc/openvpn/server.conf
	fi

	# Add block-outside-dns if enabled
	if [[ $BLOCK_OUTSIDE_DNS == 'y' ]]; then
		echo "push block-outside-dns" >>/etc/openvpn/server.conf
	fi

	# DNS resolvers
	case $DNS in
	0) # Do not push any DNS
		;;
	1) # Current system resolvers
		# Locate the proper resolv.conf
		# Needed for systems running systemd-resolved
		if grep -q "127.0.0.53" "/etc/resolv.conf"; then
			RESOLVCONF='/run/systemd/resolve/resolv.conf'
		else
			RESOLVCONF='/etc/resolv.conf'
		fi
		# Obtain the resolvers from resolv.conf and use them for OpenVPN
		sed -ne 's/^nameserver[[:space:]]\+\([^[:space:]]\+\).*$/\1/p' $RESOLVCONF | while read -r line; do
			# Copy, if it's a IPv4 |or| if IPv6 is enabled, IPv4/IPv6 does not matter
			if [[ $line =~ ^[0-9.]*$ ]] || [[ $IPV6_SUPPORT == 'y' ]]; then
				echo "push \"dhcp-option DNS $line\"" >>/etc/openvpn/server.conf
			fi
		done
		;;
	2) # Cloudflare
		echo 'push "dhcp-option DNS 1.0.0.1"' >>/etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 1.1.1.1"' >>/etc/openvpn/server.conf
		;;
	3) # Quad9
		echo 'push "dhcp-option DNS 9.9.9.9"' >>/etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 149.112.112.112"' >>/etc/openvpn/server.conf
		;;
	4) # Quad9 uncensored
		echo 'push "dhcp-option DNS 9.9.9.10"' >>/etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 149.112.112.10"' >>/etc/openvpn/server.conf
		;;
	5) # FDN
		echo 'push "dhcp-option DNS 80.67.169.40"' >>/etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 80.67.169.12"' >>/etc/openvpn/server.conf
		;;
	6) # DNS.WATCH
		echo 'push "dhcp-option DNS 84.200.69.80"' >>/etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 84.200.70.40"' >>/etc/openvpn/server.conf
		;;
	7) # OpenDNS
		echo 'push "dhcp-option DNS 208.67.222.222"' >>/etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 208.67.220.220"' >>/etc/openvpn/server.conf
		;;
	8) # Google
		echo 'push "dhcp-option DNS 8.8.8.8"' >>/etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 8.8.4.4"' >>/etc/openvpn/server.conf
		;;
	9) # AdGuard DNS
		echo 'push "dhcp-option DNS 94.140.14.14"' >>/etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 94.140.15.15"' >>/etc/openvpn/server.conf
		;;
	10) # NextDNS
		echo 'push "dhcp-option DNS 45.90.28.167"' >>/etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 45.90.30.167"' >>/etc/openvpn/server.conf
		;;
	11) # Custom DNS
		echo "push \"dhcp-option DNS $DNS1\"" >>/etc/openvpn/server.conf
		if [[ $DNS2 != "" ]]; then
			echo "push \"dhcp-option DNS $DNS2\"" >>/etc/openvpn/server.conf
		fi
		;;
	esac
	echo 'push "redirect-gateway def1 bypass-dhcp"' >>/etc/openvpn/server.conf

	# IPv6 network settings if needed
	if [[ $IPV6_SUPPORT == 'y' ]]; then
		echo "server-ipv6 $SUBNET_IPv6/$SUBNET_MASKv6
tun-ipv6
push tun-ipv6
push \"route-ipv6 2000::/3\"
push \"redirect-gateway ipv6\"" >>/etc/openvpn/server.conf
	fi

	if [[ $COMPRESSION_ENABLED == "y" ]]; then
		echo "compress $COMPRESSION_ALG" >>/etc/openvpn/server.conf
	fi

	if [[ $DH_TYPE == "1" ]]; then
		echo "dh none" >>/etc/openvpn/server.conf
		echo "ecdh-curve $DH_CURVE" >>/etc/openvpn/server.conf
	elif [[ $DH_TYPE == "2" ]]; then
		echo "dh dh.pem" >>/etc/openvpn/server.conf
	fi

	case $TLS_SIG in
	1)
		echo "tls-crypt tls-crypt.key" >>/etc/openvpn/server.conf
		;;
	2)
		echo "tls-auth tls-auth.key 0" >>/etc/openvpn/server.conf
		;;
	esac

	echo "crl-verify crl.pem
ca ca.crt
cert $SERVER_NAME.crt
key $SERVER_NAME.key
auth $HMAC_ALG
cipher $CIPHER
ncp-ciphers $CIPHER
tls-server
tls-version-min 1.2
tls-cipher $CC_CIPHER
client-config-dir /etc/openvpn/ccd
status /var/log/openvpn/status.log
verb 3" >>/etc/openvpn/server.conf

	# Create client-config-dir dir
	mkdir -p /etc/openvpn/ccd
	# Create log dir
	mkdir -p /var/log/openvpn

	# If TOTP is enabled, add the plugin to the server config
	# Check if the plugin is installed locally or globally
	if [[ -r /usr/local/lib/openvpn/plugins/openvpn-plugin-auth-pam.so ]]; then
		PLUGIN_PATH="/usr/local/lib/openvpn/plugins/openvpn-plugin-auth-pam.so"
	elif [[ -r /usr/lib/openvpn/plugins/openvpn-plugin-auth-pam.so ]]; then
		PLUGIN_PATH="/usr/lib/openvpn/plugins/openvpn-plugin-auth-pam.so"
	elif [[ $OTP != "1" ]]; then
		echo "Error: openvpn-plugin-auth-pam.so not found!"
		exit 1
	fi
	if [[ $OTP != "1" ]]; then
		echo "plugin $PLUGIN_PATH openvpn" >>/etc/openvpn/server.conf
		echo "reneg-sec 0" >>/etc/openvpn/server.conf
	fi

	# Enable routing
	echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/99-openvpn.conf
	if [[ $IPV6_SUPPORT == 'y' ]]; then
		echo 'net.ipv6.conf.all.forwarding=1' >>/etc/sysctl.d/99-openvpn.conf
	fi
	# Apply sysctl rules
	sysctl --system

	# If SELinux is enabled and a custom port was selected, we need this
	if hash sestatus 2>/dev/null; then
		if sestatus | grep "Current mode" | grep -qs "enforcing"; then
			if [[ $PORT != '1194' ]]; then
				semanage port -a -t openvpn_port_t -p "$PROTOCOL" "$PORT"
			fi
		fi
	fi

	# Finally, restart and enable OpenVPN
	if [[ $OS == 'arch' || $OS == 'fedora' || $OS == 'centos' || $OS == 'oracle' ]]; then
		# Don't modify package-provided service
		cp /usr/lib/systemd/system/openvpn-server@.service /etc/systemd/system/openvpn-server@.service

		# Workaround to fix OpenVPN service on OpenVZ
		sed -i 's|LimitNPROC|#LimitNPROC|' /etc/systemd/system/openvpn-server@.service
		# Another workaround to keep using /etc/openvpn/
		sed -i 's|/etc/openvpn/server|/etc/openvpn|' /etc/systemd/system/openvpn-server@.service

		systemctl daemon-reload
		systemctl enable openvpn-server@server
		systemctl restart openvpn-server@server
	elif [[ $OS == "ubuntu" ]] && [[ $VERSION_ID == "16.04" ]]; then
		# On Ubuntu 16.04, we use the package from the OpenVPN repo
		# This package uses a sysvinit service
		systemctl enable openvpn
		systemctl start openvpn
	elif [[ $OS != 'other' ]]; then
		# Don't modify package-provided service
		cp /lib/systemd/system/openvpn\@.service /etc/systemd/system/openvpn\@.service

		# Workaround to fix OpenVPN service on OpenVZ
		sed -i 's|LimitNPROC|#LimitNPROC|' /etc/systemd/system/openvpn\@.service
		# Another workaround to keep using /etc/openvpn/
		sed -i 's|/etc/openvpn/server|/etc/openvpn|' /etc/systemd/system/openvpn\@.service

		systemctl daemon-reload
		systemctl enable openvpn@server
		systemctl restart openvpn@server
	fi

	# Add iptables rules in two scripts
	mkdir -p /etc/iptables

	# Script to add rules
	echo "#!/bin/sh
iptables -t nat -I POSTROUTING 1 -s ${SUBNET_IPv4}/${SUBNET_MASKv4} -o $NIC -j MASQUERADE
iptables -I INPUT 1 -i tun0 -j ACCEPT
iptables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT
iptables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT
iptables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >/etc/iptables/add-openvpn-rules.sh

	if [[ $IPV6_SUPPORT == 'y' ]]; then
		echo "ip6tables -t nat -I POSTROUTING 1 -s ${SUBNET_IPv6}/${SUBNET_MASKv6} -o $NIC -j MASQUERADE
ip6tables -I INPUT 1 -i tun0 -j ACCEPT
ip6tables -I FORWARD 1 -i $NIC -o tun0 -j ACCEPT
ip6tables -I FORWARD 1 -i tun0 -o $NIC -j ACCEPT
ip6tables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >>/etc/iptables/add-openvpn-rules.sh
	fi

	# Script to remove rules
	echo "#!/bin/sh
iptables -t nat -D POSTROUTING -s ${SUBNET_IPv4}/${SUBNET_MASKv4} -o $NIC -j MASQUERADE
iptables -D INPUT -i tun0 -j ACCEPT
iptables -D FORWARD -i $NIC -o tun0 -j ACCEPT
iptables -D FORWARD -i tun0 -o $NIC -j ACCEPT
iptables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >/etc/iptables/rm-openvpn-rules.sh

	if [[ $IPV6_SUPPORT == 'y' ]]; then
		echo "ip6tables -t nat -D POSTROUTING -s ${SUBNET_IPv6}/${SUBNET_MASKv6} -o $NIC -j MASQUERADE
ip6tables -D INPUT -i tun0 -j ACCEPT
ip6tables -D FORWARD -i $NIC -o tun0 -j ACCEPT
ip6tables -D FORWARD -i tun0 -o $NIC -j ACCEPT
ip6tables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >>/etc/iptables/rm-openvpn-rules.sh
	fi

	chmod +x /etc/iptables/add-openvpn-rules.sh
	chmod +x /etc/iptables/rm-openvpn-rules.sh

	# Handle the rules via a systemd script
	if [[ "$OS" != 'other' ]]; then
		echo "[Unit]
Description=iptables rules for OpenVPN
Before=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/add-openvpn-rules.sh
ExecStop=/etc/iptables/rm-openvpn-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target" >/etc/systemd/system/iptables-openvpn.service

		# Enable service and apply rules
		systemctl daemon-reload
		systemctl enable iptables-openvpn
		systemctl start iptables-openvpn
	fi

	# If the server is behind a NAT, use the correct IP address for the clients to connect to
	if [[ $ENDPOINT != "" ]]; then
		IP=$ENDPOINT
	fi

	# client-template.txt is created so we have a template to add further users later
	echo "client" >/etc/openvpn/client-template.txt
	if [[ $PROTOCOL == 'udp' ]]; then
		echo "proto udp" >>/etc/openvpn/client-template.txt
		echo "explicit-exit-notify" >>/etc/openvpn/client-template.txt
	elif [[ $PROTOCOL == 'tcp' ]]; then
		echo "proto tcp-client" >>/etc/openvpn/client-template.txt
	fi
	echo "remote $IP $PORT
dev tun
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verify-x509-name $SERVER_NAME name
auth $HMAC_ALG
auth-nocache
cipher $CIPHER
tls-client
tls-version-min 1.2
tls-cipher $CC_CIPHER
ignore-unknown-option block-outside-dns
setenv opt block-outside-dns # Prevent Windows 10 DNS leak
verb 3" >>/etc/openvpn/client-template.txt

	if [[ $COMPRESSION_ENABLED == "y" ]]; then
		echo "compress $COMPRESSION_ALG" >>/etc/openvpn/client-template.txt
	fi

	# Generate the custom client.ovpn
	newClient
	echo "If you want to add more clients, you simply need to run this script another time!"
}

function newClient() {
	echo ""
	echo "Tell me a name for the client."
	echo "The name must consist of alphanumeric character. It may also include an underscore or a dash."

	until [[ $CLIENT =~ ^[a-zA-Z0-9_-]+$ ]]; do
		read -rp "Client name: " -e CLIENT
	done

	echo ""
	echo "Do you want to protect the configuration file with a password?"
	echo "(e.g. encrypt the private key with a password)"
	echo "   1) Add a passwordless client"
	echo "   2) Use a password for the client"

	until [[ $PASS =~ ^[1-2]$ ]]; do
		read -rp "Select an option [1-2]: " -e -i 1 PASS
	done

	CLIENTEXISTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c -E "/CN=$CLIENT\$")
	if [[ $CLIENTEXISTS == '1' ]]; then
		echo ""
		echo "The specified client CN was already found in easy-rsa, please choose another name."
		exit
	else
		cd /etc/openvpn/easy-rsa/ || return
		case $PASS in
		1)
			./easyrsa build-client-full "$CLIENT" nopass
			;;
		2)
			echo "⚠️ You will be asked for the client password below ⚠️"
			./easyrsa build-client-full "$CLIENT"
			;;
		esac
		echo "Client $CLIENT added."
	fi

	# Home directory of the user, where the client configuration will be written
	if [ -e "/home/${CLIENT}" ]; then
		# if $1 is a user name
		homeDir="/home/${CLIENT}"
	elif [ "${SUDO_USER}" ]; then
		# if not, use SUDO_USER
		if [ "${SUDO_USER}" == "root" ]; then
			# If running sudo as root
			homeDir="/root"
		else
			homeDir="/home/${SUDO_USER}"
		fi
	else
		# if not SUDO_USER, use /root
		homeDir="/root"
	fi

	# Determine if we use tls-auth or tls-crypt
	if grep -qs "^tls-crypt" /etc/openvpn/server.conf; then
		TLS_SIG="1"
	elif grep -qs "^tls-auth" /etc/openvpn/server.conf; then
		TLS_SIG="2"
	fi

	# Determine if we need to activate TOTP for this client
	if grep -qs "^plugin.*openvpn-plugin-auth-pam.so" /etc/openvpn/server.conf; then
		# Ensure the otp folder is present
		[ -d /etc/openvpn/otp ] || mkdir -p /etc/openvpn/otp

		# Get SERVER_CN from easyrsa using sed
		SERVER_CN=$(sed -n 's/^set_var EASYRSA_REQ_CN[[:space:]]*//p' /etc/openvpn/easy-rsa/vars)

		# Everything needed is in the image, save to $CLIENT.google_authenticator file in /etc/openvpn/otp
		if [[ "$AUTO_INSTALL" == "y" ]]; then
			# Skip confirmation if running in auto install mode
			google-authenticator --time-based --disallow-reuse --force --rate-limit=3 --rate-time=30 --window-size=3 \
				-l "${CLIENT}@${SERVER_CN}" -s /etc/openvpn/otp/${CLIENT}.google_authenticator --no-confirm
		else
			# Authenticator will ask for other parameters. User can choose rate limit, token reuse policy and time window policy
			# Always use time base OTP otherwise storage for counters must be configured somewhere in volume
			google-authenticator --time-based --force -l "${CLIENT}@${SERVER_CN}" -s /etc/openvpn/otp/${CLIENT}.google_authenticator
		fi
	fi

	# Generates the custom client.ovpn
	cp /etc/openvpn/client-template.txt "$homeDir/$CLIENT.ovpn"
	{
		echo "<ca>"
		cat "/etc/openvpn/easy-rsa/pki/ca.crt"
		echo "</ca>"

		echo "<cert>"
		awk '/BEGIN/,/END/' "/etc/openvpn/easy-rsa/pki/issued/$CLIENT.crt"
		echo "</cert>"

		echo "<key>"
		cat "/etc/openvpn/easy-rsa/pki/private/$CLIENT.key"
		echo "</key>"

		case $TLS_SIG in
		1)
			echo "<tls-crypt>"
			cat /etc/openvpn/tls-crypt.key
			echo "</tls-crypt>"
			;;
		2)
			echo "key-direction 1"
			echo "<tls-auth>"
			cat /etc/openvpn/tls-auth.key
			echo "</tls-auth>"
			;;
		esac
	} >>"$homeDir/$CLIENT.ovpn"

	echo ""
	echo "The configuration file has been written to $homeDir/$CLIENT.ovpn."
	echo "Download the .ovpn file and import it in your OpenVPN client."

	# If temporary web server has been activated, display the link to the client config
	if [[ "$WEB_SERVER" == "y" ]]; then
		echo ""
		echo "You asked to activate a temporary web server to download the client config."
		echo "NOTE: After you download your client config, http server will be shut down!"

		# Check if we have `nc` installed
		if [[ ! -x "$(command -v nc)" ]]; then
			echo "ERROR: netcat is not installed. Please install it and try again."
			exit 1
		fi

		FILE_PATH="$homeDir/$CLIENT.ovpn"
		FILE_NAME=$(basename "$FILE_PATH")

		CONTENT_TYPE="application/text"
		
		echo ""
		echo "If you want to use the temporary web server, you can download the configuration file from:"
		echo "http://${IPV4_NETWORK}.${SERVER_HOST}/$CLIENT.ovpn"

		# Start a temporary web server to serve the client config
		{
			echo -ne "HTTP/1.1 200 OK\r\nContent-Length: $(wc -c <$FILE_PATH)\r\nContent-Type: $CONTENT_TYPE\r\nContent-Disposition: attachment; fileName=\"$FILE_NAME\"\r\nAccept-Ranges: bytes\r\n\r\n"; cat "$FILE_PATH";
		} | nc -w0 -l ${WEB_SERVER_PORT} -q0

		echo "HTTP server has been shut down."
	fi
}

function revokeClient() {
	NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")
	if [[ $NUMBEROFCLIENTS == '0' ]]; then
		echo ""
		echo "You have no existing clients!"
		exit 1
	fi

	echo ""
	echo "Select the existing client certificate you want to revoke"
	tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
	until [[ $CLIENTNUMBER -ge 1 && $CLIENTNUMBER -le $NUMBEROFCLIENTS ]]; do
		if [[ $CLIENTNUMBER == '1' ]]; then
			read -rp "Select one client [1]: " CLIENTNUMBER
		else
			read -rp "Select one client [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
		fi
	done
	CLIENT=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$CLIENTNUMBER"p)
	cd /etc/openvpn/easy-rsa/ || return
	./easyrsa --batch revoke "$CLIENT"
	EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
	rm -f /etc/openvpn/crl.pem
	cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
	chmod 644 /etc/openvpn/crl.pem
	find /home/ -maxdepth 2 -name "$CLIENT.ovpn" -delete
	rm -f "/root/$CLIENT.ovpn"
	sed -i "/^$CLIENT,.*/d" /etc/openvpn/ipp.txt
	cp /etc/openvpn/easy-rsa/pki/index.txt{,.bk}

	echo ""
	echo "Certificate for client $CLIENT revoked."
}

function resetOpenVPNConfig() {
	echo ""
	read -rp "Do you really want to remove OpenVPN config? [y/n]: " -e -i n REMOVE
	if [[ $REMOVE == 'y' ]]; then
		# Get OpenVPN port from the configuration
		PORT=$(grep '^port ' /etc/openvpn/server.conf | cut -d " " -f 2)
		PROTOCOL=$(grep '^proto ' /etc/openvpn/server.conf | cut -d " " -f 2)

		# Cleanup
		systemctl disable iptables-openvpn
		rm /etc/systemd/system/iptables-openvpn.service
		systemctl daemon-reload
		rm /etc/iptables/add-openvpn-rules.sh
		rm /etc/iptables/rm-openvpn-rules.sh

		# SELinux
		if hash sestatus 2>/dev/null; then
			if sestatus | grep "Current mode" | grep -qs "enforcing"; then
				if [[ $PORT != '1194' ]]; then
					semanage port -d -t openvpn_port_t -p "$PROTOCOL" "$PORT"
				fi
			fi
		fi

		# Cleanup
		echo "OVPN profiles will not be removed automatically by this script."
		echo "If you want to remove them, please do it manually:"
		echo "find /home/ -maxdepth 2 -name \"*.ovpn\" -delete"
		echo "find /root/ -maxdepth 1 -name \"*.ovpn\" -delete"
		rm -rf /etc/openvpn
		# rm -rf /usr/share/doc/openvpn*
		rm -f /etc/sysctl.d/99-openvpn.conf
		# rm -rf /var/log/openvpn

		echo ""
		echo "OpenVPN configuration removed!"
		echo "The original software as well as its logs have not been removed."
	else
		echo ""
		echo "Removal aborted!"
	fi
}

function updateEasyRSA() {
	# Get the latest EasyRSA version if none supplied
	if [[ -z $EASYRSA_VERSION ]]; then
		LATEST_EASYRSA_VERSION=$(getLatestEasyRSAVersion)
		echo "Found latest EasyRSA version $LATEST_EASYRSA_VERSION."
	else
		LATEST_EASYRSA_VERSION=$EASYRSA_VERSION
		echo "Force using EasyRSA version $LATEST_EASYRSA_VERSION."
	fi

	# Get the current EasyRSA version
	# We cannot use grep -Po because it's not available on all systems, use sed instead
	# First, check if we currently have a folder /etc/openvpn/easy-rsa
	CURRENT_EASYRSA_VERSION="unknown"
	if [[ -d /etc/openvpn/easy-rsa ]]; then
		# If we have a folder, check if it contains the file vars
		if [[ -f /etc/openvpn/easy-rsa/vars ]]; then
			# If we have the file vars, get the version from it
			CURRENT_EASYRSA_VERSION=$(sed -rn 's/^set_var EASYRSA_VERSION\s+(.+)$/\1/p' /etc/openvpn/easy-rsa/vars)
			# If we could not get the version, set it to unknown
			if [[ -z $CURRENT_EASYRSA_VERSION ]]; then
				CURRENT_EASYRSA_VERSION="unknown"
			fi
			echo "Found current EasyRSA version $CURRENT_EASYRSA_VERSION."
		fi
	fi

	echo ""
	echo "Current EasyRSA version is $CURRENT_EASYRSA_VERSION."

	# Check if EasyRSA is already up to date
	if [[ "$LATEST_EASYRSA_VERSION" == "$CURRENT_EASYRSA_VERSION" ]]; then
		echo "EasyRSA is already up to date."
		exit 0
	fi

	# Download the latest EasyRSA version
	installEasyRSA "$LATEST_EASYRSA_VERSION"

	# Append the version if not already installed, otherwise replace it
	if [[ "$CURRENT_EASYRSA_VERSION" == "unknown" ]]; then
		echo "set_var EASYRSA_VERSION $LATEST_EASYRSA_VERSION" >>/etc/openvpn/easy-rsa/vars
	else
		sed -i "s/^set_var EASYRSA_VERSION\s+.*/set_var EASYRSA_VERSION $LATEST_EASYRSA_VERSION/" /etc/openvpn/easy-rsa/vars
	fi

	# Tell user that the update was successful
	echo "EasyRSA updated from $CURRENT_EASYRSA_VERSION to $LATEST_EASYRSA_VERSION."
}

function manageMenu() {
	echo "Welcome to OpenVPN setup tool!"
	echo "The git repository is available at: https://github.com/oorabona/scripts/"
	echo ""
	echo "It looks like OpenVPN is already set up."
	echo ""
	echo "What do you want to do?"
	echo "   1) Add a new user"
	echo "   2) Revoke existing user"
	echo "   3) Update EasyRSA"
	echo "   4) Reset OpenVPN configuration"
	echo "   5) Exit"
	until [[ $MENU_OPTION =~ ^[1-5]$ ]]; do
		read -rp "Select an option [1-5]: " MENU_OPTION
	done

	case $MENU_OPTION in
	1)
		newClient
		;;
	2)
		revokeClient
		;;
	3)
		updateEasyRSA
		;;
	4)
		resetOpenVPNConfig
		;;
	5)
		exit 0
		;;
	esac
}

# Check for root, TUN, OS...
initialCheck

# Check if OpenVPN is already installed
if [[ -e /etc/openvpn/server.conf && $AUTO_INSTALL != "y" ]]; then
	manageMenu
else
	installOpenVPN

	# If we are here, OpenVPN is installed, we can start the service
	if [[ $AUTO_START == "y" && $OS == "other" ]]; then
		source /etc/iptables/add-openvpn-rules.sh
		openvpn --writepid /run/openvpn.pid --cd /etc/openvpn/ --config /etc/openvpn/server.conf
		source /etc/iptables/rm-openvpn-rules.sh
	fi
fi