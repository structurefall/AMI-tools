# AMI-tools

Some scripts to help automate making AMIs.

Presently, these presume you're using a jump/bastion host between your local machine and the target, which is just called "jump." I'll probably generalize that in the future. We also presume you have two S3 buckets- one with your x509 certs, and another to store instance store AMI content in.

This is only for linux hosts (I'm testing it on Amazon Linux, specifically,) and requires both the aws-cli package and the ec2 cli components.

There's a ton of generalization to be done before this is actually useful for almost anybody, but you can take a look now and possibly get some useful info.

## amibuild-is.sh

This guy takes an existing instance store-backed host and makes an AMI from it. It takes two arguments- the private IP for the instance and the name for the AMI you're making.

It uses ec2-bundle-vol to store the AMI bundle in /media/ephemeral0, then uploads it to S3 and registers the AMI as HVM. Future versions of this script will allow for paravirtualization.

## ami-ebs-converter-strip.sh

Once you're done building your instance store AMI, you may want to make an equivalent EBS one. In my case, I also want the EBS one to have a 20GB drive, which presents some weird challenges.

To use this script, you need three arguments: an instance id (ie, i-a11a1a1a or whatever,) the name of the instance store AMI you're basing it on, and the name of the EBS AMI you want to build.

The instance you use should be EBS-backed and running Linux- it otherwise shouldn't matter too much.

The script builds a new volume at 20GB (we'll make that variable in the future,) attaches it to the instance, then grabs the existing instance store AMI bundle and dds it to the drive. Once it's there, we clean up the ephemeral entries in fstab, fix the filesystem and partitions to fit the disk, then unmount, create a snapshot, and register the snapshot as hvm.


## TODO

These are nowhere near ready to go, although they work for my environment right now. We need to generalize a ton of things, add some error checking, make better usage comments, and automate out the actual host builds. The ultimate goal is to have a single command that takes an existing instance store host and makes both AMIs out of it with no additional user interaction.
