# rhel10_imagemode
Containerfile and playbooks to manage bootc imagemode rhel10 deployment

This is a demonstration of a basic lifecycle workflow of managing an immutable RHEL deployment.  An immutable operating system is a system where the core components, such as the operating system files, configurations, and applications, are read-only and cannot be modified during runtime. This design enhances security and reproducibility by preventing unintended or malicious changes to the system. Because the image only contains the bare minimum needed to run containers and the binaries are read only this enhances security by limiting the number of things available to attack and preventing modifing system binaries.  The only writable directories are /etc and /var, where /var is used to map user directories and application data.  The following steps are covered:

  - Building initial boot image / container
  - Launching it as a VM locally 
  - Injecting repository credentials into image so it can get updates
  - Registering system and enabling Red Hat Insights
  - Using Quadlet to run an Nginx server
  - Build a new version of the base image with updates
  - Update system with the new image
  - Rollback system to previous version

You'll need a container registry account like quay.io to push and pull containers from.  The builds also must be run from a registered RHEL system (i.e. where you've run **subscription-manager register**) or you can also install subscription manager on OS's in the RHEL ecosystem like fedora and register that way.  If you are a mac user ssh to your podman vm (which is a fedora-core image that has subscription manager available) and run your podman commands natively on the fedora vm, not from the mac cli which has problems with sudo commands.  When you run podman build ithe container you create will inheret your access to the appropriate repos needed to do things like dnf update. 

#for mac users to login to the the podman machine (usually podman-machine-default)

```bash
podman machine ssh --username core
```
#note this user core has sudo access
# Setting up
To run this demo sucessfully you'll need a Red Hat user account (available for free at developers.redhat.com), a subscribed fedora or RHEL system to build things, podman and ansible, and some repository access to put your images - I use quay.io.  You'll also need some way to run a qcow2 image as a VM, you can use libvirt on RHEL or on Mac I use UTM.


git clone this repo
```bash
git clone https://github.com/edhaynes/rhel10_imagemode.git
```
Make sure your build system is subscribed
```bash
sudo subscription-manager register
```
Login to applicable registries

```bash
podman login quay.io
sudo podman login quay.io
podman login registry.redhat.io
sudo podman login registry.redhat.io
```



The image you'll create will have two user accounts, **core** and **redhat**.  **core** is defined in the **config.json** file, where you also should **change the password and put your public ssh key**.  **redhat** is created in the containerfile, and we will pass the password we define in **password.txt** at build time so the Containerfile doesn't contain the plaintext password.  Note this **password.txt** file should not have a returnline at the end, should strictly be the characters of your password. 
Edit your config.json to reflect your password for core and your public ssh key.  Edit password.txt for password
```bash
vi config.json
```
Define password for user **redhat** somewhere in a directory outside of git put a password.txt with your preferred password and give it permissions 600.  This account is not used for anything in this tutorial but is used to show how you can pass passwords into your containerfile without exposing them.

Build the initial bootable container image and push to repo.  Note this command needs to be run from directory with Containerfile in it.
We're defining a --secret id redhat-password with the path to your password.txt.  Podman build temporarily mounts this at build time then unmounts it so your plaintext password doesn't end up in the image.

```bash
podman build   --secret id=redhat-password,src=/path/to/password.txt   -t quay.io/youraccount/imagemode:1.0 .
```
```bash
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
Now that we have a bootable qcow2 image lets run it in a VM.

```bash
sudo cp ./qcow2/disk.qcow2 /var/lib/libvirt/images/imagemode.qcow2
```
```bash
virt-install \
  --name r10_imagemode \
  --memory 2048 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/imagemode.qcow2,format=qcow2 \
  --import \
  --os-variant rhel10.0 \
  --noautoconsole \
  --noautostart
```
```bash
sudo virsh start r10_imagemode
```
```bash
sudo virsh --connect qemu:///session console r10_imagemode
```
You can login to the system using user **core** and the password you defined earlier in config.json.
# Running VM on ARM based mac using UTM

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

If you're running this in a home lab I'd recommend using a bridged network connection so it gets a local IP address you can connect to PHP and Nginx servers your image is running.

# Prepping for Ansible
We are going to do some lifecycle events with ansible playbooks, so go into the /ansible directory and update the **inventory.yml** file to reflect the ip addr of your VM and also the location of your private ssh key.  You put the public ssh key into the config.json before you built, right?

# Injecting repository credentials
Updates to the system are done "atomically", you rebuild the original containerfile, bringing in any software updates and changes, and push it to your container registry with a new version number.  You'll use ansible to do a "**bootc switch**" pointing to the new image, and reboot to get the updates.  In image mode RHEL you can also choose to roll back to a previous image.  When this happens any changes to /var (user accounts & app data) persist across rollback but any config changes to /etc are discarded.  This can be very useful if you did something in /etc that prevented you from booting successfully, one time I messed up SELinux configuration and was able to boot to old image to recover.

A playbook "**inject_creds.yml**" is provided to update your booted image with your repository credentials. One thing that initially confused me was where to put quay auth credentials so that bootc switch command could access the repo.  It turned out putting the credentials in "**/etc/ostree/auth.json**" did the trick. We are going to create robot credentials that only expose your desired repo on quay.io and encrypt them into ansible vault, so we can have a playbook that doesn't expose your quay credentials when you run it.  

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
The "become" password will be the password for **core** you defined up in config.json since we're using the **core** account to run the playbook.  The Vault password is whatever you defined it as when you did your **ansible-vault encrypt**.  This encryption of your credentials helps prevent exposure if your build environment gets posted in a public place.  

# Registering System and enabling Red Hat Insights

Red Hat insights is a useful way to monitor and provide, well, insights to your deployed RHEL10 imagemode VM.  To enable this update the **/vars/rhsm_secrets.yml** file with you Red Hat login and password.  If you don't have a Red Hat account it's easy to get one at developer.redhat.com that has a few subscriptions you can experiment with.
```bash
ansible-vault encrypt vars/rhsm_secrets.yml
```
Run the ansible playbook to register system to your account and enable insights.
```bash
ansible-playbook -i inventory.yml rhsm_register.yml --ask-become --ask-vault-pass
```
Now you should be able to see your instance at https://console.redhat.com/insights


# Using Quadlet to run an Nginx server

Quadlet is a perfect fit for immutable OSs, you keep a small, hardened base image and then deploy applications on it using Quadlet.  Quadlet is a way to define applications in a container like fashion and have podman autogenerate the applicable files to run it via **systemd** at runtime.   To do this you put a quadlet file in any of several locations, depending if you want the app to run with user permissions or as a system service.  A playbook is provided to launch an Nginx server on your RHEL10 imagemode vm and map it to port 8080.  If you looked at the original containerfile you'll notice a PHP server on port 80 as well.  If you bridge your VM connection you should be able to browse to it locally, http://yourvmip:80 for the PHP server and http://yourvmip:8080 for Nginx.  For mac users Chrome has strict security policies with localnetwork stuff so use Safari to test.  Have a look at the playbook it's a simple but powerful way to run applications.  If you want to change what Nginx displays you would simply update the quadlet.yml file and rerun the ansible playbook.

To run the quadlet file:
```bash
ansible-playbook -i inventory.yml quadlet.yml --ask-become
```

# Build a new version of the base image with updates

Now lets say a new CVE comes out and you wish to update the base image, or you wish to tweak the content PHP server displays.  You just podman build the original containerfile, tag it with the appropriate version number, and push it to the repo.  An ansible playbook is provided to run "bootc switch" to change to whatever version you wish.  In this example I use flag "--pull-always" to get the latest revision of RHEL10 from the repo so I get the latest CVE fixes.  

From directory with Containerfile
```bash
podman build  --pull-always --secret id=redhat-password,src=./password.txt   -t quay.io/ehaynes/imagemode:1.1 .
```
```bash
podman push quay.io/ehaynes/imagemode:1.1
```
# Update to new image
Now run ansible playbook that switches to version 1.1.  RHEL will stage this update and boot into it when it reboots, playbook automatically reboots if there is a change.  First edit bootc_update.yml to update "bootc_image: quay.io/ehaynes/imagemode:1.1" to reflect your repository location and version you wish to switch to.
```bash
ansible-playbook -i inventory.yml bootc_update.yml --ask-become
```
If this is a new version the playbook will automatically reboot you into the new image.  If you get an error about registery permissions double check that your quay.io robot credentials have access to the repo you're trying to access.

# Rollback to old image 
If for some reason there is an issue with the new image `sudo bootc rollback` from the VM command line will take you back to your old image. Alternately in the grub bootloader you could also choose the old image.  In this case any changes to /etc will be discarded, and any changes to /var (home directory and app data) gets carried forward.  Now lets say you wished to keep both your /etc and /var layers but move back to the old image.  This is also possible by simply doing a `sudo bootc switch quay.io/ehaynes/imagemode1.0`.  In this case because the old version is "staged" it will have /var carried forward and /etc merged in to the new image during the stage.  If you like you could create a systemd task that upon upgrades checks the health of your application, and if application health dies automatically do a **bootc rollback**.  This ability to do rollbacks is very powerful for preventing outages due to dumb mistakes.  There is also the capability (not covered here) to "pin" certain images, like your failback always works image, so they are always available.  They do take storage, but since they are stored locally they are always available even if you had connectivity problems with your repo.

# Other cool stuff
Since you want to keep your immutable image as small as possible you might not install common debugging tools like tcpdump.  How can you have access to these tools for debugging sessions?  There is a cool utility called "toolbox" that downloads and runs a container (with very permissive permissions so be careful) that you can use to run debugging tools.  Since this container has DNF installed you can install tools like tcpdump and use them to debug.  Here is an example below:

```
[core@localhost ~]$ sudo toolbox enter
[core@localhost ~]$ sudo toolbox enter
No Toolbx containers found. Create now? [y/N] y
Image required to create Toolbx container.
Download registry.access.redhat.com/ubi10/toolbox:10.0 (245.2MB)? [y/N]: y

Welcome to the Toolbx; a container where you can install and run
all your tools.

 - To create a new tools container, run 'toolbox create'.

⬢ [root@toolbx ~]# which tcpdump
/usr/bin/which: no tcpdump in (/root/.local/bin:/root/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin)
⬢ [root@toolbx ~]# sudo dnf install tcpdump
```

# Conclusion
Hope this gave you a flavor of how to accomplish some day to day activities on RHEL10 image mode.  You might notice that I never needed to login to the image to tweek anything via cli and did all state changes from ansible playbooks.  If you can adhere to this dicipline it makes it very easy to scale your deployment and prevent "snowflake" systems.  Let me know if you run into issues or have suggestions to improve this tutorial.






