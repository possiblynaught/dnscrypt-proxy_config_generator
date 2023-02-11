# dnscrypt-proxy config generator

Generates a .toml config file for [dnscrypt-proxy 2](https://github.com/DNSCrypt/dnscrypt-proxy) with random ODoH and Anonymous DNS server/relay configs.

## USE

To run this standalone config generator, please download or clone the repo, enter the *dnscrypt-proxy_config_generator/* folder and run the script:

```bash
# To generate a mix of both Anonymous DNS and Oblivious DNS over HTTPS routes:
./generate_config.sh

# To generate Anonymous DNS routes only:
./generate_config.sh --anon

# To generate Oblivious DNS over HTTPS routes only:
./generate_config.sh --odoh

# To generate standard (not anonymous) DNSCrypt routes:
./generate_config.sh --crypt
```

This will generate the toml config at ***/tmp/dnscrypt-proxy.toml*** by default, but this location can be changed by updating the *OUTPUT_TOML* variable in the *generate_config.sh* script.

By default, the script will choose up to 8 servers and 5 relays for both Anonymous DNS and Oblivious DNS over HTTPS (or 8 servers for standard DNSCrypt). You can change these limits by editing the *MAX_SERVERS* and *MAX_RELAYS* variables in the *functions.sh* script. 

On first run, the script will update server lists from web via the official dnscrypt-resolvers repo and save local copies to a .gitignored local folder. Subsiquent runs will use the locally downloaded server lists, but you can force the script to re-download the lists by removing this *dnscrypt-proxy_config_generator/resolvers/* folder.

## NOTE

This script starts with a toml file, *example-dnscrypt-proxy.toml*, which is the standard [example toml config](https://github.com/DNSCrypt/dnscrypt-proxy/blob/master/dnscrypt-proxy/example-dnscrypt-proxy.toml) modified to set the *listen_addresses* to *127.0.0.53:53*. You will need to make sure your /etc/resolv.conf or dns config points to 127.0.0.53 instead of 127.0.0.1 for dns resolving. I have another repo with a [script that will automatically install dnscrypt-proxy, generate a config with this project, and set your /etc/resolv.conf to use the dnscrypt-proxy resolving.](https://github.com/possiblynaught/install_anonymous_dnscrypt-proxy)

## TODO

- [x] Copy a base toml to dir
- [x] Finish standard dnscrypt config
- [x] Finish readme + guide
- [ ] Explore allowing ipv6?
- [ ] Debug pipefail error despite successful run
- [ ] Handle command line args better
