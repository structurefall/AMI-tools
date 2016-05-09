#!/bin/bash

# Usage: ./amibuild-is.sh <private IP address of base host> <name for your new AMI>

ip=$1

aminame=$2

access_key=$(aws configure get aws_access_key_id --profile YOURAWSPROFILE)
secret_access_key=$(aws configure get aws_secret_access_key --profile YOURAWSPROFILE)
export RUBYLIB=/usr/lib/ruby/site_ruby/

ssh -t jump "ssh ec2-user@${ip} \
  \"echo Making /tmp/cert && \
  sudo mkdir -p /tmp/cert ; \
  echo Copying private-key.pem && \
  sudo aws s3 cp s3://S3BUCKETWITHYOURCERTS/private-key.pem /tmp/cert/ && \
  echo Copying x509.pem && \
  sudo aws s3 cp s3://S3BUCKETWITHYOURCERTS/x509.pem /tmp/cert/ && \
  echo Running ec2-bundle-vol
  sudo RUBYLIB=/usr/lib/ruby/site_ruby/ /usr/local/bin/ec2-bundle-vol -c /tmp/cert/x509.pem -k /tmp/cert/private-key.pem -u 8673-0600-3235 -r x86_64 -e /tmp/cert --include /etc/pki/tls/cert.pem,/etc/ec2/amitools/cert-ec2.pem -d /media/ephemeral0/ && \
  RUBYLIB=/usr/lib/ruby/site_ruby/ /usr/local/bin/ec2-upload-bundle -b S3BUCKETTOSTOREAMISIN/${aminame} -m /media/ephemeral0/image.manifest.xml -a ${access_key} -s ${secret_access_key} --region us-west-2\""

echo Running ec2 register-image
aws ec2 register-image --image-location S3BUCKETTOSTOREAMISIN/${aminame}/image.manifest.xml --name ${aminame} --virtualization-type hvm --region us-west-2 --profile YOURAWSPROFILE
