#!/bin/bash -xe

export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/opt/aws/bin:/root/bin

yum update -y
yum install -y gcc libffi-devel openssl-devel

# credstash installation for secrets
pip install -U pip
/usr/local/bin/pip install -U credstash awscli

echo "* hard nofile 64000" >> /etc/security/limits.conf
echo "* soft nofile 64000" >> /etc/security/limits.conf
echo "root hard nofile 64000" >> /etc/security/limits.conf
echo "root soft nofile 64000" >> /etc/security/limits.conf

cat <<EOF > /etc/yum.repos.d/mongodb-org-3.2.repo
[mongodb-org-3.2]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2013.03/mongodb-org/3.2/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-3.2.asc
EOF

cat <<EOF > /etc/yum.repos.d/pritunl.repo
[pritunl]
name=Pritunl Repository
baseurl=http://repo.pritunl.com/stable/yum/centos/7/
gpgcheck=1
enabled=1
EOF

gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 7568D9BB55FF9E5287D586017AE645C0CF8E292A
gpg --armor --export 7568D9BB55FF9E5287D586017AE645C0CF8E292A > key.tmp; sudo rpm --import key.tmp; rm -f key.tmp

yum install -y pritunl mongodb-org
service mongod status || service mongod start

chkconfig mongod on

start pritunl || true

cd /tmp
curl https://amazon-ssm-eu-west-1.s3.amazonaws.com/latest/linux_amd64/amazon-ssm-agent.rpm -o amazon-ssm-agent.rpm
yum install -y amazon-ssm-agent.rpm
status amazon-ssm-agent || start amazon-ssm-agent

cat <<EOF > /usr/sbin/mongobackup.sh
#!/bin/bash -e

export PATH="/usr/local/bin:\$PATH"
export BACKUP_ENCRYPTION_KEY=\$(credstash --region ${aws_region} --table ${credstash_table_name} get BACKUP_ENCRYPTION_KEY)
export BACKUP_TIME=\$(date +'%Y-%m-%d-%H-%M-%S')
export BACKUP_FILENAME="\$BACKUP_TIME-pritunl-db-backup.tar.gz"
export BACKUP_DEST="/tmp/\$BACKUP_TIME"
mkdir "\$BACKUP_DEST" && cd "\$BACKUP_DEST"
mongodump -d pritunl
tar zcf "\$BACKUP_FILENAME" dump
rm -rf dump
gpg --yes --batch --passphrase="\$BACKUP_ENCRYPTION_KEY" -c "\$BACKUP_FILENAME"
md5sum "\$BACKUP_FILENAME" > "\$BACKUP_FILENAME.md5"
rm "\$BACKUP_FILENAME"
aws s3 sync . s3://${s3_backup_bucket}/backups/
cd && rm -rf "\$BACKUP_DEST"
EOF
chmod 700 /usr/sbin/mongobackup.sh

cat <<EOF > /etc/cron.daily/pritunl-backup
#!/bin/bash -e
export PATH="/usr/local/bin:\$PATH"
/usr/sbin/mongobackup.sh && curl -fsS --retry 3 "https://hchk.io/\$(credstash --region ${aws_region} --table ${credstash_table_name} get HEALTHCHECKS_IO_KEY)"
EOF
chmod 755 /etc/cron.daily/pritunl-backup

cat <<EOF > /etc/logrotate.d/pritunl
/var/log/mongodb/*.log {
  daily
  missingok
  rotate 60
  compress
  delaycompress
  copytruncate
  notifempty
}
EOF

cat <<EOF > /home/ec2-user/.bashrc
# https://twitter.com/leventyalcin/status/852139188317278209
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi
EOF
