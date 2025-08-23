# rhel10_imagemode
Containerfile and playbooks to manage bootc imagemode rhel10 deployment

This is a demonstration of a basic lifecycle workflow of managing an immutable RHEL deployment.  An immutable operating system is a system where the core components, such as the operating system files, configurations, and applications, are read-only and cannot be modified during runtime. This design enhances security and reproducibility by preventing unintended or malicious changes to the system. The only writable directories are /etc and /var, where /var is used to map user directories and application data.  The following steps are covered:

  - Building initial boot image / container
  - Launching it as a VM locally 
  - Injecting repository credentials into image so it can get updates
  - Registering system and enabling Red Hat Insights
  - Using Quadlet to run an Nginx server, update it with changes
  - Build a new version of the base image with updates
  - Update system with the new image
  - Rollback system to previous version

You'll need a container registry account like quay.io to push and pull containers from.  This also needs to be run from a registered RHEL system (i.e. where you've run subscription-manager --register) or you can also install subscription manager on OS's in the RHEL ecosystem like fedora and register that way.  If you are a mac user ssh to your podman vm (which is a fedora-core image that has subscription manager available) and run your podman commands natively on the fedora vm, not from the mac cli which has problems with sudo commands.  You can do this with 

#for mac peeps

```bash
podman machine ssh --username core
```
#note this user core has sudo access

First login to applicable registries

```bash
podman login quay.io
sudo podman login quay.io
podman login registry.redhat.io
sudo podman login registry.redhat.io
```
git clone this repo
```bash
git clone https://github.com/edhaynes/rhel10_imagemode.git
```

This image will have two user accounts, core and redhat.  core is defined in the config.json file, where you also should change the password and put your own public ssh key.  redhat is created in the containerfile, and we will pass the password we define in password.txt at build time so the Containerfile doesn't contain the plaintext password.  

Define password for user redhat.  Somewhere in a directory outside of git put a password.txt with your preferred password and give it permissions 600.

Build the initial bootable container image and push to repo.  Note this command needs to be run from directory with Containerfile in it.
We're defining a --secret id redhat-password with the path to your password.txt.  Podman build temporarily mounts this at build time then unmounts it so your plaintext password doesn't end up in the image.

```bash
podman build   --secret id=redhat-password,src=/path/to/password.txt   -t quay.io/youraccount/imagemode:1.0 .

podman push quay.io/youraccount/imagemode:1.0
```

Now build a qcow2 bootdisk for your VM where you'll run this first image.  This does need sudo permissions and since run as sudo won't see the local build done by user account we'll download it from quay repo.
```bash
sudo podman pull quay.io/youraccount/imagemode:1.0
```
#modify below line to use your linux username, your container registry, and target arch (i.e. for ARM based mac --target-arch arm64)
```bash
sudo podman run --rm --name imagemode-bootc-image-builder --tty --privileged --security-opt label=type:unconfined_t -v /var/home/core/rhel10_imagemode:/output/ -v /var/lib/containers/storage:/var/lib/containers/storage -v /var/home/core/rhel10_imagemode/config.json:/config.json:ro --label bootc.image.builder=true registry.redhat.io/rhel10/bootc-image-builder:latest quay.io/youraccount/imagemode:1.0 --output /output/ --progress verbose --type qcow2 --target-arch amd64 --chown 1000:1000
```
# Running VM on linux

```bash
cp ./qcow2/disk.qcow2 /var/lib/libvirt/.
```
```bash
virt-install   --name r10_imagemode   --memory 2048   --vcpus 2   --disk path=/var/lib/libvirt/images/imagemode.qcow2,format=qcow2   --import   --os-variant rhel10.0   --noautoconsole
```
```bash
sudo virsh --connect qemu:///session start r10_imagemode
```
```bash
sudo virsh --connect qemu:///session console r10_imagemode
```

# Running on ARM based mac using UTM

1. Download the .qcow2 file: From Mac:
   ```bash
   podman machine cp podman-machine-default:/var/home/core/rhel10_imagemode/qcow2/disk.qcow2 .
   ```
2. Create a New VM in UTM:
Open UTM and click the "Create New Virtual Machine" button. 
Select "Virtualize"  
Choose "Other" as the operating system. 
On the next screen, change the boot device to "None"
Select 1GB for the disk volume, this will be deleted later 
3. Import the .qcow2 file:
When the VM settings screen comes up, go to the "Drives" section. 
Delete the default drive that was created automatically. 
Click "New" and select "virtio". 
Choose the "Import" option and select your downloaded .qcow2 file. 
Save and boot your vm

# Injecting repository credentials
Updates to the system are done "atomically", you rebuild the original containerfile, bringing in any software updates and changes, and push it to your container registry with a new version number.  You'll use ansible to do a "bootc switch" pointing to the new image, and reboot to get the updates.  In image mode RHEL you can also choose to roll back to a previous image.  When this happens any changes to /var (user accounts & app data) persist across rollback but any config changes to /etc are discarded.  

A playbook "inject_creds.yml" is provided to update your booted image with your repository credentials. We are going to create robot credentials that only expose your desired repo on quay.io and encrypt them into ansible vault, so we can have a playbook that doesn't expose your quay credentials when you run it.  

Login to Quay.io, click your login name under "Users and Organizations", and you should see a list of your repositories.

In the upper left you will see a grey icon that looks like a robot(when you hover over it says 'robot accounts').  Click it.

Click Create Robot Account, and provide name and description.  In my case I'll use "jasper" for the name.

Select the repo you used to push your bootable container image, give it read permissions, then click add permissions button.

Now you can click your robot account and copy your name and token.

Edit the vars/quay_secrets.yml file with your credentials then encrypt with
```bash
ansible-vault encrypt vars/quay_secrets.yml
```
You will be asked for a password you will use to decrypt when running playbook.

Run playbook with
```bash
ansible-playbook -i inventory.yml inject_creds.yml --ask-become --ask-vault-pass
```

# Registering System and enabling Red Hat Insights










