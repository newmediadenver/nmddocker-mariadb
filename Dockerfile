FROM newmedia/centos
ADD RPM-GPG-KEY-MariaDB /etc/pki/rpm-gpg/RPM-GPG-KEY-MariaDB
ADD etc /etc
RUN \
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-MariaDB && \
yum install -y MariaDB-server MariaDB-client && \
yum clean all
VOLUME ["/etc/my.cnf.d", "/var/lib/mysql"]
#CMD ["/usr/sbin/php-fpm", "-F"]
EXPOSE 3306
