# suspend_disk
If hdparm does not work again.

I have often had the problem that hdparm does not automatically put the hard disk into sleep mode. This script is supposed to help.

# Dependencies
```
inotify-tools
```

# Usage:
## Required parameters:
* -p [PATH]       Path to which the device is mounted.
* -d [PATH]       Hard disk which is to be controlled.

## Optional parameters:
* -t [INT]        Time in minutes after which the device is suspended. Current: 45m
* -o [INT]        Time in seconds the control loop sleeps. Events cannot be missed. Current: 30s
                Higher values reduce the cpu load, the number of outputs and the trigger commands.
* -m              Alternative method to query the status of the hard disk if it does not support smartctl.
                Note that this method may wake up the hard disk.
* -a [CMD]        Command which is executed once after the hard disk has been turned on.
                Is influenced by the time of the control loop.
* -s [CMD]        Command which is executed once after the hard disk has been turned off.
                Is influenced by the time of the control loop.

# Tips:
- try to keep the spin-up and spin-down cycles as low as possible
- test both status methods and make sure that the chosen method does not wake the hard disk
- use quotas for the triggered commands e.g. 'echo "hi"'.
- you may have to increase watches use:  echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf                                                                                                   
- the smartd service may have to be changed or deactivated use: systemctl disable smartd
- the gnome file tracker-store may wack up the drive
