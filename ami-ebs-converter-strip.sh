#!/bin/bash

# Usage: ./ami-ebs-converter-strip.sh <instance ID of an existing EBS-backed linux instance> <name of the instance store AMI you're copying from> <name of the EBS-backed AMI you want to create>

instance=$1

isami=$2
ebsami=$3

access_key=$(aws configure get aws_access_key_id --profile YOURAWSPROFILE)
secret_access_key=$(aws configure get aws_secret_access_key --profile YOURAWSPROFILE)

echo Getting IP address for ${instance}...
ip=$(aws ec2 describe-instances --instance-id ${instance} | jq .Reservations[0].Instances[0].PrivateIpAddress)

echo Getting ImageID and location for ${isami}
isami_json=$(aws ec2 describe-images --filters 'Name="name",Values="'${isami}'"')
isami_id=$(echo $isami_json | jq -r .Images[0].ImageId)
isami_location=$(echo $isami_json | jq -r .Images[0].ImageLocation | sed -e 's/image.manifest.xml//')

echo Creating volume...
volume=$(aws ec2 create-volume --size 20 --region us-west-2 --availability-zone us-west-2b --profile YOURAWSPROFILE | jq -r .VolumeId)

sleep 5

echo -n Attaching volume ${volume} to ${instance}...
aws ec2 attach-volume --volume-id ${volume} --instance-id ${instance} --device /dev/xvdb --region us-west-2 --profile YOURAWSPROFILE || (echo Failed to attach ${volume} to ${instance}. ; exit 1)

# Wait for the volume to finish attaching
while [ "$(aws ec2 describe-volumes --volume-ids ${volume} --profile YOURAWSPROFILE --region us-west-2 | jq -r .Volumes[0].State)" != "in-use" ] ; do
  echo -n .
  sleep 2
done
echo

echo Beginning SSH session to ${ip}
ssh -t jump "ssh ec2-user@${ip} \
  \"echo Installing aws-cli, just in case && \
    sudo yum -y install aws-cli && \
    echo Making /tmp/cert && \
    sudo mkdir -p /tmp/cert ; \
    echo Copying private-key.pem && \
    sudo aws s3 cp s3://S3BUCKETWITHYOURCERTS/private-key.pem /tmp/cert/ && \
    echo Copying x509.pem && \
    sudo aws s3 cp s3://S3BUCKETWITHYOURCERTS/x509.pem /tmp/cert/ && \
    echo Making /tmp/bundle && \
    sudo mkdir -p /tmp/bundle ; \
    echo Grabbing ${isami} from S3 && \
    sudo RUBYLIB=/usr/lib/ruby/site_ruby/ /usr/local/bin/ec2-download-bundle -b ${isami_location} -m image.manifest.xml -a $access_key -s $secret_access_key --privatekey /tmp/cert/private-key.pem -d /tmp/bundle --region us-west-2  && \
    echo Unbundling... && \
    cd /tmp/bundle ; \
    sudo RUBYLIB=/usr/lib/ruby/site_ruby/ /usr/local/bin/ec2-unbundle -m image.manifest.xml --privatekey /tmp/cert/private-key.pem && \
    echo Using dd to copy bundle to ${volume}. This may take a while... && \
    sudo dd if=/tmp/bundle/image of=/dev/xvdb bs=1M && \
    echo Running partprobe... && \
    sudo partprobe /dev/xvdb && \
    echo Making /mnt/ebs... && \
    sudo mkdir -p /mnt/ebs ; \
    echo Mounting ${volume} to /mnt/ebs... && \
    sudo mount /dev/xvdb1 /mnt/ebs && \
    echo Removing ephemeral entries from fstab... && \
    sudo sed -i -e '/ephemeral/d' /mnt/ebs/etc/fstab && \
    echo Unmounting ${volume}... && \
    sudo umount /dev/xvdb1 && \
    echo Using sgdisk to move gpt backup... && \
    sudo sgdisk -e /dev/xvdb && \
    echo Deleting old partition... && \
    sudo sgdisk -d1 /dev/xvdb && \
    echo Creating new partition at maximum size... && \
    sudo sgdisk -N1 /dev/xvdb
    \""

echo Detaching volume...
aws ec2 detach-volume --volume-id ${volume} --region us-west-2 --profile YOURAWSPROFILE

# Wait for volume to detach
while [ "$(aws ec2 describe-volumes --volume-ids ${volume} --profile YOURAWSPROFILE --region us-west-2 | jq -r .Volumes[0].State)" != "available" ] ; do
  echo -n .
  sleep 2
done
echo

echo Creating snapshot...
snapshot_json=$(aws ec2 create-snapshot --volume-id ${volume} --description ${ebsami} --region us-west-2 --profile YOURAWSPROFILE)
snapshot_id=$(echo $snapshot_json | jq -r .SnapshotId)

# Wait for snapshot to complete
while [ "$(aws ec2 describe-snapshots --snapshot-ids ${snapshot_id} --profile YOURAWSPROFILE --region us-west-2 | jq -r .Snapshots[0].State)" != "completed" ] ; do
  echo -n .
  sleep 2
done

aws ec2 register-image --name ${ebsami} --virtualization-type hvm --profile YOURAWSPROFILE --region us-west-2 --root-device-name '/dev/xvda' --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"SnapshotId":"'${snapshot_id}'"}}]'
