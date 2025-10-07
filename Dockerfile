FROM ubuntu:22.04

RUN apt-get update -y
RUN apt-get install -y \ 
  git vim pip sudo psmisc iputils-ping \
  software-properties-common libpcap-dev \
  libsystemd-dev pkg-config

# python-ndn
RUN pip install -U git+https://github.com/named-data/python-ndn.git
RUN git clone https://github.com/named-data/python-ndn.git

# ndn-cxx
RUN git clone https://github.com/named-data/ndn-cxx.git
RUN apt-get install -y build-essential libsqlite3-dev libboost-all-dev libssl-dev
RUN cd ndn-cxx && \
  ./waf configure && \
  ./waf && \
  ./waf install && \
  ldconfig

# NFD
RUN git clone --recursive https://github.com/named-data/NFD.git
ENV PKG_CONFIG_PATH=/custom/lib/pkgconfig
RUN cd NFD && \
  ./waf configure && \
  ./waf && \
  ./waf install
RUN cp /usr/local/etc/ndn/nfd.conf.sample /usr/local/etc/ndn/nfd.conf

# PSync
RUN git clone https://github.com/named-data/PSync.git
RUN cd PSync && \
  ./waf configure && \
  ./waf &&\
  ./waf install

# ndn-tools
RUN git clone https://github.com/named-data/ndn-tools.git
RUN cd ndn-tools && \
  ./waf configure && \
  ./waf && \
  ./waf install

ARG CACHE_BUSTER=9 #This is a hack to force the cache to be busted
# NLSR
#RUN git clone https://github.com/named-data/NLSR.git
#RUN git clone https://github.com/NekoWilliams/NLSR-fc.git
RUN git clone https://github.com/NekoWilliams/NLSR-fs.git
RUN cd NLSR-fs && \
  ./waf configure && \
  ./waf && \
  sudo ./waf install && \
  ldconfig
RUN mkdir -p /var/lib/nlsr/node1 /var/lib/nlsr/node2 /var/lib/nlsr/node3 /var/lib/nlsr/node4
RUN mkdir -p /var/log && chmod 755 /var/log

# ndn-svs
RUN git clone https://github.com/named-data/ndn-svs.git
RUN cd ndn-svs && \
  ./waf configure && \
  ./waf && \
  sudo ./waf install && \
  ./waf configure --enable-static --disable-shared --with-examples && \
  ./waf
