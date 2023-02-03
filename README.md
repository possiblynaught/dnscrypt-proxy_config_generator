Generates a .toml config file for dnscrypt-proxy2 with random ODoH and Anonymous DNSCrypt server/relay configs

## NOTE

Modified listen address in example-dnscrypt-proxy.toml:
listen_addresses = ['127.0.0.53:53']

## TODO

- [x] Copy a base toml to dir
- [ ] Figure out why the pipefail is showing error
- [ ] Finish standard dnscrypt config
- [ ] Finish readme + guide
- [ ] Use a case statement or something else to handle command line args
