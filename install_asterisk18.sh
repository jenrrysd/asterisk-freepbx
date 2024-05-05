#!/bin/bash

while :
do
echo "Escoga una opcion "
echo "1.- INSTALACION DE ASTERISK-18, ACTUALIZACION Y REBOOT.  "
echo "2.- INSTALACION DE FREEPBX-16.  "
echo "3.- CREACION DE DOMINIO CON LETSENCRYPT "
echo "4.- SALIR DEL SCRIPT "

echo -n "SU OPCION ELEGIDA ES => "
read opcion
case $opcion in
#
1) echo "INSTALACION DE ASTERISK-18, ACTUALIZACION Y REBOOT "
#
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
updatedb

dnf group -y install "Development Tools"

dnf -y install git wget vim curl mlocate net-tools sqlite-devel psmisc ncurses-devel newt-devel libxml2-devel libtiff-devel gtk2-devel libtool libuuid-devel subversion kernel-devel gcc-c++ bzip2 crontabs cronie-anacron libedit libedit-devel sendmail sendmail-cf

dnf -y install cronie sqlite-devel net-tools gnutls-devel unixODBC

##INSTALL JANSSON##
git clone https://github.com/akheron/jansson.git
cd jansson
autoreconf -i
./configure --prefix=/usr/
make
make install
cd

##install dahdi-linux
git clone https://github.com/asterisk/dahdi-linux.git
cd dahdi-linux
make
make install
cd

##install dahdi-tools
git clone https://github.com/asterisk/dahdi-tools.git
autoreconf -f -i
./configure
make all
make install
make
cd

##install libpri
git clone https://github.com/asterisk/libpri
make all
make install
cd

##INSTALL PJSIP
cd
git clone https://github.com/pjsip/pjproject.git
cd pjproject
./configure CFLAGS="-DNDEBUG -DPJ_HAS_IPV6=1" --prefix=/usr --libdir=/usr/lib64 --enable-shared --disable-video --disable-sound --disable-opencore-amr
make dep
make
make install
ldconfig

##INSTALL ASTERISK
cd
wget https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-18-current.tar.gz
tar -xf asterisk-18-current.tar.gz
cd asterisk-18.*/
./configure
#make
#./menuselect/menuselect --enable cdr_mysql --enable res_config_mysql --enable codec_opus --enable app_mysql --enable  chan_ooh323 --enable format_mp3 --enable app_macro --enable CORE-SOUNDS-EN-WAV --enable CORE-SOUNDS-EN-ULAW --enable CORE-SOUNDS-EN-ALAW --enable CORE-SOUNDS-EN-GSM --enable CORE-SOUNDS-EN-G729 --enable CORE-SOUNDS-EN-G722 --enable CORE-SOUNDS-EN-SLN16 --enable MOH-OPSOUND-WAV --enable MOH-OPSOUND-ULAW --enable MOH-OPSOUND-ALAW --enable MOH-OPSOUND-GSM --enable MOH-OPSOUND-G729 menuselect.makeopts

#./configure --libdir=/usr/lib64
./contrib/scripts/install_prereq install
#contrib/scripts/get_mp3_source.sh

make
make install
make samples
make config
make install-logrotate
ldconfig

##HORA LIMA-PERU
ln -sf /usr/share/zoneinfo/America/Lima /etc/localtime

##crear usuario asterisk separado y correrlo
groupadd asterisk
useradd -r -d /var/lib/asterisk -g asterisk asterisk
usermod -aG audio,dialout asterisk
chown -R asterisk:asterisk /etc/asterisk /var/{lib,log,spool}/asterisk /usr/lib64/asterisk

##vim /etc/sysconfig/asterisk
sed -i 's/#AST_USER="asterisk"/AST_USER="asterisk"/' /etc/sysconfig/asterisk
sed -i 's/#AST_GROUP="asterisk"/AST_GROUP="asterisk"/' /etc/sysconfig/asterisk

##vim /etc/asterisk/asterisk.conf
sed -i 's/;runuser = asterisk/runuser = asterisk/' /etc/asterisk/asterisk.conf
sed -i 's/;rungroup = asterisk/rungroup = asterisk/' /etc/asterisk/asterisk.conf
echo "astpidfile = /var/run/asterisk/asterisk.pid" >> /etc/asterisk/asterisk.conf
##################---HASTA AQUI INSTALACIÓN DE ASTERISK----########

########--INSTALL PAQUETES NECESARIOS PARA FREEPBX--###############
dnf -y groupinstall  "Development Tools"
dnf -y install ncurses-devel sendmail sendmail-cf newt-devel libxml2-devel libtiff-devel gtk2-devel subversion kernel-devel git crontabs cronie cronie-anacron sqlite-devel gnutls-devel unixODBC

##--INSTALL MARIADB--##
dnf -y install mariadb mariadb-server
systemctl enable --now mariadb

#systemctl start mariadb

mysql_secure_installation << 'EOF'

y
asterisk
asterisk
y
y
y
y
EOF

###crear base de datos asterisk , asteriskcdrdb
echo "CREATE DATABASE asterisk;" | mysql -u root -pasterisk
echo "CREATE DATABASE asteriskcdrdb;" | mysql -u root -pasterisk
echo "GRANT ALL PRIVILEGES ON asterisk.* TO 'freepbxuser'@'localhost' IDENTIFIED BY 'freepbxpassword';" | mysql -u root -pasterisk
echo "GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO 'freepbxuser'@'localhost' IDENTIFIED BY 'freepbxpassword';" | mysql -u root -pasterisk
echo "FLUSH PRIVILEGES;" | mysql -u root -pasterisk

####--INSTALL NODE.JS LTS--#####
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

nvm install 12
nvm use 12
node --version

###--INSTALL-APACHE--###
dnf -y install httpd
rm -rf /var/www/html/index.html
systemctl enable --now httpd
firewall-cmd --add-service={http,https} --permanent
firewall-cmd --reload

###--INSTALL PHP EXTENSIONS REQUERIDOS--####
dnf -y install yum-utils
dnf -y install https://rpms.remirepo.net/fedora/remi-release-39.rpm
dnf module -y reset php
dnf module -y install php:remi-7.4

dnf install -y php php-pear php-cgi php-common php-curl php-mbstring php-gd php-mysqlnd php-gettext php-bcmath php-zip php-xml php-json php-process php-snmp

sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 20M/' /etc/php.ini

systemctl enable php-fpm httpd
systemctl start php-fpm httpd

sed -i 's/\(^memory_limit = \).*/\1128M/' /etc/php.ini
sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/httpd/conf/httpd.conf
sed -i 's/AllowOverride None/AllowOverride All/' /etc/httpd/conf/httpd.conf
sed -i 's/\(^user = \).*/\1asterisk/' /etc/php-fpm.d/www.conf
sed -i 's/\(^group = \).*/\1asterisk/' /etc/php-fpm.d/www.conf
sed -i 's/\(^listen.acl_users = \).*/\1apache,nginx,asterisk/' /etc/php-fpm.d/www.conf

systemctl restart php-fpm httpd

cd /var/www/
wget http://mirror.freepbx.org/modules/packages/freepbx/7.4/freepbx-16.0-latest.tgz
tar xfz freepbx-16.0-latest.tgz
cd freepbx


##recargar
dnf install initscripts -y
systemctl start asterisk
chown asterisk:asterisk /root/.asterisk_history
systemctl restart asterisk
systemctl status asterisk
systemctl enable asterisk
systemctl daemon-reload

chown -R asterisk:asterisk /etc/asterisk/
chown -R asterisk:asterisk /var/lib/asterisk/
chown -R asterisk:asterisk /var/spool/asterisk/
chown -R asterisk:asterisk /var/log/asterisk/
chown -R asterisk:asterisk /usr/lib/asterisk/
chown -R asterisk:asterisk /var/run/asterisk/
chown -R asterisk:asterisk /var/lib/php/

##ACTUALIZAR Y REINICIAR
dnf update -y
reboot

echo "REINICIANDO SERVIDOR "
echo "Continua con la opción 2 "

;;

2) echo "INSTALACION DE FREEPBX "

pear install Console_Getopt
systemctl stop asterisk
cd /var/www/freepbx
./start_asterisk start
./install -n
#./install --webroot=/var/www/html -n --dbuser root --dbpass asterisk

##INSTALL FREEPBX MODULES
dnf -y install npm
fwconsole ma install mp2
fwconsole ma disablerepo commercial
fwconsole ma installall
##fwconsole ma delete firewall
fwconsole reload
fwconsole restart

systemctl restart httpd php-fpm

tee /etc/systemd/system/freepbx.service <<EOF
[Unit]
Description=FreePBX VoIP Server
After=mariadb.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/fwconsole start -q
ExecStop=/usr/sbin/fwconsole stop -q
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable freepbx

;;

###########-DOMINIO Y letsencript ssl-#############
3) echo "CREACION DE DOMINIO CON LETSENCRIPT "

dnf -y install certbot python3-certbot-apache

read -p "Escribe tu dominio y dale enter; " dominio

tee /etc/httpd/conf.d/$dominio.conf<<EOF
<VirtualHost *:80>
DocumentRoot /var/www/html
ServerName $dominio
       <Directory /var/www/html>
                Options Indexes FollowSymLinks MultiViews
                AllowOverride All
                Order allow,deny
                allow from all
                RewriteEngine On
        </Directory>
</VirtualHost>
EOF

certbot --apache

systemctl restart httpd php-fpm


echo "Ahora puedes verificar el nombre de tu dominio "
echo "https://$dominio "

;;

4) echo "OPCION 4 SALIR DEL SCRIPT" ; exit 0

esac
done
