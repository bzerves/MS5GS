  _____                    _       _   _____    _____    _____ 
 |  __ \                  (_)     | | | ____|  / ____|  / ____|
 | |__) |   __ _   _ __    _    __| | | |__   | |  __  | (___  
 |  _  /   / _\`| | '_ \  | |  / _\`| |___ \  | | |_ |  \___  \ 
 | | \ \  | (_| | | |_) | | | | (_| |  ___) | | |__| |  ____) |
 |_|  \_\  \__,_| | .__/  |_|  \__,_| |____/   \_____| |_____/ 
                  | |                                          
                  |_|                                          

# Rapid5GS

## What is a Mobility Core?

In mobile telecommunications, the Mobility Core (known as EPC in 4G or 5GC in 5G) is the central nervous system of your mobile network. It's responsible for:

- Managing user authentication and security
- Handling voice and data connections
- Routing traffic between users and the internet
- Managing network resources and quality of service
- Supporting mobility as users move between cells

Think of it as the "brain" of your mobile network - without it, your base stations (eNodeBs/gNodeBs) would be like disconnected islands with no way to communicate with each other or the outside world.

## The Problem

Setting up a mobile core network has traditionally been a nightmare:

1. **Commercial Solutions**: Enterprise-grade solutions from companies like Nokia, Ericsson, or Huawei, while powerful, require significant monetary investment and specialized expertise to deploy.

2. **Open Source Options**: While open-source solutions like Open5GS and Magma exist, they're notoriously difficult to configure. You need to:
   - Manually install dozens of dependencies
   - Configure complex networking rules
   - Set up databases and web interfaces
   - Deal with cryptic error messages
   - Spend days or weeks getting everything working

3. **Documentation**: Most documentation assumes you're already a mobility 4G/5G expert, making it nearly impossible for newcomers to get started.

## The Solution: Rapid5GS

Rapid5GS is a one-command solution that automates the entire process of setting up a production-ready Open5GS core network for fixed wireless operators. It:

- Works with both 4G (EPC) and 5G (5GC) networks
- Handles all dependencies automatically
- Configures networking and security
- Sets up monitoring and management tools
- Provides a user-friendly web interface
- Includes health checks and troubleshooting tools

### Quick Start

Just run this one command on Ubuntu 24.04 LTS or Debian 12:

```bash
git clone https://github.com/joshualambert/rapid5gs.git && cd rapid5gs && chmod +x install.sh && sudo ./install.sh
```

### System Requirements

- Ubuntu Server 24.04 LTS or Debian 12
- Root privileges (sudo access)
- At least 4GB RAM
- At least 20GB free disk space
- 2 physical network interfaces

> **IMPORTANT**: Rapid5GS is only tested and developed against fresh installations of Ubuntu 24.04 LTS or Debian 12. It is HIGHLY ADVISED to install this on a fresh copy of these operating systems before installing any other packages or making system modifications.

### Features

- **Automated Installation**: Step-by-step menu guides you through the entire process
- **Network Configuration**: Automatically sets up all required networking rules
- **Health Monitoring**: Built-in tools to monitor network performance and troubleshoot issues
- **Web Interface**: Easy-to-use dashboard for managing your network
- **Hybrid Support**: Works with both 4G and 5G networks simultaneously

### Network Control Interface

After installation, you can monitor and control your network using the built-in control interface:

```bash
chmod +x control.sh && sudo ./control.sh
```

The control interface provides several powerful tools:

1. **EPC Throughput Monitor**: Real-time view of network traffic and performance
2. **eNB Status**: Monitor connected base stations and their status
3. **UE Status**: Track connected user devices and their activities
4. **Live MME Logs**: Real-time monitoring of the Mobility Management Entity
5. **Live SMF Logs**: Real-time monitoring of the Session Management Function

This interface makes it easy to monitor your network's health and troubleshoot issues without diving into complex configuration files or logs.

### Current Limitations

- **NAT Mode Only**: Currently, the system only supports NAT mode for user traffic. All NAT operations are performed on the local machine.
- **Future Enhancements**: Support for routed IP pools and upstream NAT is planned for future releases.
- **Single Instance**: The current version is designed for single-instance deployment. Clustering support will be added in future releases.

### Supported Hardware

#### Base Stations (eNodeBs)
The following 4G base stations have been tested and verified to work with Rapid5GS:
- Airspan AirHarmony and AirSpeed units
- Nokia AZQC CBRS
- Baicells 436q and Nova 233

While theoretically any standards-compliant 4G eNodeB should work, only the above units have been thoroughly tested. 5G hardware support is planned but not yet tested.

#### User Equipment (UEs)
The following user devices have been tested and verified:
- Global Telecom Titan 4000 (our recommended choice for best performance)
- BEC RidgeWave
- Airspan AirSpot UEs

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
