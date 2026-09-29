import configparser
import os
import sys

nm, root = sys.argv[1], sys.argv[2]
c = configparser.ConfigParser(interpolation=None)
c.read(nm)
ssid = c["wifi"]["ssid"]
sec = c["wifi-security"] if c.has_section("wifi-security") else {}
km = sec.get("key-mgmt", "none")
psk = sec.get("psk")
if km not in ("wpa-psk", "sae") or not psk:
    sys.exit(f"unsupported: key-mgmt={km!r}, psk stored in file: {bool(psk)}")
d = os.path.join(root, "etc/NetworkManager/system-connections")
os.makedirs(d, mode=0o700, exist_ok=True)
os.chmod(d, 0o700)
path = os.path.join(d, os.path.basename(nm))
body = f"[connection]\nid={ssid}\ntype=wifi\n\n[wifi]\nssid={ssid}\n\n[wifi-security]\nkey-mgmt={km}\npsk={psk}\n\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n"
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.write(fd, body.encode())
os.close(fd)
print(path)
