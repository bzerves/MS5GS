```
  _____                    _       _   _____    _____    _____ 
 |  __ \                  (_)     | | | ____|  / ____|  / ____|
 | |__) |   __ _   _ __    _    __| | | |__   | |  __  | (___  
 |  _  /   / _\`| | '_ \  | |  / _\`| |___ \  | | |_ |  \___  \ 
 | | \ \  | (_| | | |_) | | | | (_| |  ___) | | |__| |  ____) |
 |_|  \_\  \__,_| | .__/  |_|  \__,_| |____/   \_____| |_____/ 
                  | |                                          
                  |_|                                          

```
# Rapid5GS

Rapid5GS is a comprehensive installation and configuration tool for Open5GS on Ubuntu 24.04 LTS or Debian 12. It automates the setup of a mobility core network using Open5GS, including all necessary dependencies and configurations.

## Prerequisites

- Ubuntu Server 24.04 LTS or Debian 12
- Root privileges (sudo access)
- Internet connection
- At least 4GB RAM
- At least 20GB free disk space
- At least 2 network interfaces (physical or virtual) on the server you're deploying this EPC on.

## Installation

1. Install Ubuntu Server 24.04 LTS or Debian on a server with two network interfaces.

2. Setup sudo utility and add your user to it.

3. Run the following one-liner command as a user with sudo privileges:
```bash
git clone https://github.com/joshualambert/rapid5gs.git && cd rapid5gs && chmod +x install.sh && sudo ./install.sh
```

## Installation Menu Options

The installation script provides the following options:

1. **Check System Requirements**
   - Verifies system compatibility
   - Confirms running on supported Debian 12 or Ubuntu 24.04 LTS Linux.
   - Validates network interfaces
   - Ensures sufficient RAM and storage

2. **Configure Installation**
   - Sets up network interfaces
   - Configures PLMN (MCC/MNC)
   - Creates necessary configuration files

3. **Install MongoDB**
   - Installs and configures MongoDB
   - Sets up the database for Open5GS

4. **Install NodeJS**
   - Installs NodeJS and npm
   - Required for the Web UI

5. **Install Open5GS**
   - Adds Open5GS PPA repository
   - Installs Open5GS core packages
   - Configures network interfaces
   - Sets up IP forwarding and firewall rules

6. **Install Open5GS Web UI**
   - Installs the web-based management interface
   - Configures web server

7. **Configure SSL with LetsEncrypt**
   - Sets up SSL certificates
   - Configures secure web access

8. **Health Check**
   - Verifies service status
   - Checks network connectivity
   - Validates configurations

9. **Reboot Services**
   - Restarts all Open5GS services
   - Applies configuration changes

10. **Exit**
    - Exits the installation script

## Usage

It is intended that you'll install Ubuntu Server 24.04 LTS or Debian 12 on a server with two network interfaces. Then run this script, one step at a time in order, to fully deploy this core. It is expected that the upstream routers from this EPC will assign both NICs a static IP address via DHCP. No need to configure those on the EPC itself - let routers route!

## Configuration Files

The following configuration files are created during installation:

- `/etc/open5gs/install.conf`: Main installation configuration
- `/etc/open5gs/mme.yaml`: MME configuration
- `/etc/open5gs/sgwc.yaml`: SGW-C configuration
- `/etc/open5gs/smf.yaml`: SMF configuration
- `/etc/open5gs/amf.yaml`: AMF configuration
- `/etc/open5gs/upf.yaml`: UPF configuration

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the GNU General Public License v3.0 - see the LICENSE file for details.

## Maintainer

- **Josh Lambert**
  - Website: [joshlambert.xyz](https://joshlambert.xyz)
  - Email: josh@lambertmail.xyz

## Acknowledgments

- Open5GS team for their work on building an open-source mobility code.
- David Peterson ([4GEngineer.com](https://4gengineer.com)) and Michael Halls ([nimbussolutions.org](https://nimbussolutions.org)) for teaching me the basics of LTE.
- Nick Jones ([omnitouch.co.au](https://omnitouch.co.au)) for helping me setup my first Open5GS core installation.
- Sarah Kerr ([isptechnology.ca](https://isptechnology.ca)) and Anthony Polsinelli ([cydrion.com](https://cydrion.com)) for lots of patience and help with networking the Mikrotik layer.

## Sponsored By

- [Centreville Tech, LLC](https://centrevilletech.com)
- [Alabama Lightwave, Inc.](https://alabamalightwave.com)

## Available For Hire

I'm available for hire to help deploy this EPC in your network. I also provide other network deployment services including:

- RF planning
- Tower construction
- Network design
- Marketing/sales support
- Software automation
- And more

Contact me for more information via email at josh@lambertmail.xyz.
