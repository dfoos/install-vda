# Citrix VDA and WEM Installation Script

## Overview

This PowerShell script automates the installation of Citrix Virtual Delivery Agent (VDA) and optionally Workspace Environment Management (WEM) on a remote Windows server. It handles various scenarios including Windows Server 2012 compatibility, PrintNightmare vulnerability fix, and multiple installation attempts if necessary.

## Prerequisites

- PowerShell 5.0 or later
- Administrative access to the target remote server
- Network access to the software share containing Citrix installation files
- Citrix Cloud Connectors set up and accessible

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| ServerName | string | Name of the remote server to install VDA/WEM on |
| SoftwareShareRoot | string | Root path of the software share on the network |
| CloudConnectors | string | Space-separated list of Cloud Connectors for VDA installation |
| InstallWEM | switch | (Optional) Install WEM after VDA installation |

## Usage

### Basic VDA Installation

```powershell
.\Install-CitrixVDA.ps1 -ServerName "SERVER01" -SoftwareShareRoot "\\SHARE\CitrixInstall" -CloudConnectors "CC01 CC02"
