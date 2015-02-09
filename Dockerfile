FROM newmedia/centos

ADD RPM-GPG-KEY-MariaDB /etc/pki/rpm-gpg/RPM-GPG-KEY-MariaDB
ADD etc /etc

RUN \
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-MariaDB && \
yum install -y MariaDB-server MariaDB-client && \
yum clean all

COPY run.sh /run.sh

ENV TERM xterm

VOLUME ["/etc/my.cnf.d", "/var/lib/mysql"]
WORKDIR /data
CMD ["/run.sh"]
EXPOSE 3306
