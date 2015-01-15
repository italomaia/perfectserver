#!/bin/sh

# The hostname for your mail server. This can be anything you like,
# however, it should match the public hostname as specified by your
# DNS records if you want to expose the server over the Internet.
HOSTNAME=example.com

# The password for the MySQL root user. You should pick something
# unique and secure; but something you can remember.
ROOTPASSWD=

# The password for the MySQL mail user. You should pick something
# unique and secure; you don’t even have to remember it beyond this
# tutorial.
MAILPASSWD=

# The password for the administrator e-mail account that you’ll
# create later in the guide.
ADMINPASSWD=

sudo su -
apt-get update
apt-get install -y mysql-server postfix postfix-mysql libsasl2-modules libsasl2-modules-sql libgsasl7 libauthen-sasl-cyrus-perl sasl2-bin libpam-mysql clamav-base libclamav6 clamav-daemon clamav-freshclam amavisd-new spamassassin spamc courier-base courier-authdaemon courier-authlib-mysql courier-imap courier-imap-ssl courier-pop courier-pop-ssl courier-ssl

groupadd virtual -g 5000
useradd -r -g "virtual" -G "users" -c "Virtual User" -u 5000 virtual
mkdir /var/spool/mail/virtual
chown virtual:virtual /var/spool/mail/virtual

mv /etc/postfix/main.cf{,.dist}
echo "
myorigin = /etc/mailname
smtpd_banner = \$myhostname ESMTP \$mail_name
biff = no
append_dot_mydomain = no
readme_directory = no
mydestination =
relayhost =
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mynetworks_style = host
mailbox_size_limit = 0
virtual_mailbox_limit = 0
recipient_delimiter = +
inet_interfaces = all
message_size_limit = 0

# SMTP Authentication (SASL)

smtpd_sasl_auth_enable = yes
broken_sasl_auth_clients = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain =

# Encrypted transfer (SSL/TLS)

smtp_use_tls = yes
smtpd_use_tls = yes
smtpd_tls_cert_file = /etc/ssl/private/mail.example.com.crt
smtpd_tls_key_file = /etc/ssl/private/mail.example.com.key
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache

# Basic SPAM prevention

smtpd_helo_required = yes
smtpd_delay_reject = yes
disable_vrfy_command = yes
smtpd_sender_restrictions = permit_sasl_authenticated, permit_mynetworks, reject
smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject

# Force incoming mail to go through Amavis

content_filter = amavis:[127.0.0.1]:10024
receive_override_options = no_address_mappings

# Virtual user mappings

alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
virtual_mailbox_base = /var/spool/mail/virtual
virtual_mailbox_maps = mysql:/etc/postfix/maps/user.cf
virtual_uid_maps = static:5000
virtual_gid_maps =  static:5000
virtual_alias_maps = mysql:/etc/postfix/maps/alias.cf
virtual_mailbox_domains = mysql:/etc/postfix/maps/domain.cf
" > /etc/postfix/main.cf

mv /etc/postfix/master.cf{,.dist}
echo "# Postfix master process configuration file.  For details on the format
# of the file, see the master(5) manual page (command: \"man 5 master\").
#
# Do not forget to execute \"postfix reload\" after editing this file.
#
# ==========================================================================
# service type  private unpriv  chroot  wakeup  maxproc command + args
#               (yes)   (yes)   (yes)   (never) (100)
# ==========================================================================
smtp      inet  n       -       -       -       -       smtpd
smtps     inet  n       -       -       -       -       smtpd
  -o smtpd_tls_wrappermode=yes
submission inet n       -       -       -       -       smtpd
pickup    fifo  n       -       -       60      1       pickup
  -o content_filter=
  -o receive_override_options=no_header_body_checks
cleanup   unix  n       -       -       -       0       cleanup
qmgr      fifo  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       -       1000?   1       tlsmgr
rewrite   unix  -       -       -       -       -       trivial-rewrite
bounce    unix  -       -       -       -       0       bounce
defer     unix  -       -       -       -       0       bounce
trace     unix  -       -       -       -       0       bounce
verify    unix  -       -       -       -       1       verify
flush     unix  n       -       -       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       -       -       -       smtp
# When relaying mail as backup MX, disable fallback_relay to avoid MX loops
relay     unix  -       -       -       -       -       smtp
    -o smtp_fallback_relay=
showq     unix  n       -       -       -       -       showq
error     unix  -       -       -       -       -       error
retry     unix  -       -       -       -       -       error
discard   unix  -       -       -       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       -       -       -       lmtp
anvil     unix  -       -       -       -       1       anvil
scache    unix  -       -       -       -       1       scache
#
# ====================================================================
# Interfaces to non-Postfix software. Be sure to examine the manual
# pages of the non-Postfix software to find out what options it wants.
#
# Many of the following services use the Postfix pipe(8) delivery
# agent.  See the pipe(8) man page for information about \${recipient}
# and other message envelope options.
# ====================================================================
#
# maildrop. See the Postfix MAILDROP_README file for details.
# Also specify in main.cf: maildrop_destination_recipient_limit=1
#
maildrop  unix  -       n       n       -       -       pipe
  flags=DRhu user=vmail argv=/usr/bin/maildrop -d \${recipient}
#
# See the Postfix UUCP_README file for configuration details.
#
uucp      unix  -       n       n       -       -       pipe
  flags=Fqhu user=uucp argv=uux -r -n -z -a\$sender - \$nexthop!rmail (\$recipient)
#
# Other external delivery methods.
#
ifmail    unix  -       n       n       -       -       pipe
  flags=F user=ftn argv=/usr/lib/ifmail/ifmail -r \$nexthop (\$recipient)
bsmtp     unix  -       n       n       -       -       pipe
  flags=Fq. user=bsmtp argv=/usr/lib/bsmtp/bsmtp -t\$nexthop -f\$sender \$recipient
scalemail-backend unix  -   n   n   -   2   pipe
  flags=R user=scalemail argv=/usr/lib/scalemail/bin/scalemail-store \${nexthop} \${user} \${extension}
mailman   unix  -       n       n       -       -       pipe
  flags=FR user=list argv=/usr/lib/mailman/bin/postfix-to-mailman.py
  \${nexthop} \${user}
amavis    unix -        -       -       -       2       smtp
  -o smtp_data_done_timeout=1200
  -o smtp_send_xforward_command=yes
  -o disable_dns_lookups=yes
  -o max_use=20
127.0.0.1:10025 inet n  -       -       -       -       smtpd
  -o content_filter=
  -o local_recipient_maps=
  -o relay_recipient_maps=
  -o smtpd_restriction_classes=
  -o smtpd_delay_reject=no
  -o smtpd_client_restrictions=permit_mynetworks,reject
  -o smtpd_helo_restrictions=
  -o smtpd_sender_restrictions=
  -o smtpd_recipient_restrictions=permit_mynetworks,reject
  -o smtpd_data_restrictions=reject_unauth_pipelining
  -o smtpd_end_of_data_restrictions=
  -o mynetworks=127.0.0.0/8
  -o smtpd_error_sleep_time=0
  -o smtpd_soft_error_limit=1001
  -o smtpd_hard_error_limit=1000
  -o smtpd_client_connection_count_limit=0
  -o smtpd_client_connection_rate_limit=0
  -o receive_override_options=no_header_body_checks,no_unknown_recipient_checks
" > /etc/postfix/master.cf

mkdir /etc/postfix/maps
echo "
user = mail
password = mailpassword
dbname = mail
table = alias
select_field = destination
where_field = source
hosts = 127.0.0.1
additional_conditions = AND `enabled` = 1
" > mkdir /etc/postfix/maps

echo "
user = mail
password = mailpassword
dbname = mail
table = domain
select_field = domain
where_field = domain
hosts = 127.0.0.1
additional_conditions = AND `enabled` = 1
" > /etc/postfix/maps/domain.cf

echo "
user = mail
password = mailpassword
dbname = mail
table = user
select_field = CONCAT(SUBSTRING_INDEX(`email`, "@", -1), "/", SUBSTRING_INDEX(`email`, "@", 1), "/")
where_field = email
hosts = 127.0.0.1
additional_conditions = AND `enabled` = 1
" > /etc/postfix/maps/user.cf

chmod 700 /etc/postfix/maps/*
chown postfix:postfix /etc/postfix/maps/*

usermod -aG sasl postfix
mkdir -p /etc/postfix/sasl

echo "
pwcheck_method: saslauthd
auxprop_plugin: sql
mech_list: plain login
sql_engine: mysql
sql_hostnames: 127.0.0.1
sql_user: mail
sql_passwd: mailpassword
sql_database: mail
sql_select: SELECT \`password\` FROM \`user\` WHERE \`email\` = \"%u@%r\" AND \`enabled\` = 1
" > /etc/postfix/sasl/smtpd.conf

mkdir -p /var/spool/postfix/var/run/saslauthd
mv /etc/default/saslauthd{,.dist}

echo "
START=yes
DESC=\"SASL Authentication Daemon\"
NAME=\"saslauthd\"
MECHANISMS=\"pam\"
MECH_OPTIONS=\"\"
THREADS=5
OPTIONS=\"-r -c -m /var/spool/postfix/var/run/saslauthd\"
" > /etc/default/saslauthd

echo "
auth    required   pam_mysql.so user=mail passwd=mailpassword host=127.0.0.1 db=mail table=user usercolumn=email passwdcolumn=password crypt=1
account sufficient pam_mysql.so user=mail passwd=mailpassword host=127.0.0.1 db=mail table=user usercolumn=email passwdcolumn=password crypt=1
" > /etc/pam.d/smtp

chmod 700 /etc/postfix/sasl/smtpd.conf
chmod 700 /etc/pam.d/smtp

mv /etc/courier/authdaemonrc{,.dist}

echo "
authmodulelist=\"authmysql\"
authmodulelistorig=\"authuserdb authpam authpgsql authldap authmysql authcustom authpipe\"
daemons=5
authdaemonvar=/var/run/courier/authdaemon
DEBUG_LOGIN=0
DEFAULTOPTIONS=\"\"
LOGGEROPTS=\"\"
" > /etc/courier/authdaemonrc

mv /etc/courier/authmysqlrc{,.dist}
echo "
MYSQL_SERVER localhost
MYSQL_USERNAME mail
MYSQL_PASSWORD mailpassword
MYSQL_PORT 0
MYSQL_DATABASE mail
MYSQL_USER_TABLE user
MYSQL_CRYPT_PWFIELD password
MYSQL_UID_FIELD 5000
MYSQL_GID_FIELD 5000
MYSQL_LOGIN_FIELD email
MYSQL_HOME_FIELD \"/var/spool/mail/virtual\"
MYSQL_MAILDIR_FIELD CONCAT(SUBSTRING_INDEX(\`email\`, \"@\", -1), \"/\", SUBSTRING_INDEX(\`email\`, \"@\", 1), \"/\")
MYSQL_NAME_FIELD name
MYSQL_QUOTA_FIELD quota
" > /etc/postfix/master.cf

mv /etc/courier/imapd{,.dist}
echo "
ADDRESS=0
PORT=143
MAXDAEMONS=40
MAXPERIP=20
PIDFILE=/var/run/courier/imapd.pid
TCPDOPTS="-nodnslookup -noidentlookup"
LOGGEROPTS="-name=imapd"
IMAP_CAPABILITY="IMAP4rev1 UIDPLUS CHILDREN NAMESPACE THREAD=ORDEREDSUBJECT THREAD=REFERENCES SORT QUOTA IDLE"
IMAP_KEYWORDS=1
IMAP_ACL=1
IMAP_CAPABILITY_ORIG="IMAP4rev1 UIDPLUS CHILDREN NAMESPACE THREAD=ORDEREDSUBJECT THREAD=REFERENCES SORT QUOTA AUTH=CRAM-MD5 AUTH=CRAM-SHA1 AUTH=CRAM-SHA256 IDLE"
IMAP_PROXY=0
IMAP_PROXY_FOREIGN=0
IMAP_IDLE_TIMEOUT=60
IMAP_MAILBOX_SANITY_CHECK=1
IMAP_CAPABILITY_TLS="$IMAP_CAPABILITY AUTH=PLAIN"
IMAP_CAPABILITY_TLS_ORIG="$IMAP_CAPABILITY_ORIG AUTH=PLAIN"
IMAP_DISABLETHREADSORT=0
IMAP_CHECK_ALL_FOLDERS=0
IMAP_OBSOLETE_CLIENT=0
IMAP_UMASK=022
IMAP_ULIMITD=65536
IMAP_USELOCKS=1
IMAP_SHAREDINDEXFILE=/etc/courier/shared/index
IMAP_ENHANCEDIDLE=0
IMAP_TRASHFOLDERNAME=Trash
IMAP_EMPTYTRASH=Trash:7
IMAP_MOVE_EXPUNGE_TO_TRASH=0
SENDMAIL=/usr/sbin/sendmail
HEADERFROM=X-IMAP-Sender
IMAPDSTART=YES
MAILDIRPATH=Maildir
" > /etc/courier/imapd

mv /etc/courier/imapd-ssl{,.dist}
echo "
SSLPORT=993
SSLADDRESS=0
SSLPIDFILE=/var/run/courier/imapd-ssl.pid
SSLLOGGEROPTS="-name=imapd-ssl"
IMAPDSSLSTART=YES
IMAPDSTARTTLS=YES
IMAP_TLS_REQUIRED=0
COURIERTLS=/usr/bin/couriertls
TLS_KX_LIST=ALL
TLS_COMPRESSION=ALL
TLS_CERTS=X509
TLS_CERTFILE=/etc/ssl/private/mail.example.com.pem
TLS_TRUSTCERTS=/etc/ssl/certs
TLS_VERIFYPEER=NONE
TLS_CACHEFILE=/var/lib/courier/couriersslcache
TLS_CACHESIZE=524288
MAILDIRPATH=Maildir
" > /etc/courier/imapd-ssl

mv /etc/courier/pop3d{,.dist}
echo "
PIDFILE=/var/run/courier/pop3d.pid
MAXDAEMONS=40
MAXPERIP=4
POP3AUTH=\"LOGIN\"
POP3AUTH_ORIG=\"PLAIN LOGIN CRAM-MD5 CRAM-SHA1 CRAM-SHA256\"
POP3AUTH_TLS=\"LOGIN PLAIN\"
POP3AUTH_TLS_ORIG=\"LOGIN PLAIN\"
POP3_PROXY=0
PORT=110
ADDRESS=0
TCPDOPTS=\"-nodnslookup -noidentlookup\"
LOGGEROPTS=\"-name=pop3d\"
POP3DSTART=YES
MAILDIRPATH=Maildir
" > mv /etc/courier/pop3d

mv /etc/courier/pop3d-ssl{,.dist}
echo "
SSLPORT=995
SSLADDRESS=0
SSLPIDFILE=/var/run/courier/pop3d-ssl.pid
SSLLOGGEROPTS=\"-name=pop3d-ssl\"
POP3DSSLSTART=YES
POP3_STARTTLS=YES
POP3_TLS_REQUIRED=0
COURIERTLS=/usr/bin/couriertls
TLS_STARTTLS_PROTOCOL=TLS1
TLS_KX_LIST=ALL
TLS_COMPRESSION=ALL
TLS_CERTS=X509
TLS_CERTFILE=/etc/ssl/private/mail.example.com.pem
TLS_TRUSTCERTS=/etc/ssl/certs
TLS_VERIFYPEER=NONE
TLS_CACHEFILE=/var/lib/courier/couriersslcache
TLS_CACHESIZE=524288
MAILDIRPATH=Maildir
" > mv /etc/courier/pop3d-ssl

openssl req -x509 -newkey rsa:1024 -keyout "/etc/ssl/private/mail.$HOSTNAME.pem" -out "/etc/ssl/private/mail.$HOSTNAME.pem" -nodes -days 3650
openssl req -new -outform PEM -out "/etc/ssl/private/mail.$HOSTNAME.crt" -newkey rsa:2048 -nodes -keyout "/etc/ssl/private/mail.$HOSTNAME.key" -keyform PEM -days 3650 -x509
chmod 640 /etc/ssl/private/mail.$HOSTNAME.*
chgrp ssl-cert /etc/ssl/private/mail.$HOSTNAME.*

echo "
use strict;

\$log_level = 1;
\$syslog_priority = 'info';
\$sa_kill_level_deflt = 6.5;
\$final_spam_destiny = D_DISCARD;
\$pax = 'pax';

@bypass_virus_checks_maps = (\%bypass_virus_checks, \@bypass_virus_checks_acl, \$bypass_virus_checks_re);
@bypass_spam_checks_maps = (\%bypass_spam_checks, \@bypass_spam_checks_acl, \$bypass_spam_checks_re);
@local_domains_acl = qw(.);

1;
" > /etc/amavis/conf.d/50-user

mv /etc/default/spamassassin{,.dist}
echo "
ENABLED=1
OPTIONS=\"--create-prefs --max-children 5 --helper-home-dir\"
PIDFILE=\"/var/run/spamd.pid\"
CRON=0
" > mv /etc/default/spamassassin

dpkg-reconfigure clamav-freshclam

mysql -u root --password=$ROOTPASSWORD -e "
CREATE DATABASE `mail`;
GRANT ALL ON `mail`.* TO "mail"@"localhost" IDENTIFIED BY "mailpassword";

FLUSH PRIVILEGES;
USE `mail`;

CREATE TABLE IF NOT EXISTS `alias` (
  `source` VARCHAR(255) NOT NULL,
  `destination` VARCHAR(255) NOT NULL DEFAULT "",
  `enabled` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`source`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `domain` (
  `domain` VARCHAR(255) NOT NULL DEFAULT "",
  `transport` VARCHAR(255) NOT NULL DEFAULT "virtual:",
  `enabled` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`domain`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `user` (
  `email` VARCHAR(255) NOT NULL DEFAULT "",
  `password` VARCHAR(255) NOT NULL DEFAULT "",
  `name` VARCHAR(255) DEFAULT NULL,
  `quota` INT UNSIGNED DEFAULT NULL,
  `enabled` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
"
