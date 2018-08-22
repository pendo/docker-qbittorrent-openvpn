FROM lsiobase/alpine:3.8

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="sparklyballs"

# package versions
ARG QBITTORRENT_VER="4.1.2"
ARG RASTERBAR_VER="1.1.9"

# add external volumes
VOLUME /downloads
VOLUME /config

# environment settings
#ENV HOME="/config" \
#XDG_CONFIG_HOME="/config" \
#SXDG_DATA_HOME="/config"


RUN \
 echo "**** install build packages ****" && \
 apk add --no-cache --virtual=build-dependencies \
	autoconf \
	automake \
	boost-dev \
	cmake \
	curl \
	file \
	g++ \
	geoip-dev \
	git \
	libtool \
	make \
	qt5-qttools-dev && \
 echo "**** install runtime packages ****" && \
 apk add --no-cache \
	boost-system \
	boost-thread \
	ca-certificates \
	dos2unix \
	ipcalc \	
	iptables \
	geoip \
	kmod \
	net-tools \
	openvpn \
	qt5-qtbase \
	unrar && \
 echo "**** compile libtorrent rasterbar ****" && \
 git clone https://github.com/arvidn/libtorrent.git /tmp/libtorrent && \
 cd /tmp/libtorrent && \
 RASTERBAR_REALVER=${RASTERBAR_VER//./_} && \
 git checkout "libtorrent-${RASTERBAR_REALVER}" && \
 ./autotool.sh && \
 ./configure \
	--disable-debug \
	--enable-encryption \
	--prefix=/usr && \
 make && \
 make install && \
 strip --strip-unneeded \
	/usr/lib/libtorrent-rasterbar.so* \
	/usr/lib/libtorrent-rasterbar.a* && \
 echo "**** compile qbittorrent ****" && \
 mkdir -p \
	/tmp/qbittorrent-src && \
 curl -o \
 /tmp/bittorrent.tar.gz -L \
	"https://github.com/qbittorrent/qBittorrent/archive/release-${QBITTORRENT_VER}.tar.gz" && \
 tar xf \
 /tmp/bittorrent.tar.gz -C \
	/tmp/qbittorrent-src --strip-components=1 && \
 cd /tmp/qbittorrent-src && \
 ./configure \
	--disable-gui \
	--prefix=/usr && \
 make && \
 make install && \
 echo "**** cleanup ****" && \
 apk del --purge \
	build-dependencies && \
 rm -rf \
	/tmp/*

# add local files
COPY root/ /
ADD openvpn/ /etc/openvpn/
ADD qbittorrent/ /etc/qbittorrent/


RUN chmod +x /etc/qbittorrent/*.sh /etc/qbittorrent/qbittorrent.init /etc/openvpn/*.sh


# Expose ports, volumes and run
EXPOSE 6881 6881/udp 8990
CMD ["/bin/bash", "/etc/openvpn/start.sh"]

