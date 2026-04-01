#!/usr/bin/env python3
"""
Proxmox VM Snapshot Script
Takes a snapshot of all running VMs via the Proxmox API
"""

import requests
import urllib3
import yaml
import json
import sys
from datetime import datetime

# Disable SSL warnings for self-signed cert
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# --- Load config ---
def load_config(path="config.yaml"):
    with open(path, "r") as f:
        return yaml.safe_load(f)

# --- Authenticate and get ticket ---
def get_auth_ticket(config):
    url = f"https://{config['host']}:8006/api2/json/access/ticket"
    response = requests.post(url, data={
        "username": config['username'],
        "password": config['password']
    }, verify=False)
    
    if response.status_code != 200:
        print(f"Auth failed: {response.status_code}")
        sys.exit(1)
    
    data = response.json()['data']
    return {
        "ticket": data['ticket'],
        "csrf": data['CSRFPreventionToken']
    }

# --- Get all VMs ---
def get_vms(config, auth):
    url = f"https://{config['host']}:8006/api2/json/nodes/{config['node']}/qemu"
    response = requests.get(
        url,
        cookies={"PVEAuthCookie": auth['ticket']},
        verify=False
    )

    print("VM list status:", response.status_code)
    print("VM list body:", response.text)

    if response.status_code != 200:
        print(f"Failed to get VMs: {response.status_code}")
        sys.exit(1)

    data = response.json().get("data")
    if data is None:
        print("API returned no VM data")
        sys.exit(1)

    return data
# --- Take snapshot ---
def take_snapshot(config, auth, vmid, snapname):
    url = f"https://{config['host']}:8006/api2/json/nodes/{config['node']}/qemu/{vmid}/snapshot"
    response = requests.post(url,
        data={
            "snapname": snapname,
            "description": f"Auto snapshot {datetime.now().strftime('%Y-%m-%d %H:%M')}"
        },
        cookies={"PVEAuthCookie": auth['ticket']},
        headers={"CSRFPreventionToken": auth['csrf']},
        verify=False
    )
    return response.status_code == 200

# --- Main ---
def main():
    config = load_config()
    auth = get_auth_ticket(config)
    vms = get_vms(config, auth)
    
    snapname = f"auto_{datetime.now().strftime('%Y%m%d_%H%M')}"
    
    results = []
    for vm in vms:
        # Only snapshot running VMs
        if vm['status'] != 'running':
            continue
        
        vmid = vm['vmid']
        name = vm.get('name', f'vm-{vmid}')
        success = take_snapshot(config, auth, vmid, snapname)
        status = "✅" if success else "❌"
        results.append(f"{status} {name} (ID: {vmid})")
        print(f"{status} Snapshot taken for {name}")
    
    print(f"\nSnapshot summary ({snapname}):")
    for r in results:
        print(f"  {r}")

if __name__ == "__main__":
    main()
